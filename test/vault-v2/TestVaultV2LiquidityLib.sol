// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../../lib/vault-v2/test/integration/MorphoVaultV1IntegrationTest.sol";
import {VaultV2LiquidityLib, VaultV2LiquidityLens} from "../../src/vault-v2/VaultV2LiquidityLib.sol";
import {IAdapter} from "../../lib/vault-v2/src/interfaces/IAdapter.sol";
import {IVaultV2} from "../../lib/vault-v2/src/interfaces/IVaultV2.sol";
import {IERC20} from "../../lib/vault-v2/src/interfaces/IERC20.sol";
import {MorphoVaultV1Adapter} from "../../lib/vault-v2/src/adapters/MorphoVaultV1Adapter.sol";
import {MorphoVaultV1AdapterFactory} from "../../lib/vault-v2/src/adapters/MorphoVaultV1AdapterFactory.sol";
import {MorphoMarketV1AdapterV2Factory} from "../../lib/vault-v2/src/adapters/MorphoMarketV1AdapterV2Factory.sol";
import {AdapterMock} from "../../lib/vault-v2/test/mocks/AdapterMock.sol";

// ---------------------------------------------------------------------------
// Wrapper - exposes internal VaultV2LiquidityLib functions as external view
// ---------------------------------------------------------------------------

contract LiquidityLibWrapper {
    function availableLiquidity(address vault) external view returns (uint256) {
        return VaultV2LiquidityLib.availableLiquidity(vault);
    }

    function adapterAvailableLiquidity(address adapter, bytes memory liqData) external view returns (uint256) {
        return VaultV2LiquidityLib.adapterAvailableLiquidity(adapter, liqData);
    }

    function maxWithdrawView(address vault, address owner) external view returns (uint256) {
        return VaultV2LiquidityLib.maxWithdrawView(vault, owner);
    }

    function maxRedeemView(address vault, address owner) external view returns (uint256) {
        return VaultV2LiquidityLib.maxRedeemView(vault, owner);
    }
}

// ---------------------------------------------------------------------------
// MorphoMarketV1AdapterV2 tests
// ---------------------------------------------------------------------------

contract TestVaultV2LiquidityLibMarketAdapter is MorphoVaultV1IntegrationTest {
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    LiquidityLibWrapper internal lib;
    VaultV2LiquidityLens internal lens;

    address internal marketAdapter;
    MarketParams internal mktParams1;
    MarketParams internal mktParams2;

    address internal immutable borrower = makeAddr("borrower");

    uint256 internal initialInIdle = 0.2e18 - 1;
    uint256 internal initialInMarket1 = 0.3e18;
    uint256 internal initialInMarket2 = 0.5e18;
    uint256 internal initialTotal = 1e18 - 1;

    function setUp() public virtual override {
        super.setUp();

        lib = new LiquidityLibWrapper();
        lens = new VaultV2LiquidityLens();

        address adaptiveCurveIrm = deployCode("AdaptiveCurveIrm.sol", abi.encode(address(morpho)));

        vm.startPrank(morphoOwner);
        morpho.enableIrm(adaptiveCurveIrm);
        // 0.8 ether is already enabled by the base setUp
        morpho.enableLltv(0.9 ether);
        vm.stopPrank();

        mktParams1 = MarketParams({
            loanToken: address(underlyingToken),
            collateralToken: address(collateralToken),
            irm: adaptiveCurveIrm,
            oracle: address(oracle),
            lltv: 0.8 ether
        });

        mktParams2 = MarketParams({
            loanToken: address(underlyingToken),
            collateralToken: address(collateralToken),
            irm: adaptiveCurveIrm,
            oracle: address(oracle),
            lltv: 0.9 ether
        });

        morpho.createMarket(mktParams1);
        morpho.createMarket(mktParams2);

        MorphoMarketV1AdapterV2Factory factory = new MorphoMarketV1AdapterV2Factory(address(morpho), adaptiveCurveIrm);
        marketAdapter = factory.createMorphoMarketV1AdapterV2(address(vault));

        // Add adapter to vault and set caps
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (marketAdapter)));
        vault.addAdapter(marketAdapter);

        bytes memory adapterIdData = abi.encode("this", marketAdapter);
        increaseAbsoluteCap(adapterIdData, type(uint128).max);
        increaseRelativeCap(adapterIdData, 1e18);

        bytes memory collIdData = abi.encode("collateralToken", mktParams1.collateralToken);
        increaseAbsoluteCap(collIdData, type(uint128).max);
        increaseRelativeCap(collIdData, 1e18);

        bytes memory mktIdData1 = abi.encode("this/marketParams", marketAdapter, mktParams1);
        increaseAbsoluteCap(mktIdData1, type(uint128).max);
        increaseRelativeCap(mktIdData1, 1e18);

        bytes memory mktIdData2 = abi.encode("this/marketParams", marketAdapter, mktParams2);
        increaseAbsoluteCap(mktIdData2, type(uint128).max);
        increaseRelativeCap(mktIdData2, 1e18);

        // Deposit and allocate
        assertEq(initialTotal, initialInIdle + initialInMarket1 + initialInMarket2);

        vault.deposit(initialTotal, address(this));

        vm.startPrank(allocator);
        vault.allocate(marketAdapter, abi.encode(mktParams1), initialInMarket1);
        vault.allocate(marketAdapter, abi.encode(mktParams2), initialInMarket2);
        vm.stopPrank();

        // Set liquidity adapter pointing at market1 as the exit market
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(marketAdapter, abi.encode(mktParams1));
    }

    // --- availableLiquidity ---

    function testAvailableLiquidity_NoLiquidityAdapter_OnlyIdle() public {
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(0), hex"");

        uint256 liq = lib.availableLiquidity(address(vault));
        assertEq(liq, initialInIdle, "should equal idle balance");
    }

    function testAvailableLiquidity_WithAdapter_FullLiquidity() public view {
        uint256 liq = lib.availableLiquidity(address(vault));
        assertEq(liq, initialInIdle + initialInMarket1, "idle + market1 supply");
    }

    function testAvailableLiquidity_WithAdapter_PartialBorrows(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, 1, initialInMarket1 - 1);

        deal(address(collateralToken), borrower, type(uint256).max);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(mktParams1, 2 * initialInMarket1, borrower, hex"");
        morpho.borrow(mktParams1, borrowAmount, 0, borrower, borrower);
        vm.stopPrank();

        uint256 liq = lib.availableLiquidity(address(vault));
        assertApproxEqAbs(liq, initialInIdle + initialInMarket1 - borrowAmount, 1, "partial borrows");
    }

    function testAvailableLiquidity_WithAdapter_FullBorrows() public {
        deal(address(collateralToken), borrower, type(uint256).max);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(mktParams1, 2 * initialInMarket1, borrower, hex"");
        morpho.borrow(mktParams1, initialInMarket1, 0, borrower, borrower);
        vm.stopPrank();

        uint256 liq = lib.availableLiquidity(address(vault));
        assertEq(liq, initialInIdle, "only idle remains when market fully borrowed");
    }

    function testAvailableLiquidity_EmptyLiquidityData() public {
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(marketAdapter, hex"");

        uint256 adapterLiq = lib.adapterAvailableLiquidity(marketAdapter, hex"");
        assertEq(adapterLiq, 0, "empty liqData returns 0");
    }

    /// @dev Covers the branch where market liquidity is capped by Morpho's actual token balance.
    function testAvailableLiquidity_WithAdapter_CappedByMorphoTokenBalance() public {
        deal(address(underlyingToken), address(morpho), 1);

        uint256 adapterLiq = lib.adapterAvailableLiquidity(marketAdapter, abi.encode(mktParams1));
        assertEq(adapterLiq, 1, "adapter liquidity should be capped by morpho token balance");

        uint256 liq = lib.availableLiquidity(address(vault));
        assertEq(liq, initialInIdle + 1, "total liquidity should include idle + capped adapter liquidity");
    }

    function testAvailableLiquidity_TwoMarkets_OnlyExitMarketCounts() public view {
        uint256 liq = lib.availableLiquidity(address(vault));
        assertEq(liq, initialInIdle + initialInMarket1, "only exit market counts");
    }

    // --- unknown adapter fallback ---

    function testAdapterAvailableLiquidity_UnknownAdapterReturnsZero() public {
        address unknownAdapter = address(new AdapterMock(address(vault)));
        uint256 adapterLiq = lib.adapterAvailableLiquidity(unknownAdapter, abi.encode(mktParams1));
        assertEq(adapterLiq, 0, "unknown adapter type should return 0");
    }

    // --- maxWithdrawView ---

    function testMaxWithdrawView_ZeroShares() public {
        address nobody = makeAddr("nobody");
        uint256 maxW = lib.maxWithdrawView(address(vault), nobody);
        assertEq(maxW, 0, "no shares returns 0");
    }

    function testMaxWithdrawView_LiquidityExceedsPosition(uint256 deposited) public {
        deposited = bound(deposited, 10, initialInIdle);

        address user = makeAddr("user");
        deal(address(underlyingToken), user, deposited);
        vm.startPrank(user);
        underlyingToken.approve(address(vault), deposited);
        vault.deposit(deposited, user);
        vm.stopPrank();

        uint256 maxW = lib.maxWithdrawView(address(vault), user);
        uint256 ownerAssets = vault.previewRedeem(vault.balanceOf(user));
        assertApproxEqAbs(maxW, ownerAssets, 1, "capped by position");
    }

    function testMaxWithdrawView_PositionExceedsLiquidity() public {
        deal(address(collateralToken), borrower, type(uint256).max);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(mktParams1, 2 * initialInMarket1, borrower, hex"");
        morpho.borrow(mktParams1, initialInMarket1, 0, borrower, borrower);
        vm.stopPrank();

        uint256 maxW = lib.maxWithdrawView(address(vault), address(this));
        assertApproxEqAbs(maxW, initialInIdle, 1, "capped by liquidity");
    }

    // --- maxRedeemView ---

    function testMaxRedeemView_Basic() public view {
        uint256 maxR = lib.maxRedeemView(address(vault), address(this));
        uint256 ownerShares = vault.balanceOf(address(this));
        uint256 liquidity = lib.availableLiquidity(address(vault));
        uint256 liquidityShares = vault.previewWithdraw(liquidity);
        uint256 expected = ownerShares < liquidityShares ? ownerShares : liquidityShares;
        assertApproxEqAbs(maxR, expected, 1, "min(ownerShares, liquidityShares)");
    }

    // --- round-trip: maxWithdrawView then actual withdraw ---

    function testMaxWithdrawView_ThenActualWithdrawSucceeds() public {
        uint256 maxW = lib.maxWithdrawView(address(vault), address(this));
        if (maxW == 0) return;

        vault.withdraw(maxW, address(this), address(this));
    }

    function testMaxRedeemView_ThenActualRedeemSucceeds() public {
        uint256 maxR = lib.maxRedeemView(address(vault), address(this));
        if (maxR == 0) return;

        vault.redeem(maxR, address(this), address(this));
    }

    // --- lens matches lib ---

    function testLens_MatchesLibrary() public view {
        assertEq(
            lens.availableLiquidity(address(vault)),
            lib.availableLiquidity(address(vault)),
            "lens.availableLiquidity"
        );
        assertEq(
            lens.maxWithdraw(address(vault), address(this)),
            lib.maxWithdrawView(address(vault), address(this)),
            "lens.maxWithdraw"
        );
        assertEq(
            lens.maxRedeem(address(vault), address(this)),
            lib.maxRedeemView(address(vault), address(this)),
            "lens.maxRedeem"
        );
    }

    /// @dev Covers the external lens passthrough for adapter-scoped liquidity.
    function testLens_AdapterLiquidity_MatchesLibrary() public view {
        bytes memory liqData = abi.encode(mktParams1);
        assertEq(
            lens.adapterLiquidity(marketAdapter, liqData),
            lib.adapterAvailableLiquidity(marketAdapter, liqData),
            "lens.adapterLiquidity"
        );
    }
}

// ---------------------------------------------------------------------------
// MorphoVaultV1Adapter tests
// ---------------------------------------------------------------------------

contract TestVaultV2LiquidityLibVaultAdapter is MorphoVaultV1IntegrationTest {
    using MorphoBalancesLib for IMorpho;

    LiquidityLibWrapper internal lib;

    address internal immutable borrower = makeAddr("borrower");

    uint256 internal initialInIdle = 0.3e18 - 1;
    uint256 internal initialInMorphoVaultV1 = 0.7e18;
    uint256 internal initialTotal = 1e18 - 1;

    function setUp() public virtual override {
        super.setUp();

        lib = new LiquidityLibWrapper();

        assertEq(initialTotal, initialInIdle + initialInMorphoVaultV1);

        vault.deposit(initialTotal, address(this));

        setSupplyQueueAllMarkets();

        vm.prank(allocator);
        vault.allocate(address(morphoVaultV1Adapter), hex"", initialInMorphoVaultV1);

        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(morphoVaultV1Adapter), hex"");
    }

    // --- availableLiquidity ---

    function testAvailableLiquidity_VaultV1Adapter_FullLiquidity() public view {
        uint256 liq = lib.availableLiquidity(address(vault));
        assertApproxEqAbs(liq, initialTotal, 1, "full liquidity via V1 maxWithdraw");
    }

    function testAvailableLiquidity_VaultV1Adapter_NoLiquidityAdapterSet() public {
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(0), hex"");

        uint256 liq = lib.availableLiquidity(address(vault));
        assertEq(liq, initialInIdle, "only idle without adapter");
    }

    function testAvailableLiquidity_VaultV1Adapter_PartialBorrows() public {
        uint256 borrowAmount = initialInMorphoVaultV1 / 2;

        deal(address(collateralToken), borrower, type(uint256).max);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(allMarketParams[0], 2 * initialInMorphoVaultV1, borrower, hex"");
        morpho.borrow(allMarketParams[0], borrowAmount, 0, borrower, borrower);
        vm.stopPrank();

        uint256 liq = lib.availableLiquidity(address(vault));
        assertLt(liq, initialTotal, "liquidity reduced by borrows");
        assertGt(liq, initialInIdle, "still more than idle");
    }

    // --- maxWithdrawView ---

    function testMaxWithdrawView_VaultV1Adapter(uint256 deposited) public {
        deposited = bound(deposited, 1e8, 3e18);

        address user = makeAddr("user");
        deal(address(underlyingToken), user, deposited);
        vm.startPrank(user);
        underlyingToken.approve(address(vault), deposited);
        vault.deposit(deposited, user);
        vm.stopPrank();

        uint256 maxW = lib.maxWithdrawView(address(vault), user);
        uint256 ownerAssets = vault.previewRedeem(vault.balanceOf(user));
        uint256 liquidity = lib.availableLiquidity(address(vault));
        uint256 expected = ownerAssets < liquidity ? ownerAssets : liquidity;
        assertApproxEqAbs(maxW, expected, 1, "bounded correctly");
    }

    // --- maxRedeemView ---

    function testMaxRedeemView_VaultV1Adapter() public view {
        uint256 maxR = lib.maxRedeemView(address(vault), address(this));
        uint256 ownerShares = vault.balanceOf(address(this));
        uint256 liquidity = lib.availableLiquidity(address(vault));
        uint256 liquidityShares = vault.previewWithdraw(liquidity);
        uint256 expected = ownerShares < liquidityShares ? ownerShares : liquidityShares;
        assertApproxEqAbs(maxR, expected, 1, "bounded correctly");
    }

    // --- round-trip ---

    function testMaxWithdrawView_VaultV1Adapter_ThenActualWithdraw() public {
        uint256 maxW = lib.maxWithdrawView(address(vault), address(this));
        if (maxW == 0) return;

        vault.withdraw(maxW, address(this), address(this));
    }
}

// ---------------------------------------------------------------------------
// Nested V2-on-V2 tests
// ---------------------------------------------------------------------------

contract TestVaultV2LiquidityLibNested is MorphoVaultV1IntegrationTest {
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    LiquidityLibWrapper internal lib;
    VaultV2LiquidityLens internal lens;
    MorphoVaultV1AdapterFactory internal extraAdapterFactory;

    VaultV2 internal outerVault;
    MorphoVaultV1Adapter internal outerAdapter;

    address internal immutable borrower = makeAddr("borrower");

    function setUp() public virtual override {
        super.setUp();

        lib = new LiquidityLibWrapper();
        lens = new VaultV2LiquidityLens();
        extraAdapterFactory = new MorphoVaultV1AdapterFactory();

        // Inner vault (from base) -> MorphoVaultV1Adapter -> MetaMorpho
        // Outer vault -> MorphoVaultV1Adapter -> inner vault (V2)

        outerVault = new VaultV2(owner, address(underlyingToken));
        vm.label(address(outerVault), "outerVault");

        outerAdapter = MorphoVaultV1Adapter(
            extraAdapterFactory.createMorphoVaultV1Adapter(address(outerVault), address(vault))
        );
        vm.label(address(outerAdapter), "outerAdapter");

        // Configure outerVault
        vm.startPrank(owner);
        outerVault.setCurator(curator);
        vm.stopPrank();

        vm.prank(curator);
        outerVault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (allocator, true)));
        outerVault.setIsAllocator(allocator, true);

        vm.prank(curator);
        outerVault.submit(abi.encodeCall(IVaultV2.addAdapter, (address(outerAdapter))));
        outerVault.addAdapter(address(outerAdapter));

        vm.prank(allocator);
        outerVault.setMaxRate(200e16 / uint256(365 days));

        bytes memory idData = abi.encode("this", address(outerAdapter));

        vm.prank(curator);
        outerVault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, type(uint128).max)));
        outerVault.increaseAbsoluteCap(idData, type(uint128).max);

        vm.prank(curator);
        outerVault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, 1e18)));
        outerVault.increaseRelativeCap(idData, 1e18);

        vm.prank(allocator);
        outerVault.setLiquidityAdapterAndData(address(outerAdapter), "");

        // Set liquidity adapter on inner vault
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(morphoVaultV1Adapter), "");

        setSupplyQueueAllMarkets();

        // Deposit and allocate through the chain
        uint256 deposited = 1e18;
        deal(address(underlyingToken), address(this), deposited);
        underlyingToken.approve(address(outerVault), deposited);
        outerVault.deposit(deposited, address(this));
    }

    // --- availableLiquidity ---

    function testAvailableLiquidity_Nested_Recurses() public view {
        uint256 outerLiq = lib.availableLiquidity(address(outerVault));
        uint256 innerLiq = lib.availableLiquidity(address(vault));

        assertGt(outerLiq, 0, "outer liquidity > 0");
        assertLe(outerLiq, innerLiq, "outer <= inner liquidity");
    }

    function testAvailableLiquidity_Nested_PartialBorrows() public {
        uint256 borrowAmount = 0.3e18;

        deal(address(collateralToken), borrower, type(uint256).max);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(allMarketParams[0], 2e18, borrower, hex"");
        morpho.borrow(allMarketParams[0], borrowAmount, 0, borrower, borrower);
        vm.stopPrank();

        uint256 outerLiq = lib.availableLiquidity(address(outerVault));
        uint256 innerLiq = lib.availableLiquidity(address(vault));

        assertLe(outerLiq, innerLiq, "outer <= inner after borrows");
    }

    // --- maxWithdrawView ---

    function testMaxWithdrawView_Nested() public view {
        uint256 maxW = lib.maxWithdrawView(address(outerVault), address(this));
        uint256 ownerAssets = outerVault.previewRedeem(outerVault.balanceOf(address(this)));
        assertLe(maxW, ownerAssets, "bounded by position");
    }

    // --- maxRedeemView ---

    function testMaxRedeemView_Nested() public view {
        uint256 maxR = lib.maxRedeemView(address(outerVault), address(this));
        uint256 ownerShares = outerVault.balanceOf(address(this));
        assertLe(maxR, ownerShares, "bounded by shares");
    }

    // --- round-trip ---

    function testMaxWithdrawView_Nested_ThenActualWithdraw() public {
        uint256 maxW = lib.maxWithdrawView(address(outerVault), address(this));
        if (maxW == 0) return;

        outerVault.withdraw(maxW, address(this), address(this));
    }

    // --- lens matches lib ---

    function testLens_Nested_MatchesLibrary() public view {
        assertEq(
            lens.availableLiquidity(address(outerVault)),
            lib.availableLiquidity(address(outerVault)),
            "lens.availableLiquidity"
        );
        assertEq(
            lens.maxWithdraw(address(outerVault), address(this)),
            lib.maxWithdrawView(address(outerVault), address(this)),
            "lens.maxWithdraw"
        );
        assertEq(
            lens.maxRedeem(address(outerVault), address(this)),
            lib.maxRedeemView(address(outerVault), address(this)),
            "lens.maxRedeem"
        );
    }
}

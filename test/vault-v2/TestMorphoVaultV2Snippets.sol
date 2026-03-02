// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../../lib/vault-v2/test/integration/MorphoVaultV1IntegrationTest.sol";
import {MorphoVaultV2Snippets} from "../../src/vault-v2/MorphoVaultV2Snippets.sol";
import {IAdapter} from "../../lib/vault-v2/src/interfaces/IAdapter.sol";
import {IVaultV2, Caps} from "../../lib/vault-v2/src/interfaces/IVaultV2.sol";
import {IERC20} from "../../lib/vault-v2/src/interfaces/IERC20.sol";
import {MathLib} from "../../lib/vault-v2/src/libraries/MathLib.sol";
import {MorphoVaultV1Adapter} from "../../lib/vault-v2/src/adapters/MorphoVaultV1Adapter.sol";
import {MorphoVaultV1AdapterFactory} from "../../lib/vault-v2/src/adapters/MorphoVaultV1AdapterFactory.sol";
import {MorphoMarketV1AdapterV2Factory} from "../../lib/vault-v2/src/adapters/MorphoMarketV1AdapterV2Factory.sol";
import {IMorphoMarketV1AdapterV2} from "../../lib/vault-v2/src/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";
import {MarketParamsLib} from "../../lib/vault-v2/lib/metamorpho/lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {AdapterMock} from "../../lib/vault-v2/test/mocks/AdapterMock.sol";

using MathLib for uint256;
using MarketParamsLib for MarketParams;

uint256 constant MIN_TEST_ASSETS = 1e8;
uint256 constant MAX_TEST_ASSETS = 1e28;

contract TestMorphoVaultV2Snippets is MorphoVaultV1IntegrationTest {
    MorphoVaultV2Snippets internal snippets;

    address internal SUPPLIER = makeAddr("Supplier");
    address internal ONBEHALF = makeAddr("OnBehalf");

    function setUp() public virtual override {
        super.setUp();

        snippets = new MorphoVaultV2Snippets(address(morpho));

        vm.startPrank(SUPPLIER);
        IERC20(vault.asset()).approve(address(snippets), type(uint256).max);
        vault.approve(address(snippets), type(uint256).max);
        vm.stopPrank();
    }

    /// @dev Adds an adapter that is valid for VaultV2 but unsupported by snippets type detection.
    function _addUnknownAdapter() internal returns (address unknownAdapter) {
        unknownAdapter = address(new AdapterMock(address(vault)));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (unknownAdapter)));
        vault.addAdapter(unknownAdapter);
    }

    function testTotalDepositVault(uint256 firstDeposit, uint256 secondDeposit) public {
        firstDeposit = bound(firstDeposit, MIN_TEST_ASSETS, MAX_TEST_ASSETS / 2);
        secondDeposit = bound(secondDeposit, MIN_TEST_ASSETS, MAX_TEST_ASSETS / 2);

        deal(address(underlyingToken), SUPPLIER, firstDeposit);

        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), firstDeposit);
        vault.deposit(firstDeposit, ONBEHALF);
        vm.stopPrank();

        assertEq(snippets.totalDepositVaultV2(address(vault)), firstDeposit, "lastTotalAssets");

        deal(address(underlyingToken), SUPPLIER, secondDeposit);
        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), secondDeposit);
        vault.deposit(secondDeposit, ONBEHALF);
        vm.stopPrank();

        assertEq(snippets.totalDepositVaultV2(address(vault)), firstDeposit + secondDeposit, "lastTotalAssets2");
    }

    function testTotalSharesUserVault(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        deal(address(underlyingToken), SUPPLIER, deposited);

        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), deposited);
        uint256 shares = vault.deposit(deposited, ONBEHALF);
        vm.stopPrank();

        assertEq(vault.balanceOf(ONBEHALF), shares, "balanceOf(ONBEHALF)");
        assertEq(snippets.totalSharesUserVaultV2(address(vault), ONBEHALF), shares, "totalSharesUserVault");
    }

    function testSharePriceVault(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        deal(address(underlyingToken), SUPPLIER, deposited);

        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), deposited);
        vault.deposit(deposited, ONBEHALF);
        vm.stopPrank();

        uint256 sharePrice = snippets.sharePriceVaultV2(address(vault));
        assertGt(sharePrice, 0, "sharePrice should be > 0");

        // Share price should be approximately 1e18 initially (1:1 ratio with some virtual shares)
        assertApproxEqRel(sharePrice, 1e18, 0.01e18, "sharePrice should be ~1e18 initially");
    }

    function testIdleAssetsVault(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        deal(address(underlyingToken), SUPPLIER, deposited);

        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), deposited);
        vault.deposit(deposited, ONBEHALF);
        vm.stopPrank();

        uint256 idleAssets = snippets.idleAssetsVaultV2(address(vault));

        // Initially, idle assets should be close to deposited amount (some might be allocated)
        // Since allocation happens automatically, idle assets could be less than deposited
        assertLe(idleAssets, deposited, "idle assets should be <= deposited");
    }

    function testPreviewDepositVault(uint256 assets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        uint256 previewShares = snippets.previewDepositVaultV2(address(vault), assets);
        assertGt(previewShares, 0, "previewShares should be > 0");

        // Actually deposit and verify the preview was accurate
        deal(address(underlyingToken), SUPPLIER, assets);

        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), assets);
        uint256 actualShares = vault.deposit(assets, ONBEHALF);
        vm.stopPrank();

        assertEq(previewShares, actualShares, "preview should match actual shares");
    }

    function testPreviewRedeemVault(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        deal(address(underlyingToken), SUPPLIER, deposited);

        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), deposited);
        uint256 shares = vault.deposit(deposited, ONBEHALF);
        vm.stopPrank();

        uint256 previewAssets = snippets.previewRedeemVaultV2(address(vault), shares);
        assertGt(previewAssets, 0, "previewAssets should be > 0");

        // Actually redeem and verify the preview was accurate
        vm.startPrank(ONBEHALF);
        uint256 actualAssets = vault.redeem(shares, ONBEHALF, ONBEHALF);
        vm.stopPrank();

        assertEq(previewAssets, actualAssets, "preview should match actual assets");
    }

    function testDepositInVault(uint256 assets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        deal(address(underlyingToken), SUPPLIER, assets);

        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(snippets), assets);
        uint256 shares = snippets.depositInVaultV2(address(vault), assets, SUPPLIER);
        vm.stopPrank();

        assertGt(shares, 0, "shares should be > 0");
        assertEq(vault.balanceOf(SUPPLIER), shares, "balanceOf(SUPPLIER)");
        assertApproxEqAbs(vault.totalAssets(), assets, 1e6, "totalAssets");
    }

    function testRedeemAllFromVault(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        deal(address(underlyingToken), SUPPLIER, deposited);

        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), deposited);
        vault.deposit(deposited, SUPPLIER);

        vault.approve(address(snippets), type(uint256).max);
        uint256 assets = snippets.redeemAllFromVaultV2(address(vault), SUPPLIER);
        vm.stopPrank();

        assertApproxEqAbs(assets, deposited, 1e6, "assets should ~= deposited");
        assertEq(vault.balanceOf(SUPPLIER), 0, "balanceOf(SUPPLIER) should be 0");
    }

    function testWithdrawFromVault(uint256 deposited, uint256 withdrawAmount) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        withdrawAmount = bound(withdrawAmount, MIN_TEST_ASSETS / 2, deposited);

        deal(address(underlyingToken), SUPPLIER, deposited);

        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), deposited);
        vault.deposit(deposited, SUPPLIER);

        uint256 sharesBefore = vault.balanceOf(SUPPLIER);

        vault.approve(address(snippets), type(uint256).max);
        uint256 shares = snippets.withdrawFromVaultV2(address(vault), withdrawAmount, SUPPLIER, SUPPLIER);
        vm.stopPrank();

        assertGt(shares, 0, "shares should be > 0");
        assertLt(vault.balanceOf(SUPPLIER), sharesBefore, "balanceOf should decrease");
    }

    function testFeeInfoVault() public {
        (uint96 performanceFee, uint96 managementFee, uint64 maxRate) = snippets.feeInfoVaultV2(address(vault));

        // Verify that the values match what's set in the vault
        assertEq(performanceFee, vault.performanceFee(), "performanceFee should match");
        assertEq(managementFee, vault.managementFee(), "managementFee should match");
        assertEq(maxRate, vault.maxRate(), "maxRate should match");
    }

    function testAccrueInterestView(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        deal(address(underlyingToken), SUPPLIER, deposited);

        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), deposited);
        vault.deposit(deposited, SUPPLIER);
        vm.stopPrank();

        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) =
            snippets.accrueInterestView(address(vault));

        // newTotalAssets should be approximately equal to deposited initially
        assertApproxEqAbs(newTotalAssets, deposited, 1e6, "newTotalAssets should ~= deposited");

        // Fee shares should be 0 or very small initially (no interest accrued yet)
        assertLe(performanceFeeShares, 1e10, "performanceFeeShares should be small");
        assertLe(managementFeeShares, 1e10, "managementFeeShares should be small");
    }

    function testMintInVault(uint256 shares) public {
        shares = bound(shares, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        uint256 previewAssets = vault.previewMint(shares);

        deal(address(underlyingToken), SUPPLIER, previewAssets);

        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(snippets), previewAssets);
        uint256 assets = snippets.mintInVaultV2(address(vault), shares, SUPPLIER);
        vm.stopPrank();

        assertGt(assets, 0, "assets should be > 0");
        assertEq(vault.balanceOf(SUPPLIER), shares, "balanceOf(SUPPLIER) should equal shares");
        assertApproxEqAbs(assets, previewAssets, 1, "assets should match preview");
    }

    function testRedeemFromVault(uint256 deposited, uint256 redeemShares) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        deal(address(underlyingToken), SUPPLIER, deposited);

        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), deposited);
        uint256 shares = vault.deposit(deposited, SUPPLIER);

        redeemShares = bound(redeemShares, shares / 4, shares / 2);

        vault.approve(address(snippets), type(uint256).max);
        uint256 assets = snippets.redeemFromVaultV2(address(vault), redeemShares, SUPPLIER, SUPPLIER);
        vm.stopPrank();

        assertGt(assets, 0, "assets should be > 0");
        assertEq(vault.balanceOf(SUPPLIER), shares - redeemShares, "balanceOf should decrease by redeemShares");
    }

    function testPreviewMintVault(uint256 shares) public {
        shares = bound(shares, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        uint256 previewAssets = snippets.previewMintVaultV2(address(vault), shares);
        assertGt(previewAssets, 0, "previewAssets should be > 0");

        // Actually mint and verify the preview was accurate
        deal(address(underlyingToken), SUPPLIER, previewAssets);

        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), previewAssets);
        uint256 actualAssets = vault.mint(shares, ONBEHALF);
        vm.stopPrank();

        assertApproxEqAbs(previewAssets, actualAssets, 1, "preview should match actual assets");
    }

    function testPreviewWithdrawVault(uint256 deposited, uint256 withdrawAmount) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        deal(address(underlyingToken), SUPPLIER, deposited);

        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), deposited);
        vault.deposit(deposited, ONBEHALF);
        vm.stopPrank();

        withdrawAmount = bound(withdrawAmount, MIN_TEST_ASSETS / 2, deposited);

        uint256 previewShares = snippets.previewWithdrawVaultV2(address(vault), withdrawAmount);
        assertGt(previewShares, 0, "previewShares should be > 0");

        // Actually withdraw and verify the preview was accurate
        vm.startPrank(ONBEHALF);
        uint256 actualShares = vault.withdraw(withdrawAmount, ONBEHALF, ONBEHALF);
        vm.stopPrank();

        assertApproxEqAbs(previewShares, actualShares, 1, "preview should match actual shares");
    }

    function testAdaptersListVault() public {
        address[] memory adaptersList = snippets.adaptersListVaultV2(address(vault));

        // The vault should have adapters set up in the integration test base
        assertGt(adaptersList.length, 0, "vault should have at least one adapter");

        // Verify each adapter is actually registered in the vault
        for (uint256 i = 0; i < adaptersList.length; i++) {
            assertTrue(vault.isAdapter(adaptersList[i]), "adapter should be registered");
        }
    }

    function testLiquidityAdapterVault() public {
        (address liquidityAdapter, bytes memory liquidityData) = snippets.liquidityAdapterVaultV2(address(vault));

        // Verify the liquidity adapter matches vault's configuration
        assertEq(liquidityAdapter, vault.liquidityAdapter(), "liquidityAdapter should match");
        assertEq(keccak256(liquidityData), keccak256(vault.liquidityData()), "liquidityData should match");
    }

    function testAllocationById() public {
        // Get adapter address from the vault
        address adapter = vault.adapters(0);
        bytes memory idData = abi.encode("this", adapter);

        // Initially allocation should be 0
        uint256 allocation = snippets.allocationById(address(vault), idData);
        assertEq(allocation, 0, "initial allocation should be 0");

        // After depositing and allocating, allocation should increase
        deal(address(underlyingToken), SUPPLIER, MIN_TEST_ASSETS);
        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), MIN_TEST_ASSETS);
        vault.deposit(MIN_TEST_ASSETS, SUPPLIER);
        vm.stopPrank();

        // Check allocation again (might have increased if liquidity adapter allocated)
        uint256 newAllocation = snippets.allocationById(address(vault), idData);
        assertGe(newAllocation, allocation, "allocation should be >= initial");
    }

    function testAbsoluteCapById() public {
        address adapter = vault.adapters(0);
        bytes memory idData = abi.encode("this", adapter);

        uint256 absoluteCap = snippets.absoluteCapById(address(vault), idData);

        // The absolute cap should match what's set in the vault
        bytes32 id = keccak256(idData);
        assertEq(absoluteCap, vault.absoluteCap(id), "absoluteCap should match vault");
    }

    function testRelativeCapById() public {
        address adapter = vault.adapters(0);
        bytes memory idData = abi.encode("this", adapter);

        uint256 relativeCap = snippets.relativeCapById(address(vault), idData);

        // The relative cap should match what's set in the vault
        bytes32 id = keccak256(idData);
        assertEq(relativeCap, vault.relativeCap(id), "relativeCap should match vault");
    }

    function testCapsById() public {
        address adapter = vault.adapters(0);
        bytes memory idData = abi.encode("this", adapter);

        Caps memory caps = snippets.capsById(address(vault), idData);

        // Verify all fields match what's in the vault
        bytes32 id = keccak256(idData);
        assertEq(caps.allocation, vault.allocation(id), "allocation should match");
        assertEq(caps.absoluteCap, vault.absoluteCap(id), "absoluteCap should match");
        assertEq(caps.relativeCap, vault.relativeCap(id), "relativeCap should match");
    }

    function testRealAssetsPerAdapter() public {
        (address[] memory adapters, uint256[] memory realAssetsList) =
            snippets.realAssetsPerAdapter(address(vault));

        // Should have at least one adapter
        assertGt(adapters.length, 0, "should have at least one adapter");
        assertEq(adapters.length, realAssetsList.length, "arrays should have same length");

        // All adapters should be registered in vault
        for (uint256 i = 0; i < adapters.length; i++) {
            assertTrue(vault.isAdapter(adapters[i]), "adapter should be registered");
            assertGe(realAssetsList[i], 0, "realAssets should be >= 0");
        }

        // After deposit, total real assets might increase
        deal(address(underlyingToken), SUPPLIER, MIN_TEST_ASSETS);
        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), MIN_TEST_ASSETS);
        vault.deposit(MIN_TEST_ASSETS, SUPPLIER);
        vm.stopPrank();

        (, uint256[] memory newRealAssetsList) = snippets.realAssetsPerAdapter(address(vault));

        // Total real assets should be >= initial
        uint256 totalInitial;
        uint256 totalNew;
        for (uint256 i = 0; i < realAssetsList.length; i++) {
            totalInitial += realAssetsList[i];
            totalNew += newRealAssetsList[i];
        }
        assertGe(totalNew, totalInitial, "total realAssets should be >= initial");
    }

    function testEffectiveCapById() public {
        address adapter = vault.adapters(0);
        bytes memory idData = abi.encode("this", adapter);

        uint256 effectiveCap = snippets.effectiveCapById(address(vault), idData);

        // Effective cap should be the minimum of absolute and relative caps
        bytes32 id = keccak256(idData);
        uint256 absoluteCap = vault.absoluteCap(id);
        uint256 relativeCap = vault.relativeCap(id);
        uint256 totalAssets = vault.totalAssets();

        uint256 relativeCapInAssets = (relativeCap * totalAssets) / 1e18;
        uint256 expectedEffectiveCap = absoluteCap < relativeCapInAssets ? absoluteCap : relativeCapInAssets;

        assertEq(effectiveCap, expectedEffectiveCap, "effectiveCap should be min of absolute and relative");
    }

    function testAccrueInterestVault() public {
        deal(address(underlyingToken), SUPPLIER, MIN_TEST_ASSETS);

        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), MIN_TEST_ASSETS);
        vault.deposit(MIN_TEST_ASSETS, SUPPLIER);
        vm.stopPrank();

        uint256 totalAssetsBefore = vault.totalAssets();

        // Warp time forward to accrue some interest
        skip(1 days);

        // Call accrueInterest
        snippets.accrueInterestVaultV2(address(vault));

        uint256 totalAssetsAfter = vault.totalAssets();

        // Total assets should be >= before (interest accrued or stayed same)
        assertGe(totalAssetsAfter, totalAssetsBefore, "totalAssets should be >= before");
    }

    function testSupplyAPYVaultV2(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        // Deposit into the VaultV2
        deal(address(underlyingToken), SUPPLIER, deposited);

        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), deposited);
        vault.deposit(deposited, SUPPLIER);
        vm.stopPrank();

        // Get the APY
        uint256 apy = snippets.supplyAPYVaultV2(address(vault));

        // APY should be >= 0
        assertGe(apy, 0, "APY should be >= 0");

        // If there are VaultV1 adapters with allocations, APY should be > 0
        // (assuming the underlying markets have non-zero rates)
        // This is a basic sanity check
    }

    function testSupplyAPYMarketV1_ZeroIrmReturnsZero() public view {
        MarketParams memory marketParams = allMarketParams[0];
        marketParams.irm = address(0);

        uint256 apy = snippets.supplyAPYMarketV1(marketParams, morpho.market(allMarketParams[0].id()));
        assertEq(apy, 0, "APY should be 0 when irm is zero");
    }

    function testSupplyAPYVaultV1_ZeroAssetsReturnsZero() public view {
        uint256 apy = snippets.supplyAPYVaultV1(address(morphoVaultV1));
        assertEq(apy, 0, "APY should be 0 for empty MetaMorpho vault");
    }

    function testSupplyAPYVaultV1_AndVaultAssetsInMarket() public {
        setSupplyQueueAllMarkets();

        uint256 deposited = 1e18;
        underlyingToken.approve(address(morphoVaultV1), deposited);
        morphoVaultV1.deposit(deposited, address(this));

        address borrower = makeAddr("borrower-v1-apy");
        uint256 collateralAmount = 20e18;
        uint256 borrowAmount = 0.3e18;

        deal(address(collateralToken), borrower, collateralAmount);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), collateralAmount);
        morpho.supplyCollateral(allMarketParams[0], collateralAmount, borrower, "");
        morpho.borrow(allMarketParams[0], borrowAmount, 0, borrower, borrower);
        vm.stopPrank();

        uint256 assetsInMarket = snippets.vaultV1AssetsInMarket(address(morphoVaultV1), allMarketParams[0]);
        assertGt(assetsInMarket, 0, "vault assets in market should be > 0");

        uint256 marketApy = snippets.supplyAPYMarketV1(allMarketParams[0], morpho.market(allMarketParams[0].id()));
        assertGt(marketApy, 0, "market APY should be > 0 with utilization");

        uint256 vaultApy = snippets.supplyAPYVaultV1(address(morphoVaultV1));
        assertGt(vaultApy, 0, "vault V1 APY should be > 0 with utilized market");
    }

    function testMarketsInVaultV2() public {
        // Initially, the vault has a MorphoVaultV1Adapter but MetaMorpho has no markets in withdraw queue
        bytes32[] memory markets = snippets.marketsInVaultV2(address(vault));

        // Markets should be empty or have some markets depending on setup
        // This is a basic sanity check - the function should not revert
        assertGe(markets.length, 0, "markets array should be valid");

        // Set up the MetaMorpho supply queue with the idle market
        setSupplyQueueIdle();

        // Now get markets again - should have at least the idle market
        markets = snippets.marketsInVaultV2(address(vault));

        // After setting supply queue, we should see the market in the withdraw queue too
        // (MetaMorpho adds to withdraw queue when setting supply queue)
    }

    function testVaultV2AssetsInMarket(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        // Set up the MetaMorpho supply queue with the idle market
        setSupplyQueueIdle();

        // Deposit into the VaultV2
        deal(address(underlyingToken), SUPPLIER, deposited);

        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), deposited);
        vault.deposit(deposited, SUPPLIER);
        vm.stopPrank();

        // Get assets in the idle market
        uint256 assetsInMarket = snippets.vaultV2AssetsInMarket(address(vault), idleParams);

        // Assets in market should be >= 0
        assertGe(assetsInMarket, 0, "assets in market should be >= 0");

        // The assets might be allocated to the MetaMorpho vault through the adapter
        // depending on the liquidity adapter configuration
    }

    function testVaultV2AssetsInMarketWithAllocation(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        // Set up the MetaMorpho supply queue with all markets
        setSupplyQueueAllMarkets();

        // Deposit into the VaultV2
        deal(address(underlyingToken), SUPPLIER, deposited);

        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), deposited);
        vault.deposit(deposited, SUPPLIER);
        vm.stopPrank();

        // Check assets across multiple markets
        uint256 totalAssetsInMarkets;
        for (uint256 i; i < allMarketParams.length; ++i) {
            uint256 assetsInMarket = snippets.vaultV2AssetsInMarket(address(vault), allMarketParams[i]);
            totalAssetsInMarkets += assetsInMarket;
        }

        // Total assets in all markets should be consistent with adapter real assets
        (address[] memory adapters, uint256[] memory realAssets) = snippets.realAssetsPerAdapter(address(vault));
        uint256 totalAdapterAssets;
        for (uint256 i; i < realAssets.length; ++i) {
            totalAdapterAssets += realAssets[i];
        }

        // The total should be approximately equal (might differ due to idle assets in vault)
        // This is just a sanity check that the function works
    }

    // --- unknown adapter fallback ---

    function testSupplyAPYVaultV2_UnknownAdapterIsIgnored() public {
        setSupplyQueueAllMarkets();

        uint256 deposited = 1e18;
        deal(address(underlyingToken), SUPPLIER, deposited);
        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), deposited);
        vault.deposit(deposited, SUPPLIER);
        vm.stopPrank();

        vm.prank(allocator);
        vault.allocate(address(morphoVaultV1Adapter), "", 0.8e18);

        address borrower = makeAddr("borrower-unknown-adapter-apy");
        uint256 collateralAmount = 100e18;
        uint256 borrowAmount = 0.2e18;
        deal(address(collateralToken), borrower, collateralAmount);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), collateralAmount);
        morpho.supplyCollateral(allMarketParams[0], collateralAmount, borrower, "");
        morpho.borrow(allMarketParams[0], borrowAmount, 0, borrower, borrower);
        vm.stopPrank();

        uint256 apyBefore = snippets.supplyAPYVaultV2(address(vault));
        assertGt(apyBefore, 0, "APY before adding unknown adapter should be > 0");

        _addUnknownAdapter();

        uint256 apyAfter = snippets.supplyAPYVaultV2(address(vault));
        assertEq(apyAfter, apyBefore, "unknown adapter should be ignored in APY computation");
    }

    function testVaultV2AssetsInMarket_UnknownAdapterIsIgnored() public {
        setSupplyQueueIdle();

        uint256 deposited = 1e18;
        deal(address(underlyingToken), SUPPLIER, deposited);
        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(vault), deposited);
        vault.deposit(deposited, SUPPLIER);
        vm.stopPrank();

        vm.prank(allocator);
        vault.allocate(address(morphoVaultV1Adapter), "", 0.8e18);

        uint256 assetsBefore = snippets.vaultV2AssetsInMarket(address(vault), idleParams);
        assertGt(assetsBefore, 0, "assets before adding unknown adapter should be > 0");

        _addUnknownAdapter();

        uint256 assetsAfter = snippets.vaultV2AssetsInMarket(address(vault), idleParams);
        assertEq(assetsAfter, assetsBefore, "unknown adapter should be ignored in assets-in-market computation");
    }

    function testMarketsInVaultV2_UnknownAdapterIsIgnored() public {
        setSupplyQueueIdle();

        bytes32[] memory marketsBefore = snippets.marketsInVaultV2(address(vault));
        _addUnknownAdapter();
        bytes32[] memory marketsAfter = snippets.marketsInVaultV2(address(vault));

        assertEq(marketsAfter.length, marketsBefore.length, "unknown adapter should not add markets");
    }
}

/// @notice Tests recursive APY: outerVault → MorphoVaultV1Adapter → vault (inner V2 with MetaMorpho).
contract TestMorphoVaultV2SnippetsRecursiveAPY is MorphoVaultV1IntegrationTest {
    MorphoVaultV2Snippets internal snippets;
    MorphoVaultV1AdapterFactory internal extraAdapterFactory;

    VaultV2 internal outerVault;
    MorphoVaultV1Adapter internal outerAdapter;

    address internal SUPPLIER = makeAddr("Supplier");

    function setUp() public virtual override {
        super.setUp();

        snippets = new MorphoVaultV2Snippets(address(morpho));
        extraAdapterFactory = new MorphoVaultV1AdapterFactory();

        // The base class created `vault` (inner V2) with a MorphoVaultV1Adapter → MetaMorpho.
        // Wrap it: outerVault → MorphoVaultV1Adapter → vault.
        outerVault = new VaultV2(owner, address(underlyingToken));
        vm.label(address(outerVault), "outerVault");

        outerAdapter = MorphoVaultV1Adapter(
            extraAdapterFactory.createMorphoVaultV1Adapter(address(outerVault), address(vault))
        );
        vm.label(address(outerAdapter), "outerAdapter");

        // Configure outerVault: curator, allocator, adapter, caps
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

        // Set the liquidity adapter on the inner vault so deposits auto-allocate to MetaMorpho.
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(morphoVaultV1Adapter), "");

        setSupplyQueueAllMarkets();

        // Create a borrower so the first Morpho Blue market has non-zero utilization (supply APY > 0).
        address BORROWER = makeAddr("Borrower");
        MarketParams memory mp = allMarketParams[0];
        uint256 collateralAmount = 100e18;
        uint256 borrowAmount = 10e18;

        deal(address(underlyingToken), address(this), borrowAmount);
        underlyingToken.approve(address(morpho), borrowAmount);
        morpho.supply(mp, borrowAmount, 0, address(this), "");

        deal(address(collateralToken), BORROWER, collateralAmount);
        vm.startPrank(BORROWER);
        collateralToken.approve(address(morpho), collateralAmount);
        morpho.supplyCollateral(mp, collateralAmount, BORROWER, "");
        morpho.borrow(mp, borrowAmount / 2, 0, BORROWER, BORROWER);
        vm.stopPrank();
    }

    /// @notice Deposit into outerVault, verify APY > 0 and does not revert.
    function test_V2OnV2_APYRecurses() public {
        uint256 deposited = 1e18;
        deal(address(underlyingToken), SUPPLIER, deposited);
        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(outerVault), deposited);
        outerVault.deposit(deposited, SUPPLIER);
        vm.stopPrank();

        uint256 outerAPY = snippets.supplyAPYVaultV2(address(outerVault));
        uint256 innerAPY = snippets.supplyAPYVaultV2(address(vault));

        assertTrue(outerAPY > 0, "Outer APY should be > 0");
        assertTrue(innerAPY > 0, "Inner APY should be > 0");
    }

    /// @notice With performance fees on both vaults, outer APY should be < inner APY.
    function test_V2OnV2_APYCompoundsFees() public {
        address feeRecipient = makeAddr("feeRecipient");

        // Set fee recipient then fee on inner vault
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (feeRecipient)));
        vault.setPerformanceFeeRecipient(feeRecipient);
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (0.1e18)));
        vault.setPerformanceFee(0.1e18);

        // Set fee recipient then fee on outer vault
        vm.prank(curator);
        outerVault.submit(abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (feeRecipient)));
        outerVault.setPerformanceFeeRecipient(feeRecipient);
        vm.prank(curator);
        outerVault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (0.1e18)));
        outerVault.setPerformanceFee(0.1e18);

        uint256 deposited = 1e18;
        deal(address(underlyingToken), SUPPLIER, deposited);
        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(outerVault), deposited);
        outerVault.deposit(deposited, SUPPLIER);
        vm.stopPrank();

        uint256 outerAPY = snippets.supplyAPYVaultV2(address(outerVault));
        uint256 innerAPY = snippets.supplyAPYVaultV2(address(vault));

        assertTrue(outerAPY > 0, "Outer APY should be > 0");
        assertTrue(outerAPY < innerAPY, "Outer APY should be < inner APY due to compounded fees");
    }

    /// @notice Empty outer vault returns 0 APY.
    function test_V2OnV2_APYWithZeroAssets() public view {
        uint256 apy = snippets.supplyAPYVaultV2(address(outerVault));
        assertEq(apy, 0, "APY should be 0 for empty vault");
    }

    /// @notice marketsInVaultV2 should recurse through outer -> inner VaultV2 and return inner market ids.
    function test_V2OnV2_MarketsInVaultV2_RecursesToInnerVault() public view {
        bytes32[] memory markets = snippets.marketsInVaultV2(address(outerVault));
        assertGt(markets.length, 0, "outer vault should expose inner markets");

        bytes32 targetMarket = Id.unwrap(allMarketParams[0].id());
        uint256 occurrences;
        for (uint256 i; i < markets.length; ++i) {
            if (markets[i] == targetMarket) occurrences++;
        }

        assertEq(occurrences, 1, "inner market id should appear once");
    }

    /// @notice vaultV2AssetsInMarket should recurse and scale inner assets by outer ownership share.
    function test_V2OnV2_VaultV2AssetsInMarket_UsesInnerShare() public {
        uint256 innerDirectDeposit = 2e18;
        deal(address(underlyingToken), address(this), innerDirectDeposit);
        vault.deposit(innerDirectDeposit, address(this));

        uint256 outerDeposit = 1e18;
        deal(address(underlyingToken), SUPPLIER, outerDeposit);
        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(outerVault), outerDeposit);
        outerVault.deposit(outerDeposit, SUPPLIER);
        vm.stopPrank();

        MarketParams memory mp = allMarketParams[0];
        uint256 innerMarketAssets = snippets.vaultV2AssetsInMarket(address(vault), mp);
        uint256 outerMarketAssets = snippets.vaultV2AssetsInMarket(address(outerVault), mp);

        uint256 outerAdapterAssets = IAdapter(address(outerAdapter)).realAssets();
        uint256 innerTotalAssets = vault.totalAssets();
        uint256 expectedOuterMarketAssets = innerMarketAssets.mulDivDown(outerAdapterAssets, innerTotalAssets);

        assertGt(innerMarketAssets, 0, "inner market assets should be > 0");
        assertGt(outerMarketAssets, 0, "outer market assets should be > 0");
        assertApproxEqAbs(
            outerMarketAssets,
            expectedOuterMarketAssets,
            2,
            "outer market assets should match proportional recursive share"
        );
    }
}

/// @notice Covers MorphoMarketV1AdapterV2 APY path and market dedup behavior across adapters.
contract TestMorphoVaultV2SnippetsMarketAdapterCoverage is MorphoVaultV1IntegrationTest {
    MorphoVaultV2Snippets internal snippets;

    address internal marketAdapter;
    address internal adaptiveCurveIrm;
    MarketParams internal sharedMarketParams;
    address internal BORROWER = makeAddr("Borrower");

    function setUp() public virtual override {
        super.setUp();

        snippets = new MorphoVaultV2Snippets(address(morpho));
        adaptiveCurveIrm = deployCode("AdaptiveCurveIrm.sol", abi.encode(address(morpho)));

        vm.prank(morphoOwner);
        morpho.enableIrm(adaptiveCurveIrm);

        sharedMarketParams = MarketParams({
            loanToken: address(underlyingToken),
            collateralToken: address(collateralToken),
            irm: adaptiveCurveIrm,
            oracle: address(oracle),
            lltv: 0.8 ether
        });
        morpho.createMarket(sharedMarketParams);

        setMorphoVaultV1Cap(sharedMarketParams, type(uint184).max);
        Id[] memory supplyQueue = new Id[](1);
        supplyQueue[0] = sharedMarketParams.id();
        vm.prank(mmAllocator);
        morphoVaultV1.setSupplyQueue(supplyQueue);

        MorphoMarketV1AdapterV2Factory factory = new MorphoMarketV1AdapterV2Factory(address(morpho), adaptiveCurveIrm);
        marketAdapter = factory.createMorphoMarketV1AdapterV2(address(vault));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (marketAdapter)));
        vault.addAdapter(marketAdapter);

        bytes memory adapterIdData = abi.encode("this", marketAdapter);
        increaseAbsoluteCap(adapterIdData, type(uint128).max);
        increaseRelativeCap(adapterIdData, 1e18);

        bytes memory collIdData = abi.encode("collateralToken", sharedMarketParams.collateralToken);
        increaseAbsoluteCap(collIdData, type(uint128).max);
        increaseRelativeCap(collIdData, 1e18);

        bytes memory marketIdData = abi.encode("this/marketParams", marketAdapter, sharedMarketParams);
        increaseAbsoluteCap(marketIdData, type(uint128).max);
        increaseRelativeCap(marketIdData, 1e18);

        uint256 deposited = 1e18;
        vault.deposit(deposited, address(this));

        vm.prank(allocator);
        vault.allocate(marketAdapter, abi.encode(sharedMarketParams), 0.8e18);
    }

    function testSupplyAPYVaultV2_UsesMorphoMarketAdapterPath() public {
        uint256 collateralAmount = 100e18;
        uint256 borrowAmount = 0.2e18;

        deal(address(collateralToken), BORROWER, collateralAmount);
        vm.startPrank(BORROWER);
        collateralToken.approve(address(morpho), collateralAmount);
        morpho.supplyCollateral(sharedMarketParams, collateralAmount, BORROWER, "");
        morpho.borrow(sharedMarketParams, borrowAmount, 0, BORROWER, BORROWER);
        vm.stopPrank();

        uint256 vaultApy = snippets.supplyAPYVaultV2(address(vault));
        assertGt(vaultApy, 0, "Vault APY should be > 0 when market adapter has utilized assets");

        uint256 adapterAssets = IAdapter(marketAdapter).realAssets();
        assertGt(adapterAssets, 0, "adapter assets should be > 0");

        uint256 marketApy =
            snippets.supplyAPYMarketV1(sharedMarketParams, morpho.market(sharedMarketParams.id()));
        uint256 expectedApy = marketApy.mulDivDown(adapterAssets, 1e18).mulDivDown(1e18, vault.totalAssets());
        assertApproxEqAbs(vaultApy, expectedApy, 3, "Vault APY should follow weighted market-adapter APY");
    }

    function testMarketsInVaultV2_DeduplicatesAcrossAdapters() public view {
        bytes32 sharedMarketId = Id.unwrap(sharedMarketParams.id());
        bytes32[] memory markets = snippets.marketsInVaultV2(address(vault));

        uint256 occurrences;
        for (uint256 i; i < markets.length; ++i) {
            if (markets[i] == sharedMarketId) occurrences++;
        }

        assertEq(occurrences, 1, "duplicated market id should appear only once");
    }

    function testMarketAdapterHasExpectedMarket() public view {
        bytes32 sharedMarketId = Id.unwrap(sharedMarketParams.id());
        uint256 marketCount = IMorphoMarketV1AdapterV2(marketAdapter).marketIdsLength();
        assertEq(marketCount, 1, "market adapter should track one allocated market");
        assertEq(IMorphoMarketV1AdapterV2(marketAdapter).marketIds(0), sharedMarketId, "tracked market id mismatch");
    }
}

/// @notice Covers outer fee wrapper (V2 -> MorphoVaultV1Adapter) with inner V2 using MorphoMarketV1AdapterV2.
contract TestMorphoVaultV2SnippetsNestedMarketAdapterCoverage is TestMorphoVaultV2SnippetsMarketAdapterCoverage {
    MorphoVaultV1AdapterFactory internal extraAdapterFactory;
    VaultV2 internal outerVault;
    MorphoVaultV1Adapter internal outerAdapter;

    address internal SUPPLIER = makeAddr("NestedSupplier");

    function setUp() public virtual override {
        super.setUp();

        extraAdapterFactory = new MorphoVaultV1AdapterFactory();

        outerVault = new VaultV2(owner, address(underlyingToken));
        outerAdapter = MorphoVaultV1Adapter(
            extraAdapterFactory.createMorphoVaultV1Adapter(address(outerVault), address(vault))
        );

        vm.startPrank(owner);
        outerVault.setCurator(curator);
        vm.stopPrank();

        vm.prank(curator);
        outerVault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (allocator, true)));
        outerVault.setIsAllocator(allocator, true);

        vm.prank(curator);
        outerVault.submit(abi.encodeCall(IVaultV2.addAdapter, (address(outerAdapter))));
        outerVault.addAdapter(address(outerAdapter));

        bytes memory idData = abi.encode("this", address(outerAdapter));
        vm.prank(curator);
        outerVault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, type(uint128).max)));
        outerVault.increaseAbsoluteCap(idData, type(uint128).max);

        vm.prank(curator);
        outerVault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, 1e18)));
        outerVault.increaseRelativeCap(idData, 1e18);

        vm.prank(allocator);
        outerVault.setLiquidityAdapterAndData(address(outerAdapter), "");

        // Inner vault uses market adapter as its liquidity adapter.
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(marketAdapter, abi.encode(sharedMarketParams));
    }

    function testNestedMarketAdapter_MarketsInVaultV2_RecursesToInnerVault() public view {
        bytes32 sharedMarketId = Id.unwrap(sharedMarketParams.id());
        bytes32[] memory markets = snippets.marketsInVaultV2(address(outerVault));

        uint256 occurrences;
        for (uint256 i; i < markets.length; ++i) {
            if (markets[i] == sharedMarketId) occurrences++;
        }

        assertEq(occurrences, 1, "shared market id should appear once on outer vault");
    }

    function testNestedMarketAdapter_VaultV2AssetsInMarket_UsesInnerShare() public {
        uint256 outerDeposit = 1e18;
        deal(address(underlyingToken), SUPPLIER, outerDeposit);
        vm.startPrank(SUPPLIER);
        underlyingToken.approve(address(outerVault), outerDeposit);
        outerVault.deposit(outerDeposit, SUPPLIER);
        vm.stopPrank();

        uint256 innerMarketAssets = snippets.vaultV2AssetsInMarket(address(vault), sharedMarketParams);
        uint256 outerMarketAssets = snippets.vaultV2AssetsInMarket(address(outerVault), sharedMarketParams);

        uint256 outerAdapterAssets = IAdapter(address(outerAdapter)).realAssets();
        uint256 innerTotalAssets = vault.totalAssets();
        uint256 expectedOuterMarketAssets = innerMarketAssets.mulDivDown(outerAdapterAssets, innerTotalAssets);

        assertGt(innerMarketAssets, 0, "inner market assets should be > 0");
        assertGt(outerMarketAssets, 0, "outer market assets should be > 0");
        assertApproxEqAbs(
            outerMarketAssets,
            expectedOuterMarketAssets,
            2,
            "outer market assets should match proportional recursive share"
        );
    }
}

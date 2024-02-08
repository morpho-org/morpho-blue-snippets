// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {MetaMorphoSnippets} from "../../src/metamorpho/MetaMorphoSnippets.sol";
import "../../lib/metamorpho/test/forge/helpers/IntegrationTest.sol";
import {IIrm} from "../../lib/metamorpho/lib/morpho-blue/src/interfaces/IIrm.sol";
import {IOracle} from "../../lib/metamorpho/lib/morpho-blue/src/interfaces/IOracle.sol";
import {SafeCast} from "../../lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

contract TestMetaMorphoSnippets is IntegrationTest {
    using MorphoBalancesLib for IMorpho;
    using MorphoLib for IMorpho;
    using MathLib for uint256;
    using Math for uint256;
    using MarketParamsLib for MarketParams;

    uint256 internal constant MAX_FEE = 0.25e18;
    MetaMorphoSnippets internal snippets;

    function setUp() public virtual override {
        super.setUp();

        snippets = new MetaMorphoSnippets(address(morpho));

        _setCap(allMarkets[0], CAP);
        _setCap(allMarkets[1], CAP);

        _sortSupplyQueueIdleLast();

        vm.startPrank(SUPPLIER);
        ERC20(vault.asset()).approve(address(snippets), type(uint256).max);
        vault.approve(address(snippets), type(uint256).max);
        vm.stopPrank();
    }

    function testTotalDepositVault(uint256 firstDeposit, uint256 secondDeposit) public {
        firstDeposit = bound(firstDeposit, MIN_TEST_ASSETS, MAX_TEST_ASSETS / 2);
        secondDeposit = bound(secondDeposit, MIN_TEST_ASSETS, MAX_TEST_ASSETS / 2);

        loanToken.setBalance(SUPPLIER, firstDeposit);

        vm.prank(SUPPLIER);
        vault.deposit(firstDeposit, ONBEHALF);

        assertEq(snippets.totalDepositVault(address(vault)), firstDeposit, "lastTotalAssets");

        loanToken.setBalance(SUPPLIER, secondDeposit);
        vm.prank(SUPPLIER);
        vault.deposit(secondDeposit, ONBEHALF);

        assertEq(snippets.totalDepositVault(address(vault)), firstDeposit + secondDeposit, "lastTotalAssets2");
    }

    function testVaultAssetsInMarket(uint256 assets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(assets, ONBEHALF);

        assertGt(shares, 0, "shares");
        assertEq(vault.balanceOf(ONBEHALF), shares, "balanceOf(ONBEHALF)");
        assertEq(morpho.expectedSupplyAssets(allMarkets[0], address(vault)), assets, "expectedSupplyAssets(vault)");
        assertEq(snippets.vaultAssetsInMarket(address(vault), allMarkets[0]), assets, "expectedSupplyAssets(vault)");
    }

    function testTotalSharesUserVault(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);
        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(deposited, ONBEHALF);

        assertEq(vault.balanceOf(ONBEHALF), shares, "balanceOf(ONBEHALF)");
        assertEq(snippets.totalSharesUserVault(address(vault), ONBEHALF), shares, "UserShares");
    }

    function testSupplyQueueVault() public {
        _setCaps();
        Id[] memory supplyQueue = new Id[](2);
        supplyQueue[0] = allMarkets[1].id();
        supplyQueue[1] = allMarkets[2].id();

        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(supplyQueue);

        assertEq(Id.unwrap(vault.supplyQueue(0)), Id.unwrap(allMarkets[1].id()));
        assertEq(Id.unwrap(vault.supplyQueue(1)), Id.unwrap(allMarkets[2].id()));

        Id[] memory supplyQueueList = snippets.supplyQueueVault(address(vault));
        assertEq(Id.unwrap(supplyQueueList[0]), Id.unwrap(allMarkets[1].id()));
        assertEq(Id.unwrap(supplyQueueList[1]), Id.unwrap(allMarkets[2].id()));
    }

    function testWithdrawQueueVault() public {
        _setCaps();

        uint256[] memory indexes = new uint256[](4);
        indexes[0] = 1;
        indexes[1] = 2;
        indexes[2] = 3;
        indexes[3] = 0;

        Id[] memory expectedWithdrawQueue = new Id[](4);
        expectedWithdrawQueue[0] = allMarkets[0].id();
        expectedWithdrawQueue[1] = allMarkets[1].id();
        expectedWithdrawQueue[2] = allMarkets[2].id();
        expectedWithdrawQueue[3] = idleParams.id();

        vm.expectEmit(address(vault));
        emit EventsLib.SetWithdrawQueue(ALLOCATOR, expectedWithdrawQueue);
        vm.prank(ALLOCATOR);
        vault.updateWithdrawQueue(indexes);

        assertEq(Id.unwrap(vault.withdrawQueue(0)), Id.unwrap(expectedWithdrawQueue[0]));
        assertEq(Id.unwrap(vault.withdrawQueue(1)), Id.unwrap(expectedWithdrawQueue[1]));
        assertEq(Id.unwrap(vault.withdrawQueue(2)), Id.unwrap(expectedWithdrawQueue[2]));
        assertEq(Id.unwrap(vault.withdrawQueue(3)), Id.unwrap(expectedWithdrawQueue[3]));

        Id[] memory withdrawQueueList = snippets.withdrawQueueVault(address(vault));

        assertEq(Id.unwrap(withdrawQueueList[0]), Id.unwrap(expectedWithdrawQueue[0]));
        assertEq(Id.unwrap(withdrawQueueList[1]), Id.unwrap(expectedWithdrawQueue[1]));
    }

    function testTotalCapAsset(uint256 capMarket1, uint256 capMarket2, uint256 capMarket3) public {
        capMarket1 = bound(capMarket1, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        capMarket2 = bound(capMarket2, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        capMarket3 = bound(capMarket3, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        _setCap(allMarkets[0], capMarket1);
        _setCap(allMarkets[1], capMarket2);
        _setCap(allMarkets[2], capMarket3);

        assertEq(
            capMarket1 + capMarket2 + capMarket3,
            snippets.totalCapCollateral(address(vault), address(collateralToken)),
            "total collateral cap"
        );
        assertEq(0, snippets.totalCapCollateral(address(vault), address(loanToken)), "the total loan cap should be 0");
    }

    function testSupplyAPY0(uint256 firstDeposit, uint256 secondDeposit) public {
        firstDeposit = bound(firstDeposit, MIN_TEST_ASSETS, MAX_TEST_ASSETS / 2);
        secondDeposit = bound(secondDeposit, MIN_TEST_ASSETS, MAX_TEST_ASSETS / 2);

        _setCap(allMarkets[0], firstDeposit);
        _setCap(allMarkets[1], secondDeposit);

        Id[] memory supplyQueue = new Id[](2);
        supplyQueue[0] = allMarkets[0].id();
        supplyQueue[1] = allMarkets[1].id();

        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(supplyQueue);

        loanToken.setBalance(SUPPLIER, firstDeposit + secondDeposit);
        vm.startPrank(SUPPLIER);
        vault.deposit(firstDeposit, ONBEHALF);
        vault.deposit(secondDeposit, ONBEHALF);
        vm.stopPrank();

        Id id0 = Id(allMarkets[0].id());
        Id id1 = Id(allMarkets[1].id());

        Market memory market0 = morpho.market(id0);
        Market memory market1 = morpho.market(id1);

        uint256 rateMarket0 = snippets.supplyAPYMarket(allMarkets[0], market0);
        uint256 rateMarket1 = snippets.supplyAPYMarket(allMarkets[1], market1);

        assertEq(rateMarket0, 0, "rate market 0 not eq to 0 while there is no borrow");
        assertEq(rateMarket1, 0, "rate market 1 not eq to 0 while there is no borrow");
    }

    function testSupplyAPYIdleMarket(uint256 deposit) public {
        deposit = bound(deposit, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        Id idleId = idleParams.id();
        Market memory idleMarket = morpho.market(idleId);
        Id[] memory supplyQueue = new Id[](1);

        supplyQueue[0] = idleId;
        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(supplyQueue);

        loanToken.setBalance(SUPPLIER, deposit);
        vm.prank(SUPPLIER);
        vault.deposit(deposit, ONBEHALF);

        uint256 supplyAPY = snippets.supplyAPYMarket(idleParams, idleMarket);

        assertEq(supplyAPY, 0, "the supply APY in idle market should be zero");
    }

    function testSupplyAPYMarket(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        public
    {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);
        MarketParams memory marketParams = allMarkets[0];
        Id id = Id(marketParams.id());
        Market memory market = morpho.market(id);

        morpho.accrueInterest(marketParams);

        uint256 actualSupplyApy = snippets.supplyAPYMarket(marketParams, market);

        (uint256 totalSupplyAssets,, uint256 totalBorrowAssets,) = morpho.expectedMarketBalances(marketParams);

        uint256 borrowApy = IIrm(marketParams.irm).borrowRateView(marketParams, market).wTaylorCompounded(365 days);

        uint256 utilization = totalBorrowAssets == 0 ? 0 : totalBorrowAssets.wDivUp(totalSupplyAssets);
        uint256 expectedSupplyApy = borrowApy.wMulDown(1 ether - market.fee).wMulDown(utilization);

        if (utilization == 0 || marketParams.irm == address(0)) {
            assertEq(actualSupplyApy, 0, "the actualSupplyApy should be 0");
        } else {
            assertGt(actualSupplyApy, 0, "the actualSupplyApy should not be 0");
            assertGt(expectedSupplyApy, 0, "the expectedSupplyApy should not be 0");
            assertEq(actualSupplyApy, expectedSupplyApy, "Diff in snippets vs integration supplyAPY test");
        }
    }

    function testSupplyAPYVault(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 timeElapsed,
        uint256 fee,
        uint256 firstDeposit,
        uint256 secondDeposit
    ) public {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);
        firstDeposit = bound(firstDeposit, 1e10, MAX_TEST_ASSETS / 2);
        secondDeposit = bound(secondDeposit, 1e10, MAX_TEST_ASSETS / 2);

        _setCap(allMarkets[0], firstDeposit);
        _setCap(allMarkets[1], secondDeposit);

        MarketParams memory marketParams0 = allMarkets[0];
        MarketParams memory marketParams1 = allMarkets[1];

        Id id0 = Id(marketParams0.id());
        Id id1 = Id(marketParams1.id());

        Market memory market0 = morpho.market(id0);
        Market memory market1 = morpho.market(id1);

        morpho.accrueInterest(marketParams0);
        morpho.accrueInterest(marketParams1);

        Id[] memory supplyQueue = new Id[](2);
        supplyQueue[0] = allMarkets[0].id();
        supplyQueue[1] = allMarkets[1].id();

        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(supplyQueue);

        loanToken.setBalance(SUPPLIER, firstDeposit + secondDeposit);
        vm.startPrank(SUPPLIER);
        vault.deposit(firstDeposit, ONBEHALF);
        vault.deposit(secondDeposit, ONBEHALF);
        vm.stopPrank();

        uint256 rateMarket0 = snippets.supplyAPYMarket(marketParams0, market0);
        uint256 rateMarket1 = snippets.supplyAPYMarket(marketParams1, market1);
        uint256 avgApyNum = rateMarket0.wMulDown(firstDeposit) + rateMarket1.wMulDown(secondDeposit);

        uint256 expectedAvgApy = avgApyNum.mulDivDown(WAD - vault.fee(), firstDeposit + secondDeposit);

        uint256 avgSupplyApySnippets = snippets.supplyAPYVault(address(vault));

        assertGt(rateMarket0, 0, "avgSupplyApySnippets == 0");
        assertGt(rateMarket1, 0, "avgSupplyApySnippets == 0");
        assertApproxEqAbs(avgSupplyApySnippets, expectedAvgApy, MIN_TEST_ASSETS);
    }

    // MANAGING FUNCTION

    function testDepositInVault(uint256 assets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);
        vm.prank(SUPPLIER);
        uint256 shares = snippets.depositInVault(address(vault), assets, SUPPLIER);

        assertGt(shares, 0, "shares");
        assertEq(vault.balanceOf(SUPPLIER), shares, "balanceOf(SUPPLIER)");
    }

    function testDepositInVaultWithoutPreviousApproval(uint256 assets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(address(snippets));
        loanToken.approve(address(vault), 0);

        vm.prank(SUPPLIER);
        uint256 shares = snippets.depositInVault(address(vault), assets, SUPPLIER);

        assertGt(shares, 0, "shares");
        assertEq(vault.balanceOf(SUPPLIER), shares, "balanceOf(SUPPLIER)");
    }

    function testWithdrawFromVaultAmount(uint256 deposited, uint256 withdrawn) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        withdrawn = bound(withdrawn, MIN_TEST_ASSETS, deposited);

        loanToken.setBalance(SUPPLIER, deposited);
        vm.startPrank(SUPPLIER);
        uint256 shares = vault.deposit(deposited, SUPPLIER);
        uint256 redeemed = snippets.withdrawFromVaultAmount(address(vault), withdrawn, SUPPLIER);
        vm.stopPrank();

        assertEq(vault.balanceOf(SUPPLIER), shares - redeemed, "balanceOf(SUPPLIER)");
    }

    function testRedeemAllFromVault(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);
        vm.startPrank(SUPPLIER);
        uint256 minted = vault.deposit(deposited, SUPPLIER);

        assertEq(vault.maxRedeem(SUPPLIER), minted, "maxRedeem(SUPPLIER)");

        uint256 redeemed = snippets.redeemAllFromVault(address(vault), SUPPLIER);
        vm.stopPrank();

        assertEq(redeemed, deposited, "assets");
        assertEq(vault.balanceOf(SUPPLIER), 0, "balanceOf(SUPPLIER)");
        assertEq(loanToken.balanceOf(SUPPLIER), deposited, "loanToken.balanceOf(SUPPLIER)");
        assertEq(morpho.expectedSupplyAssets(allMarkets[0], address(vault)), 0, "expectedSupplyAssets(vault)");
    }

    function testReallocateAvailableLiquidityIdle() public {
        _setCap(allMarkets[0], 1 ether);
        _setCap(allMarkets[1], 1 ether);
        _setCap(allMarkets[2], 1 ether);
        _setCap(idleParams, type(uint128).max);

        vm.prank(OWNER);
        vault.setIsAllocator(address(snippets), true);

        loanToken.setBalance(SUPPLIER, 4 ether);

        vm.prank(SUPPLIER);
        vault.deposit(4 ether, ONBEHALF);

        collateralToken.setBalance(BORROWER, 1 ether);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(allMarkets[0], 1 ether, BORROWER, hex"");
        morpho.borrow(allMarkets[0], 0.75 ether, 0, BORROWER, BORROWER);
        vm.stopPrank();

        MarketParams[] memory srcMarketParams = new MarketParams[](3);
        srcMarketParams[0] = allMarkets[0];
        srcMarketParams[1] = allMarkets[1];
        srcMarketParams[2] = allMarkets[2];

        snippets.reallocateAvailableLiquidity(address(vault), srcMarketParams, idleParams);

        assertEq(morpho.supplyShares(allMarkets[0].id(), address(vault)), 0.75e24, "supplyShares(0)");
        assertEq(morpho.supplyShares(allMarkets[1].id(), address(vault)), 0, "supplyShares(1)");
        assertEq(morpho.supplyShares(allMarkets[2].id(), address(vault)), 0, "supplyShares(2)");
        assertEq(morpho.supplyShares(idleParams.id(), address(vault)), 3.25e24, "supplyShares(idle)");
    }

    function _setCaps() internal {
        _setCap(allMarkets[0], CAP);
        _setCap(allMarkets[1], CAP);
        _setCap(allMarkets[2], CAP);
    }

    function _generatePendingInterest(uint256 amountSupplied, uint256 amountBorrowed, uint256 blocks, uint256 fee)
        internal
    {
        amountSupplied = bound(amountSupplied, 1e12, MAX_TEST_ASSETS);
        amountBorrowed = bound(amountBorrowed, amountSupplied / 2, amountSupplied);
        blocks = _boundBlocks(blocks);
        fee = bound(fee, 0, MAX_FEE);

        for (uint256 i = 0; i < 2; i++) {
            MarketParams memory marketParams = allMarkets[i];
            Id idMarket = Id(marketParams.id());
            vm.startPrank(MORPHO_OWNER);
            if (fee != morpho.fee(idMarket)) {
                morpho.setFee(marketParams, fee);
            }
            vm.stopPrank();

            loanToken.setBalance(SUPPLIER, amountSupplied);
            vm.prank(SUPPLIER);
            morpho.supply(marketParams, amountSupplied, 0, SUPPLIER, hex"");

            uint256 collateralPrice = IOracle(marketParams.oracle).price();
            uint256 amountCollateral =
                amountBorrowed.wDivUp(marketParams.lltv).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice);
            collateralToken.setBalance(BORROWER, amountCollateral);

            vm.startPrank(BORROWER);
            morpho.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");
            morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
            vm.stopPrank();
        }
        vm.stopPrank();

        _forward(blocks);
    }
}

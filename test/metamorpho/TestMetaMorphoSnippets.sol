// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {MetaMorphoSnippets} from "../../src/metamorpho/MetaMorphoSnippets.sol";
import "../../lib/metamorpho/test/forge/helpers/IntegrationTest.sol";

import {SafeCast} from "../../lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

contract TestMetaMorphoSnippets is IntegrationTest {
    using MorphoBalancesLib for IMorpho;
    using MorphoLib for IMorpho;
    using MathLib for uint256;
    using Math for uint256;
    using MarketParamsLib for MarketParams;

    MetaMorphoSnippets internal snippets;

    function setUp() public virtual override {
        super.setUp();

        snippets = new MetaMorphoSnippets(address(morpho));

        _setCap(allMarkets[0], CAP);
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
        // Second assert is handling the if statement
        assertEq(0, snippets.totalCapCollateral(address(vault), address(loanToken)), "the total loan cap should be 0");
    }

    function testSupplyAPY0(Market memory market) public {
        vm.assume(market.totalBorrowAssets == 0);
        vm.assume(market.lastUpdate > 0);
        vm.assume(market.fee < 1 ether);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

        MarketParams memory marketParams = allMarkets[0];
        (uint256 totalSupplyAssets,, uint256 totalBorrowAssets,) = morpho.expectedMarketBalances(marketParams);

        uint256 borrowTrue = irm.borrowRateView(marketParams, market);
        uint256 utilization = totalBorrowAssets == 0 ? 0 : totalBorrowAssets.wDivUp(totalSupplyAssets);

        assertEq(utilization, 0, "Diff in snippets vs integration supplyAPY test");
        assertEq(
            borrowTrue.wMulDown(1 ether - market.fee).wMulDown(utilization),
            0,
            "Diff in snippets vs integration supplyAPY test"
        );
        assertEq(snippets.supplyAPYMarket(marketParams, market), 0, "Diff in snippets vs integration supplyAPY test");
    }

    function testSupplyAPYIdleMarket() public {
        Market memory market;
        MarketParams memory idleMarket;
        idleMarket.loanToken = address(loanToken);

        vm.prank(MORPHO_OWNER);
        morpho.enableIrm(address(0));

        morpho.createMarket(idleMarket);

        uint256 supplyAPY = snippets.supplyAPYMarket(idleMarket, market);

        assertEq(supplyAPY, 0, "supply APY");
    }

    function testSupplyAPYMarket(Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalBorrowShares > 0);
        vm.assume(market.totalSupplyAssets > 0);
        vm.assume(market.totalSupplyShares > 0);
        vm.assume(market.fee < 1 ether);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

        MarketParams memory marketParams = allMarkets[0];
        (uint256 totalSupplyAssets,, uint256 totalBorrowAssets,) = morpho.expectedMarketBalances(marketParams);

        uint256 borrowTrue = irm.borrowRateView(marketParams, market);
        uint256 utilization = totalBorrowAssets == 0 ? 0 : totalBorrowAssets.wDivUp(totalSupplyAssets);
        uint256 supplyTrue = borrowTrue.wTaylorCompounded(1).wMulDown(1 ether - market.fee).wMulDown(utilization);

        uint256 supplyToTest = snippets.supplyAPYMarket(marketParams, market);

        // handling in if-else the situation where utilization = 0 otherwise too many rejects
        if (utilization == 0) {
            assertEq(supplyTrue, 0, "supply rate == 0");
            assertEq(supplyTrue, supplyToTest, "Diff in snippets vs integration supplyAPY test");
        } else {
            assertGt(supplyTrue, 0, "supply rate == 0");
            assertEq(supplyTrue, supplyToTest, "Diff in snippets vs integration supplyAPY test");
        }
    }

    function testSupplyAPYVault(uint256 firstDeposit, uint256 secondDeposit, uint256 firstBorrow, uint256 secondBorrow)
        public
    {
        firstDeposit = bound(firstDeposit, MIN_TEST_ASSETS, MAX_TEST_ASSETS / 2);
        secondDeposit = bound(secondDeposit, MIN_TEST_ASSETS, MAX_TEST_ASSETS / 2);
        firstBorrow = bound(firstBorrow, MIN_TEST_ASSETS, firstDeposit);
        secondBorrow = bound(secondBorrow, MIN_TEST_ASSETS, secondDeposit);

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

        collateralToken.setBalance(BORROWER, 2 * MAX_TEST_ASSETS);
        vm.startPrank(BORROWER);
        morpho.supplyCollateral(allMarkets[0], MAX_TEST_ASSETS, BORROWER, hex"");
        morpho.borrow(allMarkets[0], firstBorrow, 0, BORROWER, BORROWER);

        morpho.supplyCollateral(allMarkets[1], MAX_TEST_ASSETS, BORROWER, hex"");
        morpho.borrow(allMarkets[1], secondBorrow / 4, 0, BORROWER, BORROWER);
        vm.stopPrank();

        Id id0 = Id(allMarkets[0].id());
        Id id1 = Id(allMarkets[1].id());

        Market memory market0 = morpho.market(id0);
        Market memory market1 = morpho.market(id1);

        uint256 rateMarket0 = snippets.supplyAPYMarket(allMarkets[0], market0);
        uint256 rateMarket1 = snippets.supplyAPYMarket(allMarkets[1], market1);
        uint256 avgRateNum = rateMarket0.wMulDown(firstDeposit) + rateMarket1.wMulDown(secondDeposit);

        uint256 expectedAvgRate = avgRateNum.wDivUp(firstDeposit + secondDeposit);

        uint256 avgSupplyRateSnippets = snippets.supplyAPYVault(address(vault));

        assertEq(avgSupplyRateSnippets, expectedAvgRate, "avgSupplyRateSnippets == 0");
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

    // It covers the branch of _approveMaxVault
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
        withdrawn = bound(withdrawn, 0, deposited);

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
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {MetamorphoSnippets} from "@snippets/metamorpho/MetamorphoSnippets.sol";
import "@metamorpho-test/helpers/IntegrationTest.sol";
import "@morpho-blue/libraries/SharesMathLib.sol";
import {MorphoBalancesLib} from "@morpho-blue/libraries/periphery/MorphoBalancesLib.sol";
import {SafeCast} from "@openzeppelin/utils/math/SafeCast.sol";

contract TestIntegrationSnippets is IntegrationTest {
    MetamorphoSnippets internal snippets;

    using MorphoBalancesLib for IMorpho;
    using MorphoLib for IMorpho;
    using MathLib for uint256;
    using Math for uint256;
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;

    function setUp() public virtual override {
        super.setUp();
        snippets = new MetamorphoSnippets(address(vault), address(morpho));
        _setCap(allMarkets[0], CAP);
        _sortSupplyQueueIdleLast();
    }

    function testTotalDepositVault(uint256 deposited) public {
        uint256 firstDeposit = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS / 2);
        uint256 secondDeposit = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS / 2);

        loanToken.setBalance(SUPPLIER, firstDeposit);

        vm.prank(SUPPLIER);
        vault.deposit(firstDeposit, ONBEHALF);

        uint256 snippetTotalAsset = snippets.totalDepositVault();

        assertEq(firstDeposit, snippetTotalAsset, "lastTotalAssets");

        loanToken.setBalance(SUPPLIER, secondDeposit);
        vm.prank(SUPPLIER);
        vault.deposit(secondDeposit, ONBEHALF);

        uint256 snippetTotalAsset2 = snippets.totalDepositVault();

        assertEq(firstDeposit + secondDeposit, snippetTotalAsset2, "lastTotalAssets2");
    }

    function testVaultAssetsInMarket(uint256 assets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(assets, ONBEHALF);

        assertGt(shares, 0, "shares");
        assertEq(vault.balanceOf(ONBEHALF), shares, "balanceOf(ONBEHALF)");
        assertEq(morpho.expectedSupplyAssets(allMarkets[0], address(vault)), assets, "expectedSupplyAssets(vault)");

        uint256 vaultAmount = snippets.vaultAssetsInMarket(allMarkets[0]);
        assertEq(assets, vaultAmount, "expectedSupplyAssets(vault)");
    }

    function testTotalSharesUserVault(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);
        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(deposited, ONBEHALF);

        assertEq(vault.balanceOf(ONBEHALF), shares, "balanceOf(ONBEHALF)");

        uint256 snippetUserShares = snippets.totalSharesUserVault(ONBEHALF);
        assertEq(shares, snippetUserShares, "UserShares");
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

        Id[] memory supplyQueueList = snippets.supplyQueueVault();
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

        Id[] memory withdrawQueueList = snippets.withdrawQueueVault();

        assertEq(Id.unwrap(withdrawQueueList[0]), Id.unwrap(expectedWithdrawQueue[0]));
        assertEq(Id.unwrap(withdrawQueueList[1]), Id.unwrap(expectedWithdrawQueue[1]));
    }

    function testCapMarket(MarketParams memory marketParams) public {
        Id idMarket = marketParams.id();
        uint192 cap = vault.config(idMarket).cap;
        uint192 snippetCap = snippets.capMarket(marketParams);
        assertEq(cap, snippetCap, "cap per market");
    }

    function testSupplyAPR0(Market memory market) public {
        vm.assume(market.totalBorrowAssets == 0);
        vm.assume(market.lastUpdate > 0);
        vm.assume(market.fee < 1 ether);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);
        MarketParams memory marketParams = allMarkets[0];
        (uint256 totalSupplyAssets,, uint256 totalBorrowAssets,) = morpho.expectedMarketBalances(marketParams);
        uint256 borrowTrue = irm.borrowRateView(marketParams, market);
        uint256 utilization = totalBorrowAssets == 0 ? 0 : totalBorrowAssets.wDivUp(totalSupplyAssets);

        uint256 supplyTrue = borrowTrue.wMulDown(1 ether - market.fee).wMulDown(utilization);
        uint256 supplyToTest = snippets.supplyAPRMarket(marketParams, market);
        assertEq(utilization, 0, "Diff in snippets vs integration supplyAPR test");
        assertEq(supplyTrue, 0, "Diff in snippets vs integration supplyAPR test");
        assertEq(supplyToTest, 0, "Diff in snippets vs integration supplyAPR test");
    }

    function testSupplyAPRMarket(Market memory market) public {
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
        uint256 supplyTrue = borrowTrue.wMulDown(1 ether - market.fee).wMulDown(utilization);

        uint256 supplyToTest = snippets.supplyAPRMarket(marketParams, market);
        assertGt(supplyTrue, 0, "supply rate ==0");
        assertEq(supplyTrue, supplyToTest, "Diff in snippets vs integration supplyAPR test");
    }

    // TODO: enhance the test
    function testSupplyAPRVault(uint256 deposited) public {
        // set 2 suppliers and 1 borrower
        uint256 firstDeposit = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS / 2);
        uint256 secondDeposit = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS / 2);
        _setCap(allMarkets[0], firstDeposit);
        _setCap(allMarkets[1], secondDeposit);

        Id[] memory supplyQueue = new Id[](2);
        supplyQueue[0] = allMarkets[0].id();
        supplyQueue[1] = allMarkets[1].id();

        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(supplyQueue);
        loanToken.setBalance(SUPPLIER, firstDeposit);

        vm.prank(SUPPLIER);
        vault.deposit(firstDeposit, ONBEHALF);

        uint256 snippetTotalAsset = snippets.totalDepositVault();

        assertEq(firstDeposit, snippetTotalAsset, "lastTotalAssets");

        loanToken.setBalance(SUPPLIER, secondDeposit);
        vm.prank(SUPPLIER);
        vault.deposit(secondDeposit, ONBEHALF);

        uint256 snippetTotalAsset2 = snippets.totalDepositVault();
        assertEq(firstDeposit + secondDeposit, snippetTotalAsset2, "lastTotalAssets2");

        collateralToken.setBalance(BORROWER, type(uint256).max);
        vm.startPrank(BORROWER);
        morpho.supplyCollateral(allMarkets[0], MAX_TEST_ASSETS, BORROWER, hex"");
        morpho.borrow(allMarkets[0], firstDeposit, 0, BORROWER, BORROWER);
        vm.stopPrank();

        // // in the current state: borrower borrowed some liquidity in market 0

        collateralToken.setBalance(BORROWER, type(uint256).max - MAX_TEST_ASSETS);
        vm.startPrank(BORROWER);
        morpho.supplyCollateral(allMarkets[1], MAX_TEST_ASSETS, BORROWER, hex"");
        morpho.borrow(allMarkets[1], secondDeposit / 4, 0, BORROWER, BORROWER);
        vm.stopPrank();

        // in the current state: borrower borrowed some liquidity in market 1 as well, up to 1/4 of the liquidity

        uint256 avgSupplyRateSnippets = snippets.supplyAPRVault();
        assertGt(avgSupplyRateSnippets, 0, "avgSupplyRateSnippets ==0");

        // market 0: utilization 100% -> firstDeposit*50% + secondDeposit * (50%/4) (only a quarter is borrowed)
        _setFee(0);

        Id id0 = Id(allMarkets[0].id());

        Id id1 = Id(allMarkets[1].id());
        Market memory market0 = morpho.market(id0);
        Market memory market1 = morpho.market(id1);

        uint256 rateMarket0 = snippets.supplyAPRMarket(allMarkets[0], market0);
        uint256 rateMarket1 = snippets.supplyAPRMarket(allMarkets[1], market1);
        assertGt(rateMarket0, 0, "supply rate ==0");
        assertGt(rateMarket1, 0, "supply rate ==0");

        uint256 avgRateNum = rateMarket0.wMulDown(firstDeposit) + rateMarket1.wMulDown(secondDeposit);
        // uint256 totalDeposited =
        // uint256 avgRate = avgRateNum.wDivDown(firstDeposit+secondDeposit)
        uint256 avgRate = (firstDeposit + secondDeposit) == 0 ? 0 : avgRateNum.wDivUp(firstDeposit + secondDeposit);
        assertGt(avgRate, 0, "supply rate ==0");
        assertEq(avgSupplyRateSnippets, avgRate, "avgSupplyRateSnippets ==0");
    }

    // MANAGING FUNCTION

    function testDepositInVault(uint256 assets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(address(snippets), assets);

        vm.startPrank(address(snippets));
        loanToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        loanToken.approve(address(vault), type(uint256).max);
        collateralToken.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        uint256 shares = snippets.depositInVault(assets, address(snippets));

        assertGt(shares, 0, "shares");
        assertEq(vault.balanceOf(address(snippets)), shares, "balanceOf(address(snippets))");
    }

    function testWithdrawFromVaultAmount(uint256 deposited, uint256 withdrawn) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        withdrawn = bound(withdrawn, 0, deposited);

        loanToken.setBalance(address(snippets), deposited);

        vm.startPrank(address(snippets));
        loanToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        loanToken.approve(address(vault), type(uint256).max);
        collateralToken.approve(address(vault), type(uint256).max);

        uint256 shares = vault.deposit(deposited, address(snippets));

        uint256 redeemed = snippets.withdrawFromVault(withdrawn, address(snippets));
        vm.stopPrank();

        assertEq(vault.balanceOf(address(snippets)), shares - redeemed, "balanceOf(address(snippets))");
    }

    function testWithdrawFromVaultAll(uint256 assets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(address(snippets), assets);

        vm.startPrank(address(snippets));
        loanToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        loanToken.approve(address(vault), type(uint256).max);
        collateralToken.approve(address(vault), type(uint256).max);

        uint256 minted = vault.deposit(assets, address(snippets));

        assertEq(vault.maxWithdraw(address(snippets)), assets, "maxWithdraw(ONBEHALF)");

        uint256 redeemed = snippets.withdrawFromVault(assets, address(snippets));
        vm.stopPrank();

        assertEq(redeemed, minted, "shares");
        assertEq(vault.balanceOf(address(snippets)), 0, "balanceOf(address(snippets))");
        assertEq(loanToken.balanceOf(address(snippets)), assets, "loanToken.balanceOf(address(snippets))");
        assertEq(morpho.expectedSupplyAssets(allMarkets[0], address(vault)), 0, "expectedSupplyAssets(vault)");
    }

    function testRedeemAll(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(address(snippets), deposited);
        vm.startPrank(address(snippets));
        loanToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        loanToken.approve(address(vault), type(uint256).max);
        collateralToken.approve(address(vault), type(uint256).max);

        uint256 minted = vault.deposit(deposited, address(snippets));

        assertEq(vault.maxRedeem(address(snippets)), minted, "maxRedeem(ONBEHALF)");

        uint256 redeemed = snippets.redeemAllFromVault(address(snippets));

        vm.stopPrank();
        assertEq(redeemed, deposited, "assets");
        assertEq(vault.balanceOf(address(snippets)), 0, "balanceOf(address(snippets))");
        assertEq(loanToken.balanceOf(address(snippets)), deposited, "loanToken.balanceOf(address(snippets))");
        assertEq(morpho.expectedSupplyAssets(allMarkets[0], address(vault)), 0, "expectedSupplyAssets(vault)");
    }

    function _setCaps() internal {
        _setCap(allMarkets[0], CAP);
        _setCap(allMarkets[1], CAP);
        _setCap(allMarkets[2], CAP);
    }
}

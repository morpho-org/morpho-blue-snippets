// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {MetamorphoSnippets} from "@snippets/metamorpho/MetamorphoSnippets.sol";
import "@metamorpho-test/helpers/IntegrationTest.sol";
import "@morpho-blue/libraries/SharesMathLib.sol";
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

    function testDeposit(uint256 assets) public {
        _setCap(allMarkets[0], CAP);
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.expectEmit();
        emit EventsLib.UpdateLastTotalAssets(vault.totalAssets() + assets);
        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(assets, ONBEHALF);

        assertGt(shares, 0, "shares");
        assertEq(vault.balanceOf(ONBEHALF), shares, "balanceOf(ONBEHALF)");
        assertEq(morpho.expectedSupplyBalance(allMarkets[0], address(vault)), assets, "expectedSupplyBalance(vault)");
    }

    function testVaultAmountInMarket(uint256 assets) public {
        _setCap(allMarkets[0], CAP);
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        uint256 shares = vault.deposit(assets, ONBEHALF);

        assertGt(shares, 0, "shares");
        assertEq(vault.balanceOf(ONBEHALF), shares, "balanceOf(ONBEHALF)");
        assertEq(morpho.expectedSupplyBalance(allMarkets[0], address(vault)), assets, "expectedSupplyBalance(vault)");

        uint256 vaultAmount = snippets.vaultAmountInMarket(allMarkets[0]);
        assertEq(assets, vaultAmount, "expectedSupplyBalance(vault)");
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

        assertEq(Id.unwrap(vault.supplyQueue(0)), Id.unwrap(allMarkets[0].id()));
        assertEq(Id.unwrap(vault.supplyQueue(1)), Id.unwrap(allMarkets[1].id()));
        assertEq(Id.unwrap(vault.supplyQueue(2)), Id.unwrap(allMarkets[2].id()));

        Id[] memory supplyQueue = new Id[](2);
        supplyQueue[0] = allMarkets[1].id();
        supplyQueue[1] = allMarkets[2].id();

        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(supplyQueue);

        Id[] memory supplyQueueList = snippets.supplyQueueVault();
        assertEq(Id.unwrap(vault.supplyQueue(0)), Id.unwrap(allMarkets[1].id()));
        assertEq(Id.unwrap(vault.supplyQueue(1)), Id.unwrap(allMarkets[2].id()));
        assertEq(Id.unwrap(supplyQueueList[0]), Id.unwrap(allMarkets[1].id()));
        assertEq(Id.unwrap(supplyQueueList[1]), Id.unwrap(allMarkets[2].id()));
    }

    function testWithdrawQueueVault() public {
        _setCaps();

        assertEq(Id.unwrap(vault.withdrawQueue(0)), Id.unwrap(allMarkets[0].id()));
        assertEq(Id.unwrap(vault.withdrawQueue(1)), Id.unwrap(allMarkets[1].id()));
        assertEq(Id.unwrap(vault.withdrawQueue(2)), Id.unwrap(allMarkets[2].id()));

        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 1;
        indexes[1] = 2;
        indexes[2] = 0;

        Id[] memory expectedWithdrawQueue = new Id[](3);
        expectedWithdrawQueue[0] = allMarkets[1].id();
        expectedWithdrawQueue[1] = allMarkets[2].id();
        expectedWithdrawQueue[2] = allMarkets[0].id();

        vm.prank(ALLOCATOR);
        vault.sortWithdrawQueue(indexes);

        Id[] memory withdrawQueueList = snippets.withdrawQueueVault();
        assertEq(Id.unwrap(vault.withdrawQueue(0)), Id.unwrap(expectedWithdrawQueue[0]));
        assertEq(Id.unwrap(vault.withdrawQueue(1)), Id.unwrap(expectedWithdrawQueue[1]));
        assertEq(Id.unwrap(vault.withdrawQueue(2)), Id.unwrap(expectedWithdrawQueue[2]));

        assertEq(Id.unwrap(withdrawQueueList[0]), Id.unwrap(expectedWithdrawQueue[0]));
        assertEq(Id.unwrap(withdrawQueueList[1]), Id.unwrap(expectedWithdrawQueue[1]));
    }

    // OK
    function testCapMarket(MarketParams memory marketParams) public {
        Id idMarket = marketParams.id();
        (uint192 cap,) = vault.config(idMarket);
        uint192 snippetCap = snippets.capMarket(marketParams);
        assertEq(cap, snippetCap, "cap per market");
    }

    // OK
    function testSubmitCapOverflow(uint256 seed, uint256 cap) public {
        MarketParams memory marketParams = _randomMarketParams(seed);
        cap = bound(cap, uint256(type(uint192).max) + 1, type(uint256).max);

        vm.prank(CURATOR);
        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, uint8(192), cap));
        vault.submitCap(marketParams, cap);
    }

    // TODO Implement the TEST SUPPLY APR EQUAL 0 Function
    // function testSupplyAPREqual0(MarketParams memory marketParams, Market memory market) public {
    //     vm.assume(market.totalBorrowAssets == 0);
    //     vm.assume(market.totalBorrowShares == 0);
    //     vm.assume(market.totalSupplyAssets > 100000);
    //     vm.assume(market.lastUpdate > 0);
    //     vm.assume(market.fee < 1 ether);
    //     vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

    //     (uint256 totalSupplyAssets,, uint256 totalBorrowAssets,) = morpho.expectedMarketBalances(marketParams);
    //     uint256 borrowTrue = irm.borrowRate(marketParams, market);
    //     uint256 utilization = totalBorrowAssets == 0 ? 0 : totalBorrowAssets.wDivUp(totalSupplyAssets);

    //     uint256 supplyTrue = borrowTrue.wMulDown(1 ether - market.fee).wMulDown(utilization);
    //     uint256 supplyToTest = snippets.supplyAPRMarket(marketParams, market);
    //     assertEq(supplyTrue, 0, "Diff in snippets vs integration supplyAPR test");
    //     assertEq(supplyToTest, 0, "Diff in snippets vs integration supplyAPR test");
    // }

    // TODO  Implement the TEST SUPPLY APR Function
    // function testSupplyAPRMarket(MarketParams memory marketParams, Market memory market) public {
    //     vm.assume(market.totalBorrowAssets > 0);
    //     vm.assume(market.fee < 1 ether);
    //     vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

    //     (uint256 totalSupplyAssets,, uint256 totalBorrowAssets,) = morpho.expectedMarketBalances(marketParams);
    //     uint256 borrowTrue = irm.borrowRate(marketParams, market);
    //     assertGt(borrowTrue, 0, "intermediary test");
    //     uint256 utilization = totalBorrowAssets == 0 ? 0 : totalBorrowAssets.wDivUp(totalSupplyAssets);
    //     assertGt(utilization, 0, "intermediary test");
    //     uint256 supplyTrue = borrowTrue.wMulDown(1 ether - market.fee).wMulDown(utilization);
    //     // assertGt(supplyTrue, 0, "intermediary test");
    //     // uint256 supplyToTest = snippets.supplyAPRMarket(marketParams, market);

    //     // assertEq(supplyTrue, supplyToTest, "Diff in snippets vs integration supplyAPR test");
    // }

    // TODO  Implement the TEST SUPPLY APR Vault Function

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
        assertEq(morpho.expectedSupplyBalance(allMarkets[0], address(vault)), 0, "expectedSupplyBalance(vault)");
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
        assertEq(morpho.expectedSupplyBalance(allMarkets[0], address(vault)), 0, "expectedSupplyBalance(vault)");
    }

    function _setCaps() internal {
        _setCap(allMarkets[0], CAP);
        _setCap(allMarkets[1], CAP);
        _setCap(allMarkets[2], CAP);
    }
}

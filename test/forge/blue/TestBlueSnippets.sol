// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Id, IMorpho, MarketParams, Market} from "@morpho-blue/interfaces/IMorpho.sol";
import {BlueSnippets} from "@snippets/blue/BlueSnippets.sol";
import {MorphoBalancesLib} from "@morpho-blue/libraries/periphery/MorphoBalancesLib.sol";
import {MarketParamsLib} from "@morpho-blue/libraries/MarketParamsLib.sol";
import {MorphoLib} from "@morpho-blue/libraries/periphery/MorphoLib.sol";
import {MathLib} from "@morpho-blue/libraries/MathLib.sol";
import {SharesMathLib} from "@morpho-blue/libraries/SharesMathLib.sol";

// we need to import everything in there
import "@morpho-blue-test/BaseTest.sol";

contract TestIntegrationSnippets is BaseTest {
    using MathLib for uint256;
    using MathLib for uint128;
    using MathLib for IMorpho;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;
    // using TestMarketLib for TestMarket;

    uint256 testNumber;

    BlueSnippets internal snippets;

    function setUp() public virtual override {
        super.setUp();
        snippets = new BlueSnippets(address(morpho));
        testNumber = 42;

        vm.startPrank(SUPPLIER);
        loanToken.approve(address(snippets), type(uint256).max);
        collateralToken.approve(address(snippets), type(uint256).max);
        morpho.setAuthorization(address(snippets), true);
        vm.stopPrank();

        vm.startPrank(BORROWER);
        loanToken.approve(address(snippets), type(uint256).max);
        collateralToken.approve(address(snippets), type(uint256).max);
        morpho.setAuthorization(address(snippets), true);
        vm.stopPrank();
    }

    function testSupplyAssetUser(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        public
    {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);

        uint256 expectedSupplyAssets = snippets.supplyAssetsUser(marketParams, SUPPLIER);

        morpho.accrueInterest(marketParams);

        uint256 actualSupplyAssets =
            morpho.supplyShares(id, SUPPLIER).toAssetsDown(morpho.totalSupplyAssets(id), morpho.totalSupplyShares(id));

        assertEq(expectedSupplyAssets, actualSupplyAssets);
    }

    function testBorrowAssetUser(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        public
    {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);

        uint256 expectedBorrowAssets = snippets.borrowAssetsUser(marketParams, SUPPLIER);

        morpho.accrueInterest(marketParams);

        uint256 actualBorrowAssets =
            morpho.borrowShares(id, SUPPLIER).toAssetsUp(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));

        assertEq(expectedBorrowAssets, actualBorrowAssets);
    }

    function testCollateralAssetUser(uint256 amountSupplied, uint256 amountBorrowed, uint256 timestamp, uint256 fee)
        public
    {
        amountSupplied = bound(amountSupplied, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, MIN_TEST_AMOUNT, amountSupplied);
        timestamp = bound(timestamp, block.timestamp, type(uint32).max);
        fee = bound(fee, 0, MAX_FEE);

        _testMorphoLibCommon(amountSupplied, amountBorrowed, timestamp, fee);

        uint256 expectedCollateral = snippets.collateralAssetsUser(id, BORROWER);
        assertEq(morpho.collateral(id, BORROWER), expectedCollateral);
    }

    function testMarketTotalSupply(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        public
    {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);

        uint256 expectedTotalSupply = snippets.marketTotalSupply(marketParams);

        morpho.accrueInterest(marketParams);

        assertEq(expectedTotalSupply, morpho.totalSupplyAssets(id));
    }

    function testMarketTotalBorrow(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        public
    {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);

        uint256 expectedTotalBorrow = snippets.marketTotalBorrow(marketParams);

        morpho.accrueInterest(marketParams);

        assertEq(expectedTotalBorrow, morpho.totalBorrowAssets(id));
    }

    function testBorrowAPY(Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

        uint256 borrowTrue = irm.borrowRate(marketParams, market).wTaylorCompounded(1);
        uint256 borrowToTest = snippets.borrowAPY(marketParams, market);

        assertEq(borrowTrue, borrowToTest, "Diff in snippets vs integration borrowAPY test");
    }

    function testSupplyAPYEqual0(Market memory market) public {
        vm.assume(market.totalBorrowAssets == 0);
        vm.assume(market.totalSupplyAssets > 100000);
        vm.assume(market.lastUpdate > 0);
        vm.assume(market.fee < 1 ether);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

        (uint256 totalSupplyAssets,, uint256 totalBorrowAssets,) = morpho.expectedMarketBalances(marketParams);
        uint256 borrowTrue = irm.borrowRate(marketParams, market).wTaylorCompounded(1);
        uint256 utilization = totalBorrowAssets == 0 ? 0 : totalBorrowAssets.wDivUp(totalSupplyAssets);

        uint256 supplyTrue = borrowTrue.wMulDown(1 ether - market.fee).wMulDown(utilization);
        uint256 supplyToTest = snippets.supplyAPY(marketParams, market);
        assertEq(supplyTrue, 0, "Diff in snippets vs integration supplyAPY test");
        assertEq(supplyToTest, 0, "Diff in snippets vs integration supplyAPY test");
    }

    function testSupplyAPY(Market memory market) public {
        vm.assume(market.totalBorrowAssets > 0);
        vm.assume(market.fee < 1 ether);
        vm.assume(market.totalSupplyAssets >= market.totalBorrowAssets);

        (uint256 totalSupplyAssets,, uint256 totalBorrowAssets,) = morpho.expectedMarketBalances(marketParams);
        uint256 borrowTrue = irm.borrowRateView(marketParams, market);
        uint256 utilization = totalBorrowAssets == 0 ? 0 : totalBorrowAssets.wDivUp(totalSupplyAssets);

        uint256 supplyTrue = borrowTrue.wMulDown(1 ether - market.fee).wMulDown(utilization);
        uint256 supplyToTest = snippets.supplyAPY(marketParams, market);

        assertEq(supplyTrue, supplyToTest, "Diff in snippets vs integration supplyAPY test");
    }

    function testHealthfactor(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        public
    {
        uint256 actualHF;

        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);
        morpho.accrueInterest(marketParams);

        uint256 expectedHF = snippets.userHealthFactor(marketParams, id, SUPPLIER);

        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        uint256 maxBorrow =
            morpho.collateral(id, SUPPLIER).mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(marketParams.lltv);

        uint256 borrowed = morpho.expectedBorrowAssets(marketParams, SUPPLIER);

        if (borrowed == 0) {
            actualHF = type(uint256).max;
        } else {
            actualHF = maxBorrow.wDivDown(borrowed);
        }
        assertEq(expectedHF, actualHF);
    }

    function testHealthfactor0Borrow(uint256 amountSupplied, uint256 timeElapsed, uint256 fee) public {
        uint256 amountBorrowed = 0;
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);
        morpho.accrueInterest(marketParams);

        uint256 expectedHF = snippets.userHealthFactor(marketParams, id, SUPPLIER);

        assertEq(expectedHF, type(uint256).max);
    }

    // ---- Test Managing Functions ----

    function testSupplyAssets(uint256 amount) public {
        amount = bound(amount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);

        loanToken.setBalance(SUPPLIER, amount);
        vm.prank(SUPPLIER);
        (uint256 returnAssets,) = snippets.supply(marketParams, amount, SUPPLIER);

        assertEq(returnAssets, amount, "returned asset amount");
    }

    function testSupplyCollateral(uint256 amount) public {
        amount = bound(amount, MIN_TEST_AMOUNT, MAX_COLLATERAL_ASSETS);

        collateralToken.setBalance(SUPPLIER, amount);
        vm.prank(SUPPLIER);
        snippets.supplyCollateral(marketParams, amount, SUPPLIER);

        assertEq(morpho.collateral(id, SUPPLIER), amount, "collateral");
    }

    function testWithdrawAmount(uint256 amountSupplied, uint256 amountWithdrawn) public {
        amountSupplied = bound(amountSupplied, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        amountWithdrawn = bound(amountWithdrawn, MIN_TEST_AMOUNT, amountSupplied);

        loanToken.setBalance(SUPPLIER, amountSupplied);
        vm.startPrank(SUPPLIER);
        snippets.supply(marketParams, amountSupplied, SUPPLIER);
        (uint256 assetsWithdrawn,) = snippets.withdrawAmount(marketParams, amountWithdrawn, SUPPLIER);
        vm.stopPrank();

        assertEq(assetsWithdrawn, amountWithdrawn, "returned asset amount");
        assertEq(morpho.expectedSupplyAssets(marketParams, SUPPLIER), amountSupplied - amountWithdrawn, "supply assets");
    }

    function testWithdraw50Percent(uint256 amount) public {
        amount = bound(amount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);

        loanToken.setBalance(SUPPLIER, amount);
        vm.startPrank(SUPPLIER);
        snippets.supply(marketParams, amount, SUPPLIER);
        (uint256 assetsWithdrawn,) = snippets.withdraw50Percent(marketParams, SUPPLIER);
        vm.stopPrank();

        assertEq(assetsWithdrawn, amount / 2, "returned asset amount");
    }

    function testWithdrawAll(uint256 amount) public {
        amount = bound(amount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);

        loanToken.setBalance(SUPPLIER, amount);
        vm.startPrank(SUPPLIER);
        snippets.supply(marketParams, amount, SUPPLIER);
        (uint256 assetsWithdrawn,) = snippets.withdrawAll(marketParams, SUPPLIER);
        vm.stopPrank();

        assertEq(assetsWithdrawn, amount, "returned asset amount");
        assertEq(morpho.expectedSupplyAssets(marketParams, SUPPLIER), 0, "supply assets");
    }

    function testWithdrawCollateral(uint256 amountSupplied, uint256 amountWithdrawn) public {
        amountSupplied = bound(amountSupplied, MIN_TEST_AMOUNT, MAX_COLLATERAL_ASSETS);
        amountWithdrawn = bound(amountWithdrawn, MIN_TEST_AMOUNT, amountSupplied);

        collateralToken.setBalance(SUPPLIER, amountSupplied);
        vm.startPrank(SUPPLIER);
        snippets.supplyCollateral(marketParams, amountSupplied, SUPPLIER);
        snippets.withdrawCollateral(marketParams, amountWithdrawn, SUPPLIER);
        vm.stopPrank();

        assertEq(morpho.collateral(id, SUPPLIER), amountSupplied - amountWithdrawn, "collateral");
    }

    function testBorrowAssets(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral
    ) public {
        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);

        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _supply(amountSupplied);

        oracle.setPrice(priceCollateral);

        collateralToken.setBalance(BORROWER, amountCollateral);
        vm.startPrank(BORROWER);
        snippets.supplyCollateral(marketParams, amountCollateral, BORROWER);
        (uint256 returnAssets,) = snippets.borrow(marketParams, amountBorrowed, BORROWER);
        vm.stopPrank();

        assertEq(returnAssets, amountBorrowed, "returned asset amount");
        assertEq(morpho.expectedBorrowAssets(marketParams, BORROWER), amountBorrowed, "borrow assets");
    }

    function testRepayAmount(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 amountRepaid,
        uint256 priceCollateral
    ) public {
        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);
        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _supply(amountSupplied);
        oracle.setPrice(priceCollateral);
        amountRepaid = bound(amountRepaid, 1, amountBorrowed);

        collateralToken.setBalance(BORROWER, amountCollateral);
        vm.startPrank(BORROWER);
        snippets.supplyCollateral(marketParams, amountCollateral, BORROWER);
        snippets.borrow(marketParams, amountBorrowed, BORROWER);
        (uint256 returnAssetsRepaid,) = snippets.repayAmount(marketParams, amountRepaid, BORROWER);
        vm.stopPrank();

        assertEq(returnAssetsRepaid, amountRepaid, "returned asset amount");
        assertEq(morpho.expectedBorrowAssets(marketParams, BORROWER), amountBorrowed - amountRepaid, "borrow assets");
    }

    function testRepay50Percent(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral
    ) public {
        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);
        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _supply(amountSupplied);
        oracle.setPrice(priceCollateral);

        collateralToken.setBalance(BORROWER, amountCollateral);
        vm.startPrank(BORROWER);
        snippets.supplyCollateral(marketParams, amountCollateral, BORROWER);
        (, uint256 returnBorrowShares) = snippets.borrow(marketParams, amountBorrowed, BORROWER);
        (, uint256 repaidShares) = snippets.repay50Percent(marketParams, BORROWER);
        vm.stopPrank();

        assertEq(repaidShares, returnBorrowShares / 2, "returned asset amount");
    }

    function testRepayAll(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 priceCollateral
    ) public {
        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);
        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        _supply(amountSupplied);
        oracle.setPrice(priceCollateral);

        collateralToken.setBalance(BORROWER, amountCollateral);
        vm.startPrank(BORROWER);
        snippets.supplyCollateral(marketParams, amountCollateral, BORROWER);
        snippets.borrow(marketParams, amountBorrowed, BORROWER);
        (uint256 repaidAssets,) = snippets.repayAll(marketParams, BORROWER);
        vm.stopPrank();

        assertEq(repaidAssets, amountBorrowed, "returned asset amount");
        assertEq(morpho.expectedBorrowAssets(marketParams, BORROWER), 0, "borrow assets");
    }

    function _generatePendingInterest(uint256 amountSupplied, uint256 amountBorrowed, uint256 blocks, uint256 fee)
        internal
    {
        amountSupplied = bound(amountSupplied, 0, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, 0, amountSupplied);
        blocks = _boundBlocks(blocks);
        fee = bound(fee, 0, MAX_FEE);

        // Set fee parameters.
        vm.startPrank(OWNER);
        if (fee != morpho.fee(id)) morpho.setFee(marketParams, fee);
        vm.stopPrank();

        if (amountSupplied > 0) {
            loanToken.setBalance(SUPPLIER, amountSupplied);
            vm.prank(SUPPLIER);
            morpho.supply(marketParams, amountSupplied, 0, SUPPLIER, hex"");

            if (amountBorrowed > 0) {
                uint256 collateralPrice = oracle.price();
                collateralToken.setBalance(
                    BORROWER, amountBorrowed.wDivUp(marketParams.lltv).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice)
                );

                vm.startPrank(BORROWER);
                morpho.supplyCollateral(
                    marketParams,
                    amountBorrowed.wDivUp(marketParams.lltv).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice),
                    BORROWER,
                    hex""
                );
                morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
                vm.stopPrank();
            }
        }

        _forward(blocks);
    }

    function _testMorphoLibCommon(uint256 amountSupplied, uint256 amountBorrowed, uint256 timestamp, uint256 fee)
        private
    {
        // Set fee parameters.
        if (fee != morpho.fee(id)) {
            vm.prank(OWNER);
            morpho.setFee(marketParams, fee);
        }

        // Set timestamp.
        vm.warp(timestamp);

        loanToken.setBalance(SUPPLIER, amountSupplied);
        vm.prank(SUPPLIER);
        morpho.supply(marketParams, amountSupplied, 0, SUPPLIER, hex"");

        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        collateralToken.setBalance(
            BORROWER, amountBorrowed.wDivUp(marketParams.lltv).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice)
        );

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(
            marketParams,
            amountBorrowed.wDivUp(marketParams.lltv).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice),
            BORROWER,
            hex""
        );
        morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Id, IMorpho, MarketParams, Market} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBlueSnippets} from "../../src/morpho-blue/MorphoBlueSnippets.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {MorphoLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoLib.sol";
import {MathLib} from "../../lib/morpho-blue/src/libraries/MathLib.sol";
import {SharesMathLib} from "../../lib/morpho-blue/src/libraries/SharesMathLib.sol";
import "../../lib/morpho-blue/test/forge/BaseTest.sol";

contract TestIntegrationSnippets is BaseTest {
    using MathLib for uint256;
    using MathLib for uint128;
    using MathLib for IMorpho;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;

    MarketParams internal idleMarketParams;
    Id internal idleMarketId;

    MorphoBlueSnippets internal snippets;

    function setUp() public virtual override {
        super.setUp();

        snippets = new MorphoBlueSnippets(address(morpho));

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

    function testSupplyAssetsUser(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        public
    {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);
        morpho.accrueInterest(marketParams);

        uint256 actualSupplyAssets = snippets.supplyAssetsUser(marketParams, SUPPLIER);

        uint256 expectedSupplyAssets =
            morpho.supplyShares(id, SUPPLIER).toAssetsDown(morpho.totalSupplyAssets(id), morpho.totalSupplyShares(id));

        assertEq(actualSupplyAssets, expectedSupplyAssets);
    }

    function testBorrowAssetsUser(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        public
    {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);
        morpho.accrueInterest(marketParams);

        uint256 expectedBorrowAssets =
            morpho.borrowShares(id, BORROWER).toAssetsUp(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));

        uint256 actualBorrowAssets = snippets.borrowAssetsUser(marketParams, BORROWER);

        assertEq(actualBorrowAssets, expectedBorrowAssets);
    }

    function testCollateralAssetsUser(uint256 amountSupplied, uint256 amountBorrowed, uint256 timestamp, uint256 fee)
        public
    {
        amountSupplied = bound(amountSupplied, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, MIN_TEST_AMOUNT, amountSupplied);
        timestamp = bound(timestamp, block.timestamp, type(uint32).max);
        fee = bound(fee, 0, MAX_FEE);

        _testMorphoLibCommon(amountSupplied, amountBorrowed, timestamp, fee);

        uint256 actualCollateral = snippets.collateralAssetsUser(id, BORROWER);
        assertEq(morpho.collateral(id, BORROWER), actualCollateral);
    }

    function testMarketTotalSupply(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        public
    {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);

        uint256 actualTotalSupply = snippets.marketTotalSupply(marketParams);

        morpho.accrueInterest(marketParams);

        assertEq(actualTotalSupply, morpho.totalSupplyAssets(id));
    }

    function testMarketTotalBorrow(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        public
    {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);

        uint256 actualTotalBorrow = snippets.marketTotalBorrow(marketParams);

        morpho.accrueInterest(marketParams);

        assertEq(actualTotalBorrow, morpho.totalBorrowAssets(id));
    }

    function testBorrowAPY(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee) public {
        fee = bound(fee, 1, MAX_FEE);

        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);
        morpho.accrueInterest(marketParams);

        Market memory market = morpho.market(id);
        uint256 expectedBorrowApy = irm.borrowRateView(marketParams, market).wTaylorCompounded(365 days);
        uint256 borrowApy = snippets.borrowAPY(marketParams, market);

        assertEq(borrowApy, expectedBorrowApy, "Diff in snippets vs integration borrowAPY test");

        if (expectedBorrowApy > 0) {
            assertGt(borrowApy, 0, "The borrowApy should be greater than zero but was found to be zero.");
        }
    }

    function testBorrowAPYIdleMarket(Market memory market) public {
        uint256 borrowApy = snippets.borrowAPY(idleMarketParams, market);

        assertEq(borrowApy, 0, "borrow Apy");
    }

    function testSupplyAPYIdleMarket(uint256 amountSupplied, uint256 blocks, uint256 fee) public {
        _createIdleMarket();

        amountSupplied = bound(amountSupplied, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        blocks = _boundBlocks(blocks);
        fee = bound(fee, 0, MAX_FEE);

        vm.startPrank(OWNER);
        if (fee != morpho.fee(id)) morpho.setFee(idleMarketParams, fee);
        vm.stopPrank();

        if (amountSupplied > 0) {
            loanToken.setBalance(SUPPLIER, amountSupplied);
            vm.prank(SUPPLIER);
            morpho.supply(idleMarketParams, amountSupplied, 0, SUPPLIER, hex"");

            idleMarketParams.loanToken = address(loanToken);

            uint256 supplyApy = snippets.supplyAPY(idleMarketParams, morpho.market(idleMarketId));

            assertEq(supplyApy, 0, "supply Apy");
        }
    }

    function testSupplyAPY(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee) public {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);
        morpho.accrueInterest(marketParams);

        Market memory market = morpho.market(id);

        (uint256 totalSupplyAssets,, uint256 totalBorrowAssets,) = morpho.expectedMarketBalances(marketParams);

        uint256 borrowApy = irm.borrowRateView(marketParams, market).wTaylorCompounded(365 days);
        uint256 utilization = totalBorrowAssets == 0 ? 0 : totalBorrowAssets.wDivUp(totalSupplyAssets);

        uint256 expectedSupplyApy = borrowApy.wMulDown(1 ether - market.fee).wMulDown(utilization);

        uint256 supplyApy = snippets.supplyAPY(marketParams, market);

        assertEq(supplyApy, expectedSupplyApy, "Diff in snippets vs integration supplyAPY test");
        if (expectedSupplyApy > 0) {
            assertGt(supplyApy, 0, "The supplyApy should be greater than zero but was found to be zero.");
        }
    }

    function testHealthFactor(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        public
    {
        uint256 expectedHF;

        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);
        morpho.accrueInterest(marketParams);

        uint256 actualHF = snippets.userHealthFactor(marketParams, id, BORROWER);

        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        uint256 maxBorrow =
            morpho.collateral(id, BORROWER).mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(marketParams.lltv);

        uint256 borrowed = morpho.expectedBorrowAssets(marketParams, BORROWER);

        if (borrowed == 0) {
            expectedHF = type(uint256).max;
        } else {
            expectedHF = maxBorrow.wDivDown(borrowed);
        }
        assertEq(actualHF, expectedHF);
    }

    function testHealthFactor0Borrow(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed, uint256 fee)
        public
    {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);
        morpho.accrueInterest(marketParams);

        uint256 actualHF = snippets.userHealthFactor(marketParams, id, SUPPLIER);

        assertEq(actualHF, type(uint256).max);
    }

    function testVirtualRepaymentHealthFactor(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 timeElapsed,
        uint256 fee,
        uint256 repaymentAmount
    ) public {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);
        morpho.accrueInterest(marketParams);

        uint256 currentHF = snippets.userHealthFactor(marketParams, id, BORROWER);
        uint256 virtualHF = snippets.userHealthFactorAfterVirtualRepayment(marketParams, id, BORROWER, repaymentAmount);

        assertGe(virtualHF, currentHF, "Virtual HF should be greater than or equal to current HF after repayment");
    }

    function testVirtualBorrowHealthFactor(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 timeElapsed,
        uint256 fee,
        uint256 borrowAmount
    ) public {
        borrowAmount = bound(borrowAmount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT/2);
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);
        morpho.accrueInterest(marketParams);

        uint256 currentHF = snippets.userHealthFactor(marketParams, id, BORROWER);
        uint256 virtualHF = snippets.userHealthFactorAfterVirtualBorrow(marketParams, id, BORROWER, borrowAmount);

        assertLe(virtualHF, currentHF, "Virtual HF should be less than or equal to current HF after borrowing");
    }

    function testVirtualRepaymentFullRepay(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 timeElapsed,
        uint256 fee
    ) public {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);
        morpho.accrueInterest(marketParams);

        uint256 borrowed = morpho.expectedBorrowAssets(marketParams, BORROWER);
        uint256 virtualHF = snippets.userHealthFactorAfterVirtualRepayment(marketParams, id, BORROWER, borrowed);

        assertEq(virtualHF, type(uint256).max, "Virtual HF should be max when repaying full amount");
    }

    function testVirtualBorrowZeroAmount(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 timeElapsed,
        uint256 fee
    ) public {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);
        morpho.accrueInterest(marketParams);

        uint256 currentHF = snippets.userHealthFactor(marketParams, id, BORROWER);
        uint256 virtualHF = snippets.userHealthFactorAfterVirtualBorrow(marketParams, id, BORROWER, 0);

        assertEq(virtualHF, currentHF, "Virtual HF should equal current HF when borrowing zero");
    }

    // ---- Test Managing Functions ----

    function testSupplyAssets(uint256 amount) public {
        amount = bound(amount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);

        loanToken.setBalance(SUPPLIER, amount);
        vm.prank(SUPPLIER);
        (uint256 returnAssets,) = snippets.supply(marketParams, amount);

        assertEq(returnAssets, amount, "returned asset amount");
    }

    function testSupplyCollateral(uint256 amount) public {
        amount = bound(amount, MIN_TEST_AMOUNT, MAX_COLLATERAL_ASSETS);

        collateralToken.setBalance(BORROWER, amount);
        vm.prank(BORROWER);
        snippets.supplyCollateral(marketParams, amount);

        assertEq(morpho.collateral(id, BORROWER), amount, "collateral");
    }

    function testWithdrawAmount(uint256 amountSupplied, uint256 amountWithdrawn) public {
        amountSupplied = bound(amountSupplied, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        amountWithdrawn = bound(amountWithdrawn, MIN_TEST_AMOUNT, amountSupplied);

        loanToken.setBalance(SUPPLIER, amountSupplied);
        vm.startPrank(SUPPLIER);
        snippets.supply(marketParams, amountSupplied);
        (uint256 assetsWithdrawn,) = snippets.withdrawAmount(marketParams, amountWithdrawn);
        vm.stopPrank();

        assertEq(assetsWithdrawn, amountWithdrawn, "returned asset amount");
        assertEq(amountSupplied - amountWithdrawn, morpho.expectedSupplyAssets(marketParams, SUPPLIER), "supply assets");
    }

    function testWithdraw50Percent(uint256 amount) public {
        amount = bound(amount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);

        loanToken.setBalance(SUPPLIER, amount);
        vm.startPrank(SUPPLIER);
        snippets.supply(marketParams, amount);
        (uint256 assetsWithdrawn,) = snippets.withdraw50Percent(marketParams);
        vm.stopPrank();

        assertEq(assetsWithdrawn, amount / 2, "returned asset amount");
    }

    function testWithdrawAll(uint256 amount) public {
        amount = bound(amount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);

        loanToken.setBalance(SUPPLIER, amount);
        vm.startPrank(SUPPLIER);
        snippets.supply(marketParams, amount);
        (uint256 assetsWithdrawn,) = snippets.withdrawAll(marketParams);
        vm.stopPrank();

        assertEq(assetsWithdrawn, amount, "returned asset amount");
        assertEq(morpho.expectedSupplyAssets(marketParams, SUPPLIER), 0, "supply assets");
    }

    function testWithdrawAmountOrAll(uint256 amountSuplied, uint256 amountWithdrawn) public {
        amountSuplied = bound(amountSuplied, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        amountWithdrawn = bound(amountWithdrawn, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        loanToken.setBalance(SUPPLIER, amountSuplied);

        vm.startPrank(SUPPLIER);
        snippets.supply(marketParams, amountSuplied);
        (uint256 assetsWithdrawn,) = snippets.withdrawAmountOrAll(marketParams, amountWithdrawn);
        vm.stopPrank();

        if (amountSuplied >= amountWithdrawn) {
            assertEq(assetsWithdrawn, amountWithdrawn, "returned asset amount");
            assertEq(
                morpho.expectedSupplyAssets(marketParams, SUPPLIER), amountSuplied - amountWithdrawn, "supply assets"
            );
        } else {
            assertEq(assetsWithdrawn, amountSuplied, "returned asset amount");
            assertEq(morpho.expectedSupplyAssets(marketParams, SUPPLIER), 0, "supply assets");
        }
    }

    function testWithdrawCollateral(uint256 amountSupplied, uint256 amountWithdrawn) public {
        amountSupplied = bound(amountSupplied, MIN_TEST_AMOUNT, MAX_COLLATERAL_ASSETS);
        amountWithdrawn = bound(amountWithdrawn, MIN_TEST_AMOUNT, amountSupplied);

        collateralToken.setBalance(BORROWER, amountSupplied);
        vm.startPrank(BORROWER);
        snippets.supplyCollateral(marketParams, amountSupplied);
        snippets.withdrawCollateral(marketParams, amountWithdrawn);
        vm.stopPrank();

        assertEq(morpho.collateral(id, BORROWER), amountSupplied - amountWithdrawn, "collateral");
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
        oracle.setPrice(priceCollateral);

        _supply(amountSupplied);

        collateralToken.setBalance(BORROWER, amountCollateral);
        vm.startPrank(BORROWER);
        snippets.supplyCollateral(marketParams, amountCollateral);
        (uint256 returnAssets,) = snippets.borrow(marketParams, amountBorrowed);
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
        oracle.setPrice(priceCollateral);
        amountRepaid = bound(amountRepaid, 1, amountBorrowed);

        _supply(amountSupplied);

        collateralToken.setBalance(BORROWER, amountCollateral);
        vm.startPrank(BORROWER);
        snippets.supplyCollateral(marketParams, amountCollateral);
        snippets.borrow(marketParams, amountBorrowed);
        (uint256 returnAssetsRepaid,) = snippets.repayAmount(marketParams, amountRepaid);
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
        oracle.setPrice(priceCollateral);

        _supply(amountSupplied);

        collateralToken.setBalance(BORROWER, amountCollateral);
        vm.startPrank(BORROWER);
        snippets.supplyCollateral(marketParams, amountCollateral);
        (, uint256 returnBorrowShares) = snippets.borrow(marketParams, amountBorrowed);
        (, uint256 repaidShares) = snippets.repay50Percent(marketParams);
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
        oracle.setPrice(priceCollateral);

        _supply(amountSupplied);

        collateralToken.setBalance(BORROWER, amountCollateral);
        vm.startPrank(BORROWER);
        snippets.supplyCollateral(marketParams, amountCollateral);
        snippets.borrow(marketParams, amountBorrowed);
        (uint256 repaidAssets,) = snippets.repayAll(marketParams);
        vm.stopPrank();

        assertEq(repaidAssets, amountBorrowed, "returned asset amount");
        assertEq(morpho.expectedBorrowAssets(marketParams, BORROWER), 0, "borrow assets");
    }

    function testRepayAmountOrAll(
        uint256 amountCollateral,
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 amountRepaid,
        uint256 priceCollateral
    ) public {
        (amountCollateral, amountBorrowed, priceCollateral) =
            _boundHealthyPosition(amountCollateral, amountBorrowed, priceCollateral);
        oracle.setPrice(priceCollateral);
        amountSupplied = bound(amountSupplied, amountBorrowed, MAX_TEST_AMOUNT);
        amountRepaid = bound(amountRepaid, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);

        _supply(amountSupplied);
        collateralToken.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        snippets.supplyCollateral(marketParams, amountCollateral);
        snippets.borrow(marketParams, amountBorrowed);
        (uint256 returnAssetsRepaid,) = snippets.repayAmountOrAll(marketParams, amountRepaid);
        vm.stopPrank();

        if (amountBorrowed >= amountRepaid) {
            assertEq(returnAssetsRepaid, amountRepaid, "returned asset amount");
            assertEq(
                morpho.expectedBorrowAssets(marketParams, BORROWER), amountBorrowed - amountRepaid, "borrow assets"
            );
        } else {
            assertEq(returnAssetsRepaid, amountBorrowed, "returned asset amount");
            assertEq(morpho.expectedBorrowAssets(marketParams, BORROWER), 0, "borrow assets");
        }
    }

    function _generatePendingInterest(uint256 amountSupplied, uint256 amountBorrowed, uint256 blocks, uint256 fee)
        internal
    {
        amountSupplied = bound(amountSupplied, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, MIN_TEST_AMOUNT, amountSupplied);
        blocks = _boundBlocks(blocks);
        fee = bound(fee, 0, MAX_FEE);

        vm.startPrank(OWNER);
        if (fee != morpho.fee(id)) morpho.setFee(marketParams, fee);
        vm.stopPrank();

        loanToken.setBalance(SUPPLIER, amountSupplied);
        vm.prank(SUPPLIER);
        morpho.supply(marketParams, amountSupplied, 0, SUPPLIER, hex"");

        uint256 collateralPrice = oracle.price();
        uint256 amountCollateral =
            amountBorrowed.wDivUp(marketParams.lltv).mulDivUp(ORACLE_PRICE_SCALE, collateralPrice);
        collateralToken.setBalance(BORROWER, amountCollateral);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, amountCollateral, BORROWER, hex"");
        morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        _forward(blocks);
    }

    function _testMorphoLibCommon(uint256 amountSupplied, uint256 amountBorrowed, uint256 timestamp, uint256 fee)
        private
    {
        if (fee != morpho.fee(id)) {
            vm.prank(OWNER);
            morpho.setFee(marketParams, fee);
        }

        vm.warp(timestamp);

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

    function _createIdleMarket() internal {
        idleMarketParams = MarketParams(address(loanToken), address(0), address(0), address(0), 0);
        idleMarketId = idleMarketParams.id();

        vm.startPrank(OWNER);
        if (!morpho.isLltvEnabled(0)) morpho.enableLltv(0);
        if (morpho.lastUpdate(idleMarketParams.id()) == 0) morpho.createMarket(idleMarketParams);
        vm.stopPrank();

        _forward(1);
    }
}

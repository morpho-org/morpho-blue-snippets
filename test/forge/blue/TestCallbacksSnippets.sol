// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "@morpho-blue-test/BaseTest.sol";
import {SwapMock} from "@snippets/blue/mocks/SwapMock.sol";
import {CallbacksSnippets} from "@snippets/blue/CallbacksSnippets.sol";

contract CallbacksIntegrationTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;

    SwapMock internal swapMock;

    CallbacksSnippets public snippets;

    function setUp() public virtual override {
        super.setUp();
        swapMock = new SwapMock(address(collateralToken), address(loanToken), address(oracle));
        snippets = new CallbacksSnippets(address(morpho)); // todos add the addres of WETH, lido, wsteth
    }

    function testLeverageMe(uint256 collateralInitAmount) public {
        // INITIALISATION

        uint256 leverageFactor = 4; // nb to set
        uint256 loanLeverageFactor = 3; // max here would be 3.2 = 0.8 * leverageFactor

        collateralInitAmount = bound(collateralInitAmount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT / leverageFactor);

        collateralToken.setBalance(address(snippets), collateralInitAmount);

        uint256 collateralAmount = collateralInitAmount * leverageFactor;

        oracle.setPrice(ORACLE_PRICE_SCALE);

        // supplying enough liquidity in the market
        vm.startPrank(SUPPLIER);
        loanToken.setBalance(address(SUPPLIER), collateralAmount);
        morpho.supply(marketParams, collateralAmount, 0, address(SUPPLIER), hex"");
        vm.stopPrank();

        // approve the swap contract
        vm.startPrank(address(snippets));
        loanToken.approve(address(morpho), type(uint256).max);
        loanToken.approve(address(swapMock), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(swapMock), type(uint256).max);
        vm.stopPrank();

        uint256 loanAmount = collateralInitAmount * loanLeverageFactor;

        snippets.leverageMe(leverageFactor, loanLeverageFactor, collateralInitAmount, swapMock, marketParams);

        assertGt(morpho.borrowShares(marketParams.id(), address(snippets)), 0, "no borrow");
        assertEq(morpho.collateral(marketParams.id(), address(snippets)), collateralAmount, "no collateral");
        assertEq(morpho.expectedBorrowAssets(marketParams, address(snippets)), loanAmount, "no collateral");
    }

    function testDeLeverageMe(uint256 collateralInitAmount) public {
        /// same as testLeverageMe

        uint256 leverageFactor = 4; // nb to set
        uint256 loanLeverageFactor = 3; // max here would be 3.2 = 0.8 * leverageFactor

        collateralInitAmount = bound(collateralInitAmount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT / leverageFactor);

        collateralToken.setBalance(address(snippets), collateralInitAmount);

        uint256 collateralAmount = collateralInitAmount * leverageFactor;

        oracle.setPrice(ORACLE_PRICE_SCALE);

        vm.startPrank(SUPPLIER);
        loanToken.setBalance(address(SUPPLIER), collateralAmount);
        morpho.supply(marketParams, collateralAmount, 0, address(SUPPLIER), hex"");
        vm.stopPrank();

        vm.startPrank(address(snippets));
        loanToken.approve(address(morpho), type(uint256).max);
        loanToken.approve(address(swapMock), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(swapMock), type(uint256).max);
        vm.stopPrank();

        uint256 loanAmount = collateralInitAmount * loanLeverageFactor;

        snippets.leverageMe(leverageFactor, loanLeverageFactor, collateralInitAmount, swapMock, marketParams);

        assertGt(morpho.borrowShares(marketParams.id(), address(snippets)), 0, "no borrow");
        assertEq(morpho.collateral(marketParams.id(), address(snippets)), collateralAmount, "no collateral");
        assertEq(morpho.expectedBorrowAssets(marketParams, address(snippets)), loanAmount, "no collateral");

        /// end of testLeverageMe

        uint256 amountRepayed =
            snippets.deLeverageMe(leverageFactor, loanLeverageFactor, collateralInitAmount, swapMock, marketParams);

        assertEq(morpho.borrowShares(marketParams.id(), address(snippets)), 0, "no borrow");
        assertEq(amountRepayed, loanAmount, "no repaid");
    }

    struct LiquidateTestParams {
        uint256 amountCollateral;
        uint256 amountSupplied;
        uint256 amountBorrowed;
        uint256 priceCollateral;
        uint256 lltv;
    }

    // TODOS: implement the following function
    // function testLiquidateWithoutCollateral(LiquidateTestParams memory params, uint256 amountSeized) public {
    //     _setLltv(_boundTestLltv(params.lltv));
    //     (params.amountCollateral, params.amountBorrowed, params.priceCollateral) =
    //         _boundUnhealthyPosition(params.amountCollateral, params.amountBorrowed, params.priceCollateral);

    //     vm.assume(params.amountCollateral > 1);

    //     params.amountSupplied =
    //         bound(params.amountSupplied, params.amountBorrowed, params.amountBorrowed + MAX_TEST_AMOUNT);
    //     _supply(params.amountSupplied);

    //     collateralToken.setBalance(BORROWER, params.amountCollateral);

    //     oracle.setPrice(type(uint256).max / params.amountCollateral);

    //     vm.startPrank(BORROWER);
    //     morpho.supplyCollateral(marketParams, params.amountCollateral, BORROWER, hex"");
    //     morpho.borrow(marketParams, params.amountBorrowed, 0, BORROWER, BORROWER);
    //     vm.stopPrank();

    //     oracle.setPrice(params.priceCollateral);

    //     // uint256 borrowShares = morpho.borrowShares(id, BORROWER);
    //     uint256 liquidationIncentiveFactor = _liquidationIncentiveFactor(marketParams.lltv);
    //     uint256 maxSeized = params.amountBorrowed.wMulDown(liquidationIncentiveFactor).mulDivDown(
    //         ORACLE_PRICE_SCALE, params.priceCollateral
    //     );
    //     vm.assume(maxSeized != 0);

    //     amountSeized = bound(amountSeized, 1, Math.min(maxSeized, params.amountCollateral - 1));

    //     uint256 expectedRepaid =
    //         amountSeized.mulDivUp(params.priceCollateral, ORACLE_PRICE_SCALE).wDivUp(liquidationIncentiveFactor);
    //     // uint256 expectedRepaidShares =
    //     // expectedRepaid.toSharesDown(morpho.totalBorrowAssets(id), morpho.totalBorrowShares(id));

    //     vm.startPrank(address(snippets));
    //     loanToken.approve(address(morpho), type(uint256).max);
    //     loanToken.approve(address(swapMock), type(uint256).max);
    //     collateralToken.approve(address(morpho), type(uint256).max);
    //     collateralToken.approve(address(swapMock), type(uint256).max);
    //     loanToken.approve(address(snippets), type(uint256).max);
    //     collateralToken.approve(address(snippets), type(uint256).max);
    //     loanToken.setBalance(address(snippets), params.amountBorrowed);

    //     // vm.prank(LIQUIDATOR);

    //     (uint256 returnSeized, uint256 returnRepaid) =
    //         snippets.liquidateWithoutCollat(BORROWER, params.amountBorrowed, amountSeized, swapMock, marketParams);
    //     // morpho.liquidate(marketParams, BORROWER, amountSeized, 0, hex"");
    //     // uint256 expectedCollateral = params.amountCollateral - amountSeized;
    //     // uint256 expectedBorrowed = params.amountBorrowed - expectedRepaid;
    //     // uint256 expectedBorrowShares = borrowShares - expectedRepaidShares;

    //     assertEq(returnSeized, amountSeized, "returned seized amount");
    //     assertEq(returnRepaid, expectedRepaid, "returned asset amount");
    //     // assertEq(morpho.borrowShares(id, BORROWER), expectedBorrowShares, "borrow shares");
    //     // assertEq(morpho.totalBorrowAssets(id), expectedBorrowed, "total borrow");
    //     // assertEq(morpho.totalBorrowShares(id), expectedBorrowShares, "total borrow shares");
    //     // assertEq(morpho.collateral(id, BORROWER), expectedCollateral, "collateral");
    //     // assertEq(loanToken.balanceOf(BORROWER), params.amountBorrowed, "borrower balance");
    //     // assertEq(loanToken.balanceOf(LIQUIDATOR), expectedBorrowed, "liquidator balance");
    //     // assertEq(loanToken.balanceOf(address(morpho)), params.amountSupplied - expectedBorrowed, "morpho
    // balance");
    //     // assertEq(collateralToken.balanceOf(address(morpho)), expectedCollateral, "morpho collateral balance");
    //     // assertEq(collateralToken.balanceOf(LIQUIDATOR), amountSeized, "liquidator collateral balance");
    // }
}

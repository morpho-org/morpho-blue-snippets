// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "@morpho-blue-test/BaseTest.sol";
import {ISwap} from "@snippets/blue/interfaces/ISwap.sol";
import {SwapMock} from "@snippets/blue/mocks/SwapMock.sol";
import {CallbacksSnippets} from "@snippets/blue/CallbacksSnippets.sol";
import {ERC20} from "@solmate/utils/SafeTransferLib.sol";

contract CallbacksIntegrationTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;

    address internal USER;

    ISwap internal swapper;

    CallbacksSnippets public snippets;

    function setUp() public virtual override {
        super.setUp();

        USER = makeAddr("User");

        swapper = ISwap(address(new SwapMock(address(collateralToken), address(loanToken), address(oracle))));
        snippets = new CallbacksSnippets(morpho, swapper);

        vm.startPrank(USER);
        collateralToken.approve(address(snippets), type(uint256).max);
        morpho.setAuthorization(address(snippets), true);
        vm.stopPrank();
    }

    function testLeverageMe(uint256 initAmountCollateral, uint256 leverageFactor) public {
        uint256 maxLeverageFactor = WAD / (WAD - marketParams.lltv);

        leverageFactor = bound(leverageFactor, 2, maxLeverageFactor);
        initAmountCollateral = bound(initAmountCollateral, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT / leverageFactor);
        uint256 finalAmountCollateral = initAmountCollateral * leverageFactor;

        oracle.setPrice(ORACLE_PRICE_SCALE);
        loanToken.setBalance(SUPPLIER, finalAmountCollateral);
        collateralToken.setBalance(USER, initAmountCollateral);

        vm.prank(SUPPLIER);
        morpho.supply(marketParams, finalAmountCollateral, 0, SUPPLIER, hex"");

        vm.prank(USER);
        snippets.leverageMe(leverageFactor, initAmountCollateral, marketParams);

        uint256 loanAmount = initAmountCollateral * (leverageFactor - 1);

        assertGt(morpho.borrowShares(marketParams.id(), USER), 0, "no borrow");
        assertEq(morpho.collateral(marketParams.id(), USER), finalAmountCollateral, "no collateral");
        assertEq(morpho.expectedBorrowAssets(marketParams, USER), loanAmount, "no collateral");
    }

    function testDeLeverageMe(uint256 initAmountCollateral, uint256 leverageFactor) public {
        uint256 maxLeverageFactor = WAD / (WAD - marketParams.lltv);

        leverageFactor = bound(leverageFactor, 2, maxLeverageFactor);
        initAmountCollateral = bound(initAmountCollateral, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT / leverageFactor);
        uint256 finalAmountCollateral = initAmountCollateral * leverageFactor;

        oracle.setPrice(ORACLE_PRICE_SCALE);
        loanToken.setBalance(SUPPLIER, finalAmountCollateral);
        collateralToken.setBalance(USER, initAmountCollateral);

        vm.prank(SUPPLIER);
        morpho.supply(marketParams, finalAmountCollateral, 0, SUPPLIER, hex"");

        uint256 loanAmount = initAmountCollateral * (leverageFactor - 1);

        vm.prank(USER);
        snippets.leverageMe(leverageFactor, initAmountCollateral, marketParams);

        assertGt(morpho.borrowShares(marketParams.id(), USER), 0, "no borrow");
        assertEq(morpho.collateral(marketParams.id(), USER), finalAmountCollateral, "no collateral");
        assertEq(morpho.expectedBorrowAssets(marketParams, USER), loanAmount, "no collateral");

        /// end of testLeverageMe
        vm.prank(USER);
        uint256 amountRepayed = snippets.deLeverageMe(marketParams);

        assertEq(morpho.borrowShares(marketParams.id(), USER), 0, "no borrow");
        assertEq(amountRepayed, loanAmount, "no repaid");
        assertEq(
            ERC20(marketParams.collateralToken).balanceOf(USER), initAmountCollateral, "user didn't get back his assets"
        );
    }

    struct LiquidateTestParams {
        uint256 amountCollateral;
        uint256 amountSupplied;
        uint256 amountBorrowed;
        uint256 priceCollateral;
        uint256 lltv;
    }

    function testLiquidateSeizeAllCollateral(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);

        uint256 collateralAmount = borrowAmount.wDivUp(marketParams.lltv);

        oracle.setPrice(ORACLE_PRICE_SCALE);
        loanToken.setBalance(SUPPLIER, borrowAmount);
        collateralToken.setBalance(BORROWER, collateralAmount);

        vm.prank(SUPPLIER);
        morpho.supply(marketParams, borrowAmount, 0, SUPPLIER, hex"");

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, collateralAmount, BORROWER, hex"");
        morpho.borrow(marketParams, borrowAmount, 0, BORROWER, BORROWER);
        vm.stopPrank();

        oracle.setPrice(ORACLE_PRICE_SCALE / 2);

        vm.prank(LIQUIDATOR);
        snippets.fullLiquidationWithoutCollat(marketParams, BORROWER, true);

        assertEq(morpho.collateral(marketParams.id(), BORROWER), 0, "not fully liquididated");
        assertGt(ERC20(marketParams.loanToken).balanceOf(LIQUIDATOR), 0, "Liquidator didn't receive profit");
    }

    function testLiquidateRepayAllShares(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);

        uint256 collateralAmount = borrowAmount.wDivUp(marketParams.lltv);

        oracle.setPrice(ORACLE_PRICE_SCALE);
        loanToken.setBalance(SUPPLIER, borrowAmount);
        collateralToken.setBalance(BORROWER, collateralAmount);

        vm.prank(SUPPLIER);
        morpho.supply(marketParams, borrowAmount, 0, SUPPLIER, hex"");

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, collateralAmount, BORROWER, hex"");
        morpho.borrow(marketParams, borrowAmount, 0, BORROWER, BORROWER);
        vm.stopPrank();

        oracle.setPrice(ORACLE_PRICE_SCALE.wMulDown(0.95e18));

        vm.prank(LIQUIDATOR);
        snippets.fullLiquidationWithoutCollat(marketParams, BORROWER, false);

        assertEq(morpho.borrowShares(marketParams.id(), BORROWER), 0, "not fully liquididated");
        assertGt(ERC20(marketParams.loanToken).balanceOf(LIQUIDATOR), 0, "Liquidator didn't receive profit");
    }
}

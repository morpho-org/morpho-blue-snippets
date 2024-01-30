// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "../../lib/morpho-blue/test/forge/BaseTest.sol";
import {ISwap} from "../../src/morpho-blue/interfaces/ISwap.sol";
import {SwapMock} from "../../src/morpho-blue/mocks/SwapMock.sol";
import {LiquidationSnippets} from "../../src/morpho-blue/LiquidationSnippets.sol";
import {ERC20} from "../../lib/solmate/src/utils/SafeTransferLib.sol";

contract LiquidationSnippetsTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;

    address internal USER;

    ISwap internal swapper;

    LiquidationSnippets public snippets;

    function setUp() public virtual override {
        super.setUp();

        USER = makeAddr("User");

        swapper = ISwap(address(new SwapMock(address(collateralToken), address(loanToken), address(oracle))));
        snippets = new LiquidationSnippets(morpho, swapper);

        vm.startPrank(USER);
        collateralToken.approve(address(snippets), type(uint256).max);
        morpho.setAuthorization(address(snippets), true);
        vm.stopPrank();
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

        assertEq(morpho.collateral(marketParams.id(), BORROWER), 0, "not fully liquidated");
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

    function testLiquidationImpossible(uint256 borrowAmount) public {
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

        vm.prank(LIQUIDATOR);
        vm.expectRevert(bytes(ErrorsLib.HEALTHY_POSITION));
        snippets.fullLiquidationWithoutCollat(marketParams, BORROWER, false);
    }

    // function testLiquidateNotCreatedMarket(MarketParams memory marketParamsFuzz, uint256 lltv) public {
    //     uint256 borrowAmount = bound(1 ether, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);

    //     uint256 collateralAmount = borrowAmount.wDivUp(marketParams.lltv);

    //     oracle.setPrice(ORACLE_PRICE_SCALE);
    //     loanToken.setBalance(SUPPLIER, borrowAmount);
    //     collateralToken.setBalance(BORROWER, collateralAmount);

    //     vm.prank(SUPPLIER);
    //     morpho.supply(marketParams, borrowAmount, 0, SUPPLIER, hex"");

    //     vm.startPrank(BORROWER);
    //     morpho.supplyCollateral(marketParams, collateralAmount, BORROWER, hex"");
    //     morpho.borrow(marketParams, borrowAmount, 0, BORROWER, BORROWER);
    //     vm.stopPrank();

    //     _setLltv(_boundTestLltv(lltv));
    //     vm.assume(neq(marketParamsFuzz, marketParams));

    //     vm.prank(LIQUIDATOR);
    //     vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
    //     snippets.fullLiquidationWithoutCollat(marketParamsFuzz, BORROWER, false);
    // }
}

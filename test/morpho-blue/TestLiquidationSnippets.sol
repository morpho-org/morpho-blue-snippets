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

    function testOnlyMorphoEnforcement() public {
        // Arrange: Deploy a malicious contract or use an EOA address different from Morpho's
        address maliciousUser = makeAddr("maliciousUser");

        // Act: Try calling a function protected by the onlyMorpho modifier
        vm.startPrank(maliciousUser);
        (bool success,) = address(snippets).call(abi.encodeWithSelector(snippets.onMorphoLiquidate.selector, 0, ""));
        vm.stopPrank();

        // Assert: The call should fail if the onlyMorpho modifier is correctly implemented
        assertEq(success, false, "Function should not be callable by addresses other than Morpho");
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
}

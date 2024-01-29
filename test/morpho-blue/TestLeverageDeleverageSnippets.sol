// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "../../lib/morpho-blue/test/forge/BaseTest.sol";
import {ISwap} from "../../src/morpho-blue/interfaces/ISwap.sol";
import {SwapMock} from "../../src/morpho-blue/mocks/SwapMock.sol";
import {LeverageDeleverageSnippets} from "../../src/morpho-blue/LeverageDeleverageSnippets.sol";
import {ERC20} from "../../lib/solmate/src/utils/SafeTransferLib.sol";

contract LeverageDeleverageTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;

    address internal USER;

    ISwap internal swapper;

    LeverageDeleverageSnippets public snippets;

    function setUp() public virtual override {
        super.setUp();

        USER = makeAddr("User");

        swapper = ISwap(address(new SwapMock(address(collateralToken), address(loanToken), address(oracle))));
        snippets = new LeverageDeleverageSnippets(morpho, swapper);

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
}

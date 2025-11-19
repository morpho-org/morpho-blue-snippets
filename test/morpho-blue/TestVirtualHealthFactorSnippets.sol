// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Id, IMorpho, MarketParams} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {VirtualHealthFactorSnippets} from "../../src/morpho-blue/VirtualHealthFactor.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {MorphoLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoLib.sol";
import {MathLib} from "../../lib/morpho-blue/src/libraries/MathLib.sol";
import "../../lib/morpho-blue/test/forge/BaseTest.sol";

contract TestIntegrationSnippets is BaseTest {
    using MathLib for uint256;
    using MathLib for uint128;
    using MathLib for IMorpho;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;

    MarketParams internal idleMarketParams;
    Id internal idleMarketId;

    VirtualHealthFactorSnippets internal snippets;

    function setUp() public virtual override {
        super.setUp();

        snippets = new VirtualHealthFactorSnippets(address(morpho));

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

    function testVirtualRepaymentHealthFactor(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 timeElapsed,
        uint256 fee,
        uint256 repaymentAmount
    ) public {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);
        morpho.accrueInterest(marketParams);

        uint256 borrowed = morpho.expectedBorrowAssets(marketParams, BORROWER);
        repaymentAmount = bound(repaymentAmount, MIN_TEST_AMOUNT, borrowed);

        uint256 currentHf = snippets.userHealthFactor(marketParams, id, BORROWER);
        uint256 virtualHf = snippets.userHealthFactorAfterVirtualRepayment(marketParams, id, BORROWER, repaymentAmount);

        assertGe(virtualHf, currentHf, "Virtual Hf should be greater than or equal to current Hf after repayment");
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

        uint256 currentHf = snippets.userHealthFactor(marketParams, id, BORROWER);
        uint256 virtualHf = snippets.userHealthFactorAfterVirtualBorrow(marketParams, id, BORROWER, borrowAmount);

        assertLe(virtualHf, currentHf, "Virtual Hf should be less than or equal to current Hf after borrowing");
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
        uint256 virtualHf = snippets.userHealthFactorAfterVirtualRepayment(marketParams, id, BORROWER, borrowed);

        assertEq(virtualHf, type(uint256).max, "Virtual Hf should be max when repaying full amount");
    }

    function testVirtualBorrowZeroAmount(
        uint256 amountSupplied,
        uint256 amountBorrowed,
        uint256 timeElapsed,
        uint256 fee
    ) public {
        _generatePendingInterest(amountSupplied, amountBorrowed, timeElapsed, fee);
        morpho.accrueInterest(marketParams);

        uint256 currentHf = snippets.userHealthFactor(marketParams, id, BORROWER);
        uint256 virtualHf = snippets.userHealthFactorAfterVirtualBorrow(marketParams, id, BORROWER, 0);

        assertEq(virtualHf, currentHf, "Virtual Hf should equal current Hf when borrowing zero");
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
}
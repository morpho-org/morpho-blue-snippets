// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "@morpho-blue-test/BaseTest.sol";
import {SwapMock} from "@snippets/blue/mocks/SwapMock.sol";

contract TestIntegrationSnippets is BaseTest {
    SwapMock internal swapMock;

    function setUp() public virtual override {
        super.setUp();
        swapMock = new SwapMock(address(collateralToken), address(loanToken), address(oracle));
    }

    function testSwapCollatToLoan(uint256 amount) public {
        amount = bound(amount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        collateralToken.setBalance(address(this), amount);
        collateralToken.approve(address(swapMock), type(uint256).max);

        uint256 swappedAssets = swapMock.swapCollatToLoan(amount);
        assertEq(swappedAssets, amount, " error in swap");
    }

    function testSwapLoanToCollat(uint256 amount) public {
        amount = bound(amount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        loanToken.setBalance(address(this), amount);
        loanToken.approve(address(swapMock), type(uint256).max);

        uint256 swappedAssets = swapMock.swapLoanToCollat(amount);
        assertEq(swappedAssets, amount, " error in swap");
    }
}

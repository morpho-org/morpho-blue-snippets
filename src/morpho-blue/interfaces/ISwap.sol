// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ISwap
 * @dev Interface for the SwapMock contract.
 */
interface ISwap {
    /**
     * @dev Swaps collateral token to loan token.
     * @param amount The amount of collateral token to swap.
     * @return returnedAmount The amount of loan token returned.
     */
    function swapCollatToLoan(uint256 amount) external returns (uint256 returnedAmount);

    /**
     * @dev Swaps loan token to collateral token.
     * @param amount The amount of loan token to swap.
     * @return returnedAmount The amount of collateral token returned.
     */
    function swapLoanToCollat(uint256 amount) external returns (uint256 returnedAmount);
}

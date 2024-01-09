// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ORACLE_PRICE_SCALE} from "@morpho-blue/libraries/ConstantsLib.sol";

import "@morpho-blue/mocks/ERC20Mock.sol";
import {IOracle} from "@morpho-blue/interfaces/IOracle.sol";

import "@morpho-blue/libraries/MathLib.sol";

/// @title SwapMock
/// @notice Mock contract for swapping between collateral and loan tokens.
/// @dev Uses an Oracle for price data and MathLib for calculations.
contract SwapMock {
    using MathLib for uint256;

    ERC20Mock public immutable collateralToken;
    ERC20Mock public immutable loanToken;

    address public immutable oracle;

    /// @notice Creates a new SwapMock contract instance.
    /// @param collateralAddress The address of the collateral token.
    /// @param loanAddress The address of the loan token.
    /// @param oracleAddress The address of the oracle.
    constructor(address collateralAddress, address loanAddress, address oracleAddress) {
        collateralToken = ERC20Mock(collateralAddress);
        loanToken = ERC20Mock(loanAddress);

        oracle = oracleAddress;
    }

    /// @notice Swaps collateral token to loan token.
    /// @param amount The amount of collateral token to swap.
    /// @return returnedAmount The amount of loan token returned after the swap.
    function swapCollatToLoan(uint256 amount) external returns (uint256 returnedAmount) {
        returnedAmount = amount.mulDivDown(IOracle(oracle).price(), ORACLE_PRICE_SCALE);

        collateralToken.transferFrom(msg.sender, address(this), amount);

        loanToken.setBalance(address(this), returnedAmount);
        loanToken.transfer(msg.sender, returnedAmount);
    }

    /// @notice Swaps loan token to collateral token.
    /// @param amount The amount of loan token to swap.
    /// @return returnedAmount The amount of collateral token returned after the swap.
    function swapLoanToCollat(uint256 amount) external returns (uint256 returnedAmount) {
        returnedAmount = amount.mulDivDown(ORACLE_PRICE_SCALE, IOracle(oracle).price());

        loanToken.transferFrom(msg.sender, address(this), amount);

        collateralToken.setBalance(address(this), returnedAmount);
        collateralToken.transfer(msg.sender, returnedAmount);
    }
}

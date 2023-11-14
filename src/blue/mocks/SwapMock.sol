// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ORACLE_PRICE_SCALE} from "@morpho-blue/libraries/ConstantsLib.sol";

import "@morpho-blue/mocks/ERC20Mock.sol";
import {IOracle} from "@morpho-blue/interfaces/IOracle.sol";

import "@morpho-blue/libraries/MathLib.sol";

contract SwapMock {
    using MathLib for uint256;

    ERC20Mock public immutable collateralToken;
    ERC20Mock public immutable loanToken;

    address public immutable oracle;

    constructor(address collateralAddress, address loanAddress, address oracleAddress) {
        collateralToken = ERC20Mock(collateralAddress);
        loanToken = ERC20Mock(loanAddress);

        oracle = oracleAddress;
    }

    function swapCollatToLoan(uint256 amount) external returns (uint256 returnedAmount) {
        returnedAmount = amount.mulDivDown(IOracle(oracle).price(), ORACLE_PRICE_SCALE);

        collateralToken.transferFrom(msg.sender, address(this), amount);

        loanToken.setBalance(address(this), returnedAmount);
        loanToken.transfer(msg.sender, returnedAmount);
    }

    function swapLoanToCollat(uint256 amount) external returns (uint256 returnedAmount) {
        returnedAmount = amount.mulDivDown(ORACLE_PRICE_SCALE, IOracle(oracle).price());

        loanToken.transferFrom(msg.sender, address(this), amount);

        collateralToken.setBalance(address(this), returnedAmount);
        collateralToken.transfer(msg.sender, returnedAmount);
    }
}

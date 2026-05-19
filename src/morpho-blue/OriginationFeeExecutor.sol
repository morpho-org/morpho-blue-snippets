// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Id, IMorpho, MarketParams} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {SafeTransferLib, ERC20} from "../../lib/solmate/src/utils/SafeTransferLib.sol";

/// @title Origination Fee Executor
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Reference EIP-7702 delegation target for charging a one-shot origination fee on the borrowed asset.
/// @dev This contract has no owner or storage. It is intended to be called through a delegated EOA, so `address(this)`
/// is the borrower and the receiver of the net borrowed assets.
contract OriginationFeeExecutor {
    using MarketParamsLib for MarketParams;
    using SafeTransferLib for ERC20;

    uint256 public constant MAX_FEE_BPS = 1_000;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Emitted when a delegated EOA borrows and pays an origination fee.
    /// @param borrower The delegated EOA whose Morpho Blue borrow position is increased.
    /// @param marketId The identifier of the Morpho Blue market.
    /// @param userAssets The net loan-token amount left on the delegated EOA.
    /// @param feeAmount The loan-token amount delivered to `feeRecipient`.
    event OriginationFeeCharged(address indexed borrower, Id indexed marketId, uint256 userAssets, uint256 feeAmount);

    /// @notice Borrows from Morpho Blue and transfers an origination fee to `feeRecipient`.
    /// @dev Intended to be called as `<EOA>.borrowWithOriginationFee(...)` after the EOA has signed an EIP-7702
    /// delegation to this executor. The delegated EOA must call itself, so `msg.sender == address(this)`.
    /// @dev The fee is charged on the net amount requested: `fee = userAssets * feeBps / BPS_DENOMINATOR`. The EOA
    /// accrues interest on `userAssets + fee`, not only on `userAssets`.
    /// @param morpho The Morpho Blue contract.
    /// @param marketParams The Morpho Blue market to borrow from.
    /// @param userAssets The net amount of loan token to leave on the delegated EOA.
    /// @param feeBps The fee applied to `userAssets`, in basis points. For example, 200 is 2%.
    /// @param feeRecipient The address receiving origination fees in the loan token.
    /// @return feeAmount The amount of loan token routed to `feeRecipient`.
    /// @return totalBorrowed The gross amount borrowed on Morpho Blue.
    function borrowWithOriginationFee(
        IMorpho morpho,
        MarketParams calldata marketParams,
        uint256 userAssets,
        uint256 feeBps,
        address feeRecipient
    ) external returns (uint256 feeAmount, uint256 totalBorrowed) {
        require(msg.sender == address(this), "ONLY_SELF");
        require(feeRecipient != address(0), "ZERO_RECIPIENT");
        require(feeBps > 0 && feeBps <= MAX_FEE_BPS, "INVALID_FEE_BPS");

        feeAmount = userAssets * feeBps / BPS_DENOMINATOR;
        totalBorrowed = userAssets + feeAmount;

        morpho.borrow(marketParams, totalBorrowed, 0, address(this), address(this));

        ERC20(marketParams.loanToken).safeTransfer(feeRecipient, feeAmount);

        emit OriginationFeeCharged(address(this), marketParams.id(), userAssets, feeAmount);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Id, IMorpho, MarketParams} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {SafeTransferLib, ERC20} from "../../lib/solmate/src/utils/SafeTransferLib.sol";

/// @title Origination Fee Snippets
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Reference router for charging a one-shot origination fee on the borrowed asset.
/// @dev This contract is for educational purposes only. The fee recipient and fee bps are immutable so users can
/// inspect the exact fee policy before authorizing this router on Morpho Blue.
contract OriginationFeeSnippets {
    using MarketParamsLib for MarketParams;
    using SafeTransferLib for ERC20;

    IMorpho public immutable MORPHO;
    address public immutable FEE_RECIPIENT;
    uint256 public immutable FEE_BPS;

    uint256 public constant MAX_FEE_BPS = 1_000;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Emitted when a borrower opens debt through this router and pays the origination fee.
    /// @param borrower The user whose Morpho Blue borrow position is increased.
    /// @param marketId The identifier of the Morpho Blue market.
    /// @param userAssets The net loan-token amount delivered to the borrower.
    /// @param feeAmount The loan-token amount delivered to `FEE_RECIPIENT`.
    event OriginationFeeCharged(address indexed borrower, Id indexed marketId, uint256 userAssets, uint256 feeAmount);

    /// @notice Constructs an immutable origination-fee router.
    /// @param morpho The Morpho Blue contract.
    /// @param feeRecipient The address receiving origination fees in the loan token.
    /// @param feeBps The fee applied to `userAssets`, in basis points. For example, 200 is 2%.
    constructor(IMorpho morpho, address feeRecipient, uint256 feeBps) {
        require(feeRecipient != address(0), "ZERO_RECIPIENT");
        require(feeBps > 0 && feeBps <= MAX_FEE_BPS, "INVALID_FEE_BPS");

        MORPHO = morpho;
        FEE_RECIPIENT = feeRecipient;
        FEE_BPS = feeBps;
    }

    /// @notice Borrows on behalf of `msg.sender` and routes an origination fee to `FEE_RECIPIENT`.
    /// @dev The caller must have sufficient collateral supplied to `marketParams` and must have authorized this
    /// contract via `morpho.setAuthorization(address(this), true)`.
    /// @dev The fee is charged on the net amount requested: `fee = userAssets * FEE_BPS / BPS_DENOMINATOR`. The caller
    /// accrues interest on `userAssets + fee`, not only on `userAssets`.
    /// @param marketParams The Morpho Blue market to borrow from.
    /// @param userAssets The net amount of loan token the caller wants to receive.
    /// @return feeAmount The amount of loan token routed to `FEE_RECIPIENT`.
    /// @return totalBorrowed The gross amount borrowed on Morpho Blue.
    function borrowWithOriginationFee(MarketParams calldata marketParams, uint256 userAssets)
        external
        returns (uint256 feeAmount, uint256 totalBorrowed)
    {
        feeAmount = userAssets * FEE_BPS / BPS_DENOMINATOR;
        totalBorrowed = userAssets + feeAmount;

        MORPHO.borrow(marketParams, totalBorrowed, 0, msg.sender, address(this));

        ERC20(marketParams.loanToken).safeTransfer(FEE_RECIPIENT, feeAmount);
        ERC20(marketParams.loanToken).safeTransfer(msg.sender, userAssets);

        emit OriginationFeeCharged(msg.sender, marketParams.id(), userAssets, feeAmount);
    }
}

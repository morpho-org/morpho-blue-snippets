// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Id, IMorpho, MarketParams} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {SafeTransferLib, ERC20} from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import {Ownable} from "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title Origination Fee Snippets
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Reference router for charging a one-shot origination fee on the borrowed asset.
/// @dev This contract is for educational purposes only. Users authorizing this router on Morpho Blue trust the owner to
/// manage `feeRecipient` and `feeBps` within the hard-coded fee cap.
contract OriginationFeeSnippets is Ownable {
    using MarketParamsLib for MarketParams;
    using SafeTransferLib for ERC20;

    IMorpho public immutable MORPHO;
    address public feeRecipient;
    uint256 public feeBps;

    uint256 public constant MAX_FEE_BPS = 1_000;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Emitted when a borrower opens debt through this router and pays the origination fee.
    /// @param borrower The user whose Morpho Blue borrow position is increased.
    /// @param marketId The identifier of the Morpho Blue market.
    /// @param userAssets The net loan-token amount delivered to the borrower.
    /// @param feeAmount The loan-token amount delivered to `feeRecipient`.
    event OriginationFeeCharged(address indexed borrower, Id indexed marketId, uint256 userAssets, uint256 feeAmount);

    /// @notice Emitted when the owner updates the fee recipient.
    /// @param newFeeRecipient The address receiving future origination fees in the loan token.
    event FeeRecipientSet(address indexed newFeeRecipient);

    /// @notice Emitted when the owner updates the fee bps.
    /// @param newFeeBps The fee applied to future borrows, in basis points.
    event FeeBpsSet(uint256 newFeeBps);

    /// @notice Constructs an owner-managed origination-fee router.
    /// @param morpho The Morpho Blue contract.
    /// @param initialFeeRecipient The address receiving origination fees in the loan token.
    /// @param initialFeeBps The fee applied to `userAssets`, in basis points. For example, 200 is 2%.
    constructor(IMorpho morpho, address initialFeeRecipient, uint256 initialFeeBps) {
        MORPHO = morpho;

        _setFeeRecipient(initialFeeRecipient);
        _setFeeBps(initialFeeBps);
    }

    /// @notice Sets the address receiving future origination fees.
    /// @param newFeeRecipient The address receiving origination fees in the loan token.
    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        _setFeeRecipient(newFeeRecipient);
    }

    /// @notice Sets the fee applied to future borrows.
    /// @param newFeeBps The fee applied to `userAssets`, in basis points. For example, 200 is 2%.
    function setFeeBps(uint256 newFeeBps) external onlyOwner {
        _setFeeBps(newFeeBps);
    }

    /// @notice Borrows on behalf of `msg.sender` and routes an origination fee to `feeRecipient`.
    /// @dev The caller must have sufficient collateral supplied to `marketParams` and must have authorized this
    /// contract via `morpho.setAuthorization(address(this), true)`.
    /// @dev The fee is charged on the net amount requested: `fee = userAssets * feeBps / BPS_DENOMINATOR`. The caller
    /// accrues interest on `userAssets + fee`, not only on `userAssets`.
    /// @param marketParams The Morpho Blue market to borrow from.
    /// @param userAssets The net amount of loan token the caller wants to receive.
    /// @return feeAmount The amount of loan token routed to `feeRecipient`.
    /// @return totalBorrowed The gross amount borrowed on Morpho Blue.
    function borrowWithOriginationFee(MarketParams calldata marketParams, uint256 userAssets)
        external
        returns (uint256 feeAmount, uint256 totalBorrowed)
    {
        address currentFeeRecipient = feeRecipient;
        feeAmount = userAssets * feeBps / BPS_DENOMINATOR;
        totalBorrowed = userAssets + feeAmount;

        MORPHO.borrow(marketParams, totalBorrowed, 0, msg.sender, address(this));

        ERC20(marketParams.loanToken).safeTransfer(currentFeeRecipient, feeAmount);
        ERC20(marketParams.loanToken).safeTransfer(msg.sender, userAssets);

        emit OriginationFeeCharged(msg.sender, marketParams.id(), userAssets, feeAmount);
    }

    function _setFeeRecipient(address newFeeRecipient) internal {
        require(newFeeRecipient != address(0), "ZERO_RECIPIENT");

        feeRecipient = newFeeRecipient;

        emit FeeRecipientSet(newFeeRecipient);
    }

    function _setFeeBps(uint256 newFeeBps) internal {
        require(newFeeBps > 0 && newFeeBps <= MAX_FEE_BPS, "INVALID_FEE_BPS");

        feeBps = newFeeBps;

        emit FeeBpsSet(newFeeBps);
    }
}

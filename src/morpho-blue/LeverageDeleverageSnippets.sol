// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    IMorphoSupplyCollateralCallback,
    IMorphoRepayCallback
} from "../../lib/morpho-blue/src/interfaces/IMorphoCallbacks.sol";
import {ISwap} from "./interfaces/ISwap.sol";

import {Id, IMorpho, MarketParams} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {SafeTransferLib, ERC20} from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import {MorphoLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoLib.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";

// This Swapper contract is for educational purposes only. It demonstrates a token swap mechanism, leveraging
// an arbitrary oracle to determine the exchange rates.

// The primary purpose of introducing this Swapper contract is to illustrate how callbacks function within
// Morpho Blue, without specifically endorsing any existing DEX.

// It's important to replace the 'Swapper' with your preferred swap service in your actual implementation. Accordingly,
// the methods `swapCollatToLoan` and `swapLoanToCollat` should also be modified to align with the swap interface of
// your choice.

// When implementing a swap, consider the following:
//    1. Slippage,
//    2. Transaction fees.

contract LeverageDeleverageSnippets is IMorphoSupplyCollateralCallback, IMorphoRepayCallback {
    using MorphoLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using SafeTransferLib for ERC20;

    IMorpho public immutable morpho;
    ISwap public immutable swapper;

    constructor(IMorpho _morpho, ISwap _swapper) {
        morpho = _morpho;
        swapper = _swapper;
    }

    modifier onlyMorpho() {
        require(msg.sender == address(morpho), "msg.sender should be Morpho Blue");
        _;
    }

    // Type of collateral supply callback data.
    struct SupplyCollateralData {
        uint256 loanAmount;
        MarketParams marketParams;
        address user;
    }

    // Type of repay callback data.
    struct RepayData {
        MarketParams marketParams;
        address user;
    }

    function onMorphoSupplyCollateral(uint256 amount, bytes calldata data) external onlyMorpho {
        SupplyCollateralData memory decoded = abi.decode(data, (SupplyCollateralData));
        (uint256 amountBis,) = morpho.borrow(decoded.marketParams, decoded.loanAmount, 0, decoded.user, address(this));

        ERC20(decoded.marketParams.loanToken).approve(address(swapper), amount);

        // Logic to Implement. Following example is a swap, could be a 'unwrap + stake + wrap staked' for
        // wETH(wstETH) Market.
        swapper.swapLoanToCollat(amountBis);
    }

    function onMorphoRepay(uint256 amount, bytes calldata data) external onlyMorpho {
        RepayData memory decoded = abi.decode(data, (RepayData));
        uint256 toWithdraw = morpho.collateral(decoded.marketParams.id(), decoded.user);

        morpho.withdrawCollateral(decoded.marketParams, toWithdraw, decoded.user, address(this));

        ERC20(decoded.marketParams.collateralToken).approve(address(swapper), amount);
        swapper.swapCollatToLoan(amount);
    }

    /// @notice Creates a leveraged position with a specified `leverageFactor` on the `marketParams` market of Morpho
    /// Blue for the sender.
    /// @dev Requires the sender to hold `initAmountCollateral` and approve this contract to manage their positions on
    /// Morpho Blue (as this contract will borrow on behalf of the sender).
    /// @param leverageFactor The desired leverage factor, cannot exceed the limit of 1/1-LLTV.
    /// @param initAmountCollateral The initial amount of collateral held by the sender.
    /// @param marketParams Parameters of the market on which to execute the leverage operation.
    function leverageMe(uint256 leverageFactor, uint256 initAmountCollateral, MarketParams calldata marketParams)
        public
    {
        // Transfer the initial collateral from the sender to this contract.
        ERC20(marketParams.collateralToken).safeTransferFrom(msg.sender, address(this), initAmountCollateral);

        // Calculate the final amount of collateral based on the leverage factor.
        uint256 finalAmountCollateral = initAmountCollateral * leverageFactor;

        // Calculate the amount of LoanToken to be borrowed and swapped against CollateralToken.
        // Note: In this simplified example, the price is assumed to be `ORACLE_PRICE_SCALE`.
        // In a real-world scenario:
        // - The price might not equal `ORACLE_PRICE_SCALE`, and the oracle's price should be factored into the
        // calculation, like this:
        // (leverageFactor - 1) * initAmountCollateral.mulDivDown.(ORACLE_PRICE_SCALE, IOracle(oracle).price())
        // - Consideration for fees and slippage is crucial to accurately compute `loanAmount`.
        uint256 loanAmount = (leverageFactor - 1) * initAmountCollateral;

        // Approve the maximum amount to Morpho on behalf of the collateral token.
        _approveMaxTo(marketParams.collateralToken, address(morpho));

        // Supply the collateral to Morpho, initiating the leverage operation.
        morpho.supplyCollateral(
            marketParams,
            finalAmountCollateral,
            msg.sender,
            abi.encode(SupplyCollateralData(loanAmount, marketParams, msg.sender))
        );
    }

    /// @notice Deleverages the sender on the given `marketParams` market of Morpho Blue by repaying his debt and
    /// withdrawing his collateral. The withdrawn assets are sent to the sender.
    /// @dev If the sender has a leveraged position on `marketParams`, he doesn't need any tokens to perform this
    /// operation, but he needs to have approved this contract to manage their positions on Morpho Blue (as this
    /// contract will withdrawCollateral on behalf of the sender).
    /// @param marketParams Parameters of the market.
    function deLeverageMe(MarketParams calldata marketParams) public returns (uint256 amountRepaid) {
        uint256 totalShares = morpho.borrowShares(marketParams.id(), msg.sender);

        _approveMaxTo(marketParams.loanToken, address(morpho));

        (amountRepaid,) =
            morpho.repay(marketParams, 0, totalShares, msg.sender, abi.encode(RepayData(marketParams, msg.sender)));

        ERC20(marketParams.collateralToken).safeTransfer(
            msg.sender, ERC20(marketParams.collateralToken).balanceOf(address(this))
        );
    }

    function _approveMaxTo(address asset, address spender) internal {
        if (ERC20(asset).allowance(address(this), spender) == 0) {
            ERC20(asset).safeApprove(spender, type(uint256).max);
        }
    }
}

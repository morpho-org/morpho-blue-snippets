// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMorphoLiquidateCallback} from "../../lib/morpho-blue/src/interfaces/IMorphoCallbacks.sol";
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
// the method `swapCollatToLoan` should also be modified to align with the swap interface of
// your choice.

// When implementing a swap, consider the following:
//    1. Slippage,
//    2. Transaction fees.

contract LiquidationSnippets is IMorphoLiquidateCallback {
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

    // Type of liquidation callback data.
    struct LiquidateData {
        address collateralToken;
    }

    function onMorphoLiquidate(uint256, bytes calldata data) external onlyMorpho {
        LiquidateData memory decoded = abi.decode(data, (LiquidateData));

        ERC20(decoded.collateralToken).approve(address(swapper), type(uint256).max);

        swapper.swapCollatToLoan(ERC20(decoded.collateralToken).balanceOf(address(this)));
    }

    /// @notice Fully liquidates the borrow position of `borrower` on the given `marketParams` market of Morpho Blue and
    /// sends the profit of the liquidation to the sender.
    /// @dev Thanks to callbacks, the sender doesn't need to hold any tokens to perform this operation.
    /// @param marketParams The market to perform the liquidation on.
    /// @param borrower The owner of the liquidable borrow position.
    /// @param seizeFullCollat Pass `True` to seize all the collateral of `borrower`. Pass `False` to repay all of the
    /// `borrower`'s debt.
    function fullLiquidationWithoutCollat(MarketParams calldata marketParams, address borrower, bool seizeFullCollat)
        public
        returns (uint256 seizedAssets, uint256 repaidAssets)
    {
        Id id = marketParams.id();

        uint256 seizedCollateral;
        uint256 repaidShares;

        if (seizeFullCollat) seizedCollateral = morpho.collateral(id, borrower);
        else repaidShares = morpho.borrowShares(id, borrower);

        _approveMaxTo(marketParams.loanToken, address(morpho));

        (seizedAssets, repaidAssets) = morpho.liquidate(
            marketParams,
            borrower,
            seizedCollateral,
            repaidShares,
            abi.encode(LiquidateData(marketParams.collateralToken))
        );

        ERC20(marketParams.loanToken).safeTransfer(msg.sender, ERC20(marketParams.loanToken).balanceOf(address(this)));
    }

    function _approveMaxTo(address asset, address spender) internal {
        if (ERC20(asset).allowance(address(this), spender) == 0) {
            ERC20(asset).safeApprove(spender, type(uint256).max);
        }
    }
}

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

// The following swapper contract only has educational purpose. It simulates a contract allowing to swap a token against
// another, with the exact price returned by an arbitrary oracle.

// The introduction of the swapper contract is to showcase the functioning of the callbacks on Morpho Blue without
// highlighting any known DEX.

// Therefore, swapper must be replaced (by the swap of your choice) in your implementation. The functions
// `swapCollatToLoan` and `swapLoanToCollat` must as well be adapted to match the ones of the chosen swap contract.

// One should be aware that has to be taken into account on potential swap:
//    1. slippage,
//    2. fees.

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

    /// @notice Create a leveraged position with a given `leverageFactor` on the `marketParams` market of Morpho Blue
    /// for the sendder.
    /// @dev The sender needs to hold `initAmountCollateral`, and to approve this contract to manage his positions on
    /// Morpho Blue.
    /// @param leverageFactor The factor of leverage wanted. can't be higher than 1/1-LLTV.
    /// @param initAmountCollateral The initial amount of collateral owned by the sender.
    /// @param marketParams The market to perform the leverage on.
    function leverageMe(uint256 leverageFactor, uint256 initAmountCollateral, MarketParams calldata marketParams)
        public
    {
        ERC20(marketParams.collateralToken).safeTransferFrom(msg.sender, address(this), initAmountCollateral);

        uint256 finalAmountcollateral = initAmountCollateral * leverageFactor;

        // The amount of LoanToken to be borrowed (and then swapped against collateralToken) to perform the callback is
        // the following :

        // (leverageFactor - 1) * InitAmountCollateral.mulDivDown.(ORACLE_PRICE_SCALE, IOracle(oracle).price())

        // However in this simple example we have price = `ORACLE_PRICE_SCALE`, so loanAmount = (leverageFactor - 1) *
        // InitAmountCollateral

        // Warning : When using real swaps, price doesn't necessarily equal `ORACLE_PRICE_SCALE` anymore, so
        // mulDivDown.(ORACLE_PRICE_SCALE, IOracle(oracle).price()) can't be removed from the calculus, and therefore an
        // oracle should be used to compute the correct amount.
        // Warning : When using real swaps, fees and slippage should also be taken into account to compute `loanAmount`.

        uint256 loanAmount = (leverageFactor - 1) * initAmountCollateral;

        _approveMaxTo(marketParams.collateralToken, address(morpho));

        morpho.supplyCollateral(
            marketParams,
            finalAmountcollateral,
            msg.sender,
            abi.encode(SupplyCollateralData(loanAmount, marketParams, msg.sender))
        );
    }

    /// @notice Create a deleverages the sender on the given `marketParams` market of Morpho Blue by repaying his debt
    /// and withdrawing his collateral. The withdrawn assets are sent to the sender.
    /// @dev If the sender has a leveraged position on `marketParams`, he doesn't need any tokens to perform this
    /// operation.
    /// @param marketParams The market to perform the leverage on.
    function deLeverageMe(MarketParams calldata marketParams) public returns (uint256 amountRepayed) {
        uint256 totalShares = morpho.borrowShares(marketParams.id(), msg.sender);

        _approveMaxTo(marketParams.loanToken, address(morpho));

        (amountRepayed,) =
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

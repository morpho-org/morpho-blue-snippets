// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

// import {SwapMock} from "@snippets/blue/mocks/SwapMock.sol";
import {
    IMorphoSupplyCollateralCallback,
    IMorphoLiquidateCallback,
    IMorphoRepayCallback
} from "@morpho-blue/interfaces/IMorphoCallbacks.sol";

import {Id, IMorpho, MarketParams, Market} from "@morpho-blue/interfaces/IMorpho.sol";
import {SafeTransferLib, ERC20} from "@solmate/utils/SafeTransferLib.sol";
import {MathLib} from "@morpho-blue/libraries/MathLib.sol";
import {MorphoLib} from "@morpho-blue/libraries/periphery/MorphoLib.sol";
import {MarketParamsLib} from "@morpho-blue/libraries/MarketParamsLib.sol";

import {ISwap} from "@snippets/blue/interfaces/ISwap.sol";
/*
The following swapper contract only has educational purpose. It simulates a contract allowing to swap a token against
another, with the exact price returned by an arbitrary oracle.

The introduction of the swapper contract is to showcase the functioning of leverage on Morpho Blue (using callbacks)
without highlighting any known DEX.

Therefore, swapper must be replaced (by the swap of your choice) in your implementation. The functions
`swapCollatToLoan` and `swapLoanToCollat` must as well be adapted to match the ones of the chosen swap contract.
    
One should be aware that has to be taken into account on potential swap:
    1. slippage
    2. fees

TODOS: add a definition of what snippets are useful for
    */

contract CallbacksSnippets is IMorphoSupplyCollateralCallback, IMorphoRepayCallback, IMorphoLiquidateCallback {
    using MathLib for uint256;
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

    /* 
    
    Callbacks

    Reminder: for a given market, one can leverage his position up to a leverageFactor = 1/1-LLTV,
    
    Example : with a LLTV of 80% -> 5 is the max leverage factor
    
    */

    function onMorphoSupplyCollateral(uint256 amount, bytes calldata data) external onlyMorpho {
        (uint256 toBorrow, MarketParams memory marketParams, address user) =
            abi.decode(data, (uint256, MarketParams, address));
        (uint256 amountBis,) = morpho.borrow(marketParams, toBorrow, 0, user, address(this));

        ERC20(marketParams.loanToken).approve(address(swapper), amount);

        // Logic to Implement. Following example is a swap, could be a 'unwrap + stake + wrap staked' for
        // wETH(wstETH) Market
        // _approveMaxTo(marketParams.);
        swapper.swapLoanToCollat(amountBis);
    }

    function onMorphoLiquidate(uint256 repaidAssets, bytes calldata data) external onlyMorpho {
        (uint256 toSwap, MarketParams memory marketParams) = abi.decode(data, (uint256, MarketParams));
        uint256 returnedAmount = swapper.swapCollatToLoan(toSwap);
        require(returnedAmount > repaidAssets); // Add logic for gas cost threshold for instance
        ERC20(marketParams.loanToken).approve(address(swapper), returnedAmount);
    }

    function onMorphoRepay(uint256 amount, bytes calldata data) external onlyMorpho {
        (MarketParams memory marketParams, address user) = abi.decode(data, (MarketParams, address));
        uint256 toWithdraw = morpho.collateral(marketParams.id(), user);

        morpho.withdrawCollateral(marketParams, toWithdraw, user, address(this));

        ERC20(marketParams.collateralToken).approve(address(swapper), amount);
        swapper.swapCollatToLoan(amount);
    }

    function leverageMe(uint256 leverageFactor, uint256 initAmountCollateral, MarketParams calldata marketParams)
        public
    {
        ERC20(marketParams.collateralToken).safeTransferFrom(msg.sender, address(this), initAmountCollateral);

        uint256 finalAmountcollateral = initAmountCollateral * leverageFactor;

        // The amount of LoanToken to be borrowed (and then swapped against collateralToken) to perform the callback is
        // the following :

        // (leverageFactor - 1) * InitAmountCollateral.mulDivDown.(ORACLE_PRICE_SCALE, IOracle(oracle).price())

        // However here we have price = `ORACLE_PRICE_SCALE`, so loanAmount = (leverageFactor - 1) *
        // InitAmountCollateral

        // Warning : When using real swaps, price doesn't equal `ORACLE_PRICE_SCALE` anymore, so
        // mulDivDown.(ORACLE_PRICE_SCALE, IOracle(oracle).price()) can't be removed from the calculus, and therefore an
        // oracle should be used to compute the correct amount.
        // Warning : When using real swaps, fees and slippage should also be taken into account to compute `loanAmount`.

        uint256 loanAmount = (leverageFactor - 1) * initAmountCollateral;

        _approveMaxTo(marketParams.collateralToken, address(morpho));

        morpho.supplyCollateral(
            marketParams, finalAmountcollateral, msg.sender, abi.encode(loanAmount, marketParams, msg.sender)
        );
    }

    function liquidateWithoutCollat(
        address borrower,
        uint256 loanAmountToRepay,
        uint256 assetsToSeize,
        MarketParams calldata marketParams
    ) public returns (uint256 seizedAssets, uint256 repaidAssets) {
        _approveMaxTo(address(marketParams.collateralToken), address(this));

        uint256 repaidShares;

        (seizedAssets, repaidAssets) =
            morpho.liquidate(marketParams, borrower, assetsToSeize, repaidShares, abi.encode(loanAmountToRepay));
    }

    function deLeverageMe(MarketParams calldata marketParams) public returns (uint256 amountRepayed) {
        uint256 totalShares = morpho.borrowShares(marketParams.id(), msg.sender);

        _approveMaxTo(marketParams.loanToken, address(morpho));

        (amountRepayed,) = morpho.repay(marketParams, 0, totalShares, msg.sender, abi.encode(marketParams, msg.sender));

        ERC20(marketParams.collateralToken).safeTransfer(
            msg.sender, ERC20(marketParams.collateralToken).balanceOf(msg.sender)
        );
    }

    function _approveMaxTo(address asset, address spender) internal {
        if (ERC20(asset).allowance(address(this), spender) == 0) {
            ERC20(asset).approve(spender, type(uint256).max);
        }
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {SwapMock} from "@snippets/blue/mocks/SwapMock.sol";
import {
    IMorphoSupplyCollateralCallback,
    IMorphoLiquidateCallback,
    IMorphoRepayCallback
} from "@morpho-blue/interfaces/IMorphoCallbacks.sol";

import {Id, IMorpho, MarketParams, Market} from "@morpho-blue/interfaces/IMorpho.sol";
import {SafeTransferLib, ERC20} from "@solmate/utils/SafeTransferLib.sol";
import {MathLib} from "@morpho-blue/libraries/MathLib.sol";
import {MorphoLib} from "@morpho-blue/libraries/periphery/MorphoLib.sol";
import {MorphoBalancesLib} from "@morpho-blue/libraries/periphery/MorphoBalancesLib.sol";
import {MarketParamsLib} from "@morpho-blue/libraries/MarketParamsLib.sol";

/*
    The following implementation regarding the swap mocked has been done for educationnal purpose
    the swap mock is giving back, thanks to the orace of the market, the exact value in terms of amount between a
    collateral and a loan token
    
    One should be aware that has to be taken into account on potential swap:
     1. slippage
     2. fees


     add a definition of what snippets are
    */
contract CallbacksSnippets is IMorphoSupplyCollateralCallback, IMorphoRepayCallback, IMorphoLiquidateCallback {
    using MathLib for uint256;
    using MorphoLib for IMorpho;
    using MarketParamsLib for MarketParams;

    IMorpho public immutable morpho;
    SwapMock swapMock;

    constructor(address morphoAddress) {
        morpho = IMorpho(morphoAddress);
    }

    /* 
    
    Callbacks
    remember that at a given market, one can leverage itself up to 1/1-LLTV,
    leverageFactor so for an LLTV of 80% -> 5 is the max leverage factor
    loanLeverageFactor max loanLeverageFactor would have to be on LLTV * leverageFactor to be safe
    
    */

    function onMorphoSupplyCollateral(uint256 amount, bytes calldata data) external {
        require(msg.sender == address(morpho));
        (bytes4 selector, bytes memory _data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.leverageMe.selector) {
            (uint256 toBorrow, MarketParams memory marketParams) = abi.decode(_data, (uint256, MarketParams));
            (uint256 amountBis,) = morpho.borrow(marketParams, toBorrow, 0, address(this), address(this));
            ERC20(marketParams.collateralToken).approve(address(swapMock), amount);

            // Logic to Implement. Following example is a swap, could be a 'unwrap + stake + wrap staked' for
            // wETH(wstETH) Market
            swapMock.swapLoanToCollat(amountBis);
        }
    }

    function onMorphoLiquidate(uint256 repaidAssets, bytes calldata data) external onlyMorpho {
        require(msg.sender == address(morpho));
        (bytes4 selector, bytes memory _data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.liquidateWithoutCollat.selector) {
            (uint256 toSwap, MarketParams memory marketParams) = abi.decode(_data, (uint256, MarketParams));
            uint256 returnedAmount = swapMock.swapCollatToLoan(toSwap);
            require(returnedAmount > repaidAssets); // Add logic for gas cost threshold for instance
            ERC20(marketParams.loanToken).approve(address(swapMock), returnedAmount);
        }
    }

    function onMorphoRepay(uint256 amount, bytes calldata data) external {
        require(msg.sender == address(morpho));
        (bytes4 selector, bytes memory _data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.deLeverageMe.selector) {
            (uint256 toWithdraw, MarketParams memory marketParams) = abi.decode(_data, (uint256, MarketParams));
            morpho.withdrawCollateral(marketParams, toWithdraw, address(this), address(this));

            ERC20(marketParams.loanToken).approve(address(morpho), amount);
            swapMock.swapCollatToLoan(toWithdraw);
        }
    }

    function leverageMe(
        uint256 leverageFactor,
        uint256 loanLeverageFactor,
        uint256 collateralInitAmount,
        SwapMock _swapMock,
        MarketParams calldata marketParams
    ) public {
        _setSwapMock(_swapMock);

        uint256 collateralAssets = collateralInitAmount * leverageFactor;
        uint256 loanAmount = collateralInitAmount * loanLeverageFactor;

        _approveMaxTo(address(marketParams.collateralToken), address(this));

        morpho.supplyCollateral(
            marketParams,
            collateralAssets,
            address(this),
            abi.encode(this.leverageMe.selector, abi.encode(loanAmount, marketParams))
        );
    }

    function liquidateWithoutCollat(
        address borrower,
        uint256 loanAmountToRepay,
        uint256 assetsToSeize,
        SwapMock _swapMock,
        MarketParams calldata marketParams
    ) public returns (uint256 seizedAssets, uint256 repaidAssets) {
        _setSwapMock(_swapMock);

        _approveMaxTo(address(marketParams.collateralToken), address(this));

        uint256 repaidShares = 0;

        (seizedAssets, repaidAssets) = morpho.liquidate(
            marketParams,
            borrower,
            assetsToSeize,
            repaidShares,
            abi.encode(this.liquidateWithoutCollat.selector, abi.encode(loanAmountToRepay))
        );
    }

    function deLeverageMe(
        uint256 leverageFactor,
        uint256 loanLeverageFactor,
        uint256 collateralInitAmount,
        SwapMock _swapMock,
        MarketParams calldata marketParams
    ) public returns (uint256 amountRepayed) {
        _setSwapMock(_swapMock);

        uint256 collateralAssets = collateralInitAmount * leverageFactor;
        uint256 loanAmount = collateralInitAmount * loanLeverageFactor;

        _approveMaxTo(address(marketParams.collateralToken), address(this));

        (amountRepayed,) = morpho.repay(
            marketParams,
            loanAmount,
            0,
            address(this),
            abi.encode(this.deLeverageMe.selector, abi.encode(collateralAssets, marketParams))
        );
    }

    modifier onlyMorpho() {
        require(msg.sender == address(morpho), "msg.sender should be Morpho Blue");
        _;
    }

    function _approveMaxTo(address asset, address spender) internal {
        if (ERC20(asset).allowance(address(this), spender) == 0) {
            ERC20(asset).approve(spender, type(uint256).max);
        }
    }

    function _setSwapMock(SwapMock _swapMock) public {
        swapMock = _swapMock;
    }
}

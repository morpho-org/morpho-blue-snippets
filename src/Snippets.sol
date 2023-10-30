// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Id, IMorpho, MarketParams, Market} from "@morpho-blue/interfaces/IMorpho.sol";
import {IERC20} from "@morpho-blue/interfaces/IERC20.sol";
import {IIrm} from "@morpho-blue/interfaces/IIrm.sol";
import {IOracle} from "@morpho-blue/interfaces/IOracle.sol";

import {MorphoBalancesLib} from "@morpho-blue/libraries/periphery/MorphoBalancesLib.sol";
import {MarketParamsLib} from "@morpho-blue/libraries/MarketParamsLib.sol";
import {MorphoLib} from "@morpho-blue/libraries/periphery/MorphoLib.sol";
import {MathLib} from "@morpho-blue/libraries/MathLib.sol";
import {SharesMathLib} from "@morpho-blue/libraries/SharesMathLib.sol";
import {ORACLE_PRICE_SCALE} from "@morpho-blue/libraries/ConstantsLib.sol";

contract Snippets {
    using MathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;
    IMorpho public immutable morpho;

    constructor(address morphoAddress) {
        morpho = IMorpho(morphoAddress);
    }

    // INFORMATIONAL: No 'Total Supply' and no 'Total Borrow' functions to calculate on chain as there could be some weird oracles / markets created

    // ---- VIEW FUNCTIONS ----

    // OK - view function?
    function supplyAPR(
        MarketParams memory marketParams,
        Market memory market
    ) public returns (uint256 supplyRate) {
        (uint256 totalSupplyAssets, , uint256 totalBorrowAssets, ) = morpho
            .expectedMarketBalances(marketParams);

        // Get the borrow rate
        uint256 borrowRate = IIrm(marketParams.irm).borrowRate(
            marketParams,
            market
        );

        // Get the supply rate
        uint256 utilization = totalBorrowAssets == 0
            ? 0
            : totalBorrowAssets.wDivUp(totalSupplyAssets);

        supplyRate = borrowRate.wMulDown(1 ether - market.fee).wMulDown(
            utilization
        );
    }

    // OK - view function?
    function borrowAPR(
        MarketParams memory marketParams,
        Market memory market
    ) public returns (uint256 borrowRate) {
        borrowRate = IIrm(marketParams.irm).borrowRate(marketParams, market);
    }

    // OK
    function supplyBalance(
        MarketParams memory marketParams,
        address user
    ) public view returns (uint256 totalSupplyBalance) {
        totalSupplyBalance = morpho.expectedSupplyBalance(marketParams, user);
    }

    // OK
    function borrowBalance(
        MarketParams memory marketParams,
        address user
    ) public view returns (uint256 totalBorrowBalance) {
        totalBorrowBalance = morpho.expectedBorrowBalance(marketParams, user);
    }

    // OK
    function collateralBalance(
        Id marketId,
        address user
    ) public view returns (uint256 totalCollateralBalance) {
        (, , totalCollateralBalance) = morpho.position(marketId, user);
    }

    // OK
    function marketTotalSupply(
        MarketParams memory marketParams
    ) public view returns (uint256 totalSupplyAssets) {
        totalSupplyAssets = morpho.expectedTotalSupply(marketParams);
    }

    // OK
    function marketTotalBorrow(
        MarketParams memory marketParams
    ) public view returns (uint256 totalBorrowAssets) {
        totalBorrowAssets = morpho.expectedTotalBorrow(marketParams);
    }

    // OK
    function userHealthFactor(
        MarketParams memory marketParams,
        Id id,
        address user
    ) public view returns (uint256 healthFactor) {
        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        uint256 collateral = morpho.collateral(id, user);
        uint256 borrowed = morpho.expectedBorrowBalance(marketParams, user);

        uint256 collateralNormalized = collateral
            .mulDivDown(collateralPrice, ORACLE_PRICE_SCALE)
            .wMulDown(marketParams.lltv);
        healthFactor = collateralNormalized.wMulDown(borrowed);
    }
}

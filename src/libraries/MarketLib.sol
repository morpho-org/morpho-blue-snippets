// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

// import {MarketParams} from "@morpho-blue/libraries/MarketParamsLib.sol";

// import {MathLib} from "@morpho-blue/libraries/MathLib.sol";

// /// @title MarketLib
// /// @author Morpho Labs
// /// @custom:contact security@morpho.xyz
// /// @notice Library used to ease market reads and writes.
// library MarketLib {
//     using MathLib for uint256;

//     /// @notice Returns whether the `market` is created or not.
//     function isCreated(
//         Types.Market memory market
//     ) internal pure returns (bool) {
//         return market.aToken != address(0);
//     }

//     /// @notice Returns whether supply is paused on `market` or not.
//     function isSupplyPaused(
//         Types.Market memory market
//     ) internal pure returns (bool) {
//         return market.pauseStatuses.isSupplyPaused;
//     }

//     /// @notice Returns whether supply collateral is paused on `market` or not.
//     function isSupplyCollateralPaused(
//         Types.Market memory market
//     ) internal pure returns (bool) {
//         return market.pauseStatuses.isSupplyCollateralPaused;
//     }

//     /// @notice Returns whether borrow is paused on `market` or not.
//     function isBorrowPaused(
//         Types.Market memory market
//     ) internal pure returns (bool) {
//         return market.pauseStatuses.isBorrowPaused;
//     }

//     /// @notice Returns whether repay is paused on `market` or not.
//     function isRepayPaused(
//         Types.Market memory market
//     ) internal pure returns (bool) {
//         return market.pauseStatuses.isRepayPaused;
//     }

//     /// @notice Returns whether withdraw is paused on `market` or not.
//     function isWithdrawPaused(
//         Types.Market memory market
//     ) internal pure returns (bool) {
//         return market.pauseStatuses.isWithdrawPaused;
//     }

//     /// @notice Returns whether withdraw collateral is paused on `market` or not.
//     function isWithdrawCollateralPaused(
//         Types.Market memory market
//     ) internal pure returns (bool) {
//         return market.pauseStatuses.isWithdrawCollateralPaused;
//     }

//     /// @notice Returns whether liquidate collateral is paused on `market` or not.
//     function isLiquidateCollateralPaused(
//         Types.Market memory market
//     ) internal pure returns (bool) {
//         return market.pauseStatuses.isLiquidateCollateralPaused;
//     }

//     /// @notice Returns whether liquidate borrow is paused on `market` or not.
//     function isLiquidateBorrowPaused(
//         Types.Market memory market
//     ) internal pure returns (bool) {
//         return market.pauseStatuses.isLiquidateBorrowPaused;
//     }

//     /// @notice Returns whether the `market` is deprecated or not.
//     function isDeprecated(
//         Types.Market memory market
//     ) internal pure returns (bool) {
//         return market.pauseStatuses.isDeprecated;
//     }

//     /// @notice Returns whether the peer-to-peer is disabled on `market` or not.
//     function isP2PDisabled(
//         Types.Market memory market
//     ) internal pure returns (bool) {
//         return market.pauseStatuses.isP2PDisabled;
//     }

//     /// @notice Returns the supply indexes of `market`.
//     function getSupplyIndexes(
//         Types.Market memory market
//     ) internal pure returns (Types.MarketSideIndexes256 memory supplyIndexes) {
//         supplyIndexes.poolIndex = uint256(market.indexes.supply.poolIndex);
//         supplyIndexes.p2pIndex = uint256(market.indexes.supply.p2pIndex);
//     }

//     /// @notice Returns the borrow indexes of `market`.
//     function getBorrowIndexes(
//         Types.Market memory market
//     ) internal pure returns (Types.MarketSideIndexes256 memory borrowIndexes) {
//         borrowIndexes.poolIndex = uint256(market.indexes.borrow.poolIndex);
//         borrowIndexes.p2pIndex = uint256(market.indexes.borrow.p2pIndex);
//     }

//     /// @notice Returns the indexes of `market`.
//     function getIndexes(
//         Types.Market memory market
//     ) internal pure returns (Types.Indexes256 memory indexes) {
//         indexes.supply = getSupplyIndexes(market);
//         indexes.borrow = getBorrowIndexes(market);
//     }

//     /// @notice Returns the proportion of idle supply in `market` over the total peer-to-peer amount in supply.
//     function proportionIdle(
//         Types.Market memory market
//     ) internal pure returns (uint256) {
//         uint256 idleSupply = market.idleSupply;
//         if (idleSupply == 0) return 0;

//         uint256 totalP2PSupplied = market.deltas.supply.scaledP2PTotal.rayMul(
//             market.indexes.supply.p2pIndex
//         );

//         // We take the minimum to handle the case where the proportion is rounded to greater than 1.
//         return Math.min(idleSupply.rayDivUp(totalP2PSupplied), WadRayMath.RAY);
//     }

//     /// @notice Calculates the total quantity of underlyings truly supplied peer-to-peer on the given market.
//     /// @param indexes The current indexes.
//     /// @return The total peer-to-peer supply (total peer-to-peer supply - supply delta - idle supply).
//     function trueP2PSupply(
//         Types.Market memory market,
//         Types.Indexes256 memory indexes
//     ) internal pure returns (uint256) {
//         Types.MarketSideDelta memory supplyDelta = market.deltas.supply;
//         return
//             supplyDelta
//                 .scaledP2PTotal
//                 .rayMul(indexes.supply.p2pIndex)
//                 .zeroFloorSub(
//                     supplyDelta.scaledDelta.rayMul(indexes.supply.poolIndex)
//                 )
//                 .zeroFloorSub(market.idleSupply);
//     }

//     /// @notice Calculates the total quantity of underlyings truly borrowed peer-to-peer on the given market.
//     /// @param indexes The current indexes.
//     /// @return The total peer-to-peer borrow (total peer-to-peer borrow - borrow delta).
//     function trueP2PBorrow(
//         Types.Market memory market,
//         Types.Indexes256 memory indexes
//     ) internal pure returns (uint256) {
//         Types.MarketSideDelta memory borrowDelta = market.deltas.borrow;
//         return
//             borrowDelta
//                 .scaledP2PTotal
//                 .rayMul(indexes.borrow.p2pIndex)
//                 .zeroFloorSub(
//                     borrowDelta.scaledDelta.rayMul(indexes.borrow.poolIndex)
//                 );
//     }
// }

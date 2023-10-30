// // SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

// // import {Constants} from "@morpho-blue/libraries/ConstantsLib.sol";

// import {MathLib} from "@morpho-blue/libraries/MathLib.sol";
// // import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";
// // import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";
// // import {collateralValue, rawCollateralValue} from "test/helpers/Utils.sol";

// // import {ERC20} from "@solmate/tokens/ERC20.sol";

// struct TestMarketParams {
//     address loanTokenAddress;
//     address collateralTokenAddress;
//     address oracleTokenAddress;
//     address irmTokenAddress;
//     uint256 lltv;
// }

// struct TestMarketDetails {
//     uint128 totalSupplyAssets;
//     uint128 totalSupplyShares;
//     uint128 totalBorrowAssets;
//     uint128 totalBorrowShares;
//     uint128 lastUpdate;
//     uint128 fee;
// }

// struct TestPosition {
//     uint256 supplyShares;
//     uint128 borrowShares;
//     uint128 collateral;
// }

// library TestMarketLib {
//     using MathLib for uint256;

//     // using PercentageMath for uint256;

//     /// @dev Returns the quantity that can be borrowed/withdrawn from the market.
//     function liquidity(
//         TestMarket storage market
//     ) internal view returns (uint256) {
//         return ERC20(market.underlying).balanceOf(market.aToken);
//     }

//     /// @dev Returns the quantity currently supplied on the market on AaveV3.
//     function totalSupply(
//         TestMarket storage market
//     ) internal view returns (uint256) {
//         return ERC20(market.aToken).totalSupply();
//     }

//     /// @dev Returns the quantity currently borrowed (with variable & stable rates) on the market on AaveV3.
//     function totalBorrow(
//         TestMarket storage market
//     ) internal view returns (uint256) {
//         return totalVariableBorrow(market) + totalStableBorrow(market);
//     }

//     /// @dev Returns the quantity currently borrowed with variable rate from the market on AaveV3.
//     function totalVariableBorrow(
//         TestMarket storage market
//     ) internal view returns (uint256) {
//         return ERC20(market.variableDebtToken).totalSupply();
//     }

//     /// @dev Returns the quantity currently borrowed with stable rate from the market on AaveV3.
//     function totalStableBorrow(
//         TestMarket storage market
//     ) internal view returns (uint256) {
//         return ERC20(market.stableDebtToken).totalSupply();
//     }

//     /// @dev Returns the quantity currently supplied on behalf of the user, on the market on AaveV3.
//     function supplyOf(
//         TestMarket storage market,
//         address user
//     ) internal view returns (uint256) {
//         return ERC20(market.aToken).balanceOf(user);
//     }

//     /// @dev Returns the quantity currently borrowed on behalf of the user, with variable rate, on the market on AaveV3.
//     function variableBorrowOf(
//         TestMarket storage market,
//         address user
//     ) internal view returns (uint256) {
//         return ERC20(market.variableDebtToken).balanceOf(user);
//     }

//     /// @dev Returns the quantity currently borrowed on behalf of the user, with stable rate, on the market on AaveV3.
//     function stableBorrowOf(
//         TestMarket storage market,
//         address user
//     ) internal view returns (uint256) {
//         return ERC20(market.stableDebtToken).balanceOf(user);
//     }

//     /// @dev Calculates the underlying amount that can be supplied on the given market on AaveV3, reaching the borrow cap.
//     function borrowGap(
//         TestMarket storage market
//     ) internal view returns (uint256) {
//         return market.borrowCap.zeroFloorSub(totalBorrow(market));
//     }

//     /// @dev Quotes the given amount of base tokens as quote tokens.
//     function quote(
//         TestMarket storage quoteMarket,
//         TestMarket storage baseMarket,
//         uint256 amount
//     ) internal view returns (uint256) {
//         return
//             (amount * baseMarket.price * 10 ** quoteMarket.decimals) /
//             (quoteMarket.price * 10 ** baseMarket.decimals);
//     }

//     function getLtv(
//         TestMarket storage collateralMarket,
//         uint8 eModeCategoryId
//     ) internal view returns (uint256) {
//         return
//             eModeCategoryId != 0 &&
//                 eModeCategoryId == collateralMarket.eModeCategoryId
//                 ? collateralMarket.eModeCategory.ltv
//                 : collateralMarket.ltv;
//     }

//     function getLt(
//         TestMarket storage collateralMarket,
//         uint8 eModeCategoryId
//     ) internal view returns (uint256) {
//         uint256 ltv = getLtv(collateralMarket, eModeCategoryId);
//         if (ltv == 0) return 0;

//         return
//             eModeCategoryId != 0 &&
//                 eModeCategoryId == collateralMarket.eModeCategoryId
//                 ? collateralMarket.eModeCategory.liquidationThreshold
//                 : collateralMarket.lt;
//     }

//     /// @dev Calculates the maximum borrowable quantity collateralized by the given quantity of collateral.
//     function borrowable(
//         TestMarket storage borrowedMarket,
//         TestMarket storage collateralMarket,
//         uint256 rawCollateral,
//         uint8 eModeCategoryId
//     ) internal view returns (uint256) {
//         uint256 ltv = getLtv(collateralMarket, eModeCategoryId);

//         return
//             quote(
//                 borrowedMarket,
//                 collateralMarket,
//                 collateralValue(rawCollateral)
//             ).percentMul(ltv - 10);
//         // The borrowable quantity is under-estimated because of decimals precision (especially for the pair WBTC/WETH).
//     }

//     /// @dev Calculates the maximum borrowable quantity collateralized by the given quantity of collateral.
//     function collateralized(
//         TestMarket storage borrowedMarket,
//         TestMarket storage collateralMarket,
//         uint256 rawCollateral,
//         uint8 eModeCategoryId
//     ) internal view returns (uint256) {
//         uint256 lt = getLt(collateralMarket, eModeCategoryId);

//         return
//             quote(
//                 borrowedMarket,
//                 collateralMarket,
//                 collateralValue(rawCollateral)
//             ).percentMul(lt - 10);
//         // The collateralized quantity is under-estimated because of decimals precision (especially for the pair WBTC/WETH).
//     }

//     /// @dev Calculates the minimum collateral quantity necessary to collateralize the given quantity of debt while still being able to borrow.
//     function minBorrowCollateral(
//         TestMarket storage collateralMarket,
//         TestMarket storage borrowedMarket,
//         uint256 amount,
//         uint8 eModeCategoryId
//     ) internal view returns (uint256) {
//         uint256 ltv = getLtv(collateralMarket, eModeCategoryId);

//         return
//             rawCollateralValue(
//                 quote(collateralMarket, borrowedMarket, amount).percentDiv(
//                     // The quantity of collateral required to open a borrow is over-estimated because of decimals precision (especially for the pair WBTC/WETH).
//                     ltv - 10
//                 )
//             );
//     }

//     /// @dev Calculates the minimum collateral quantity necessary to collateralize the given quantity of debt,
//     ///      without necessarily being able to borrow more.
//     function minCollateral(
//         TestMarket storage collateralMarket,
//         TestMarket storage borrowedMarket,
//         uint256 amount,
//         uint8 eModeCategoryId
//     ) internal view returns (uint256) {
//         uint256 lt = getLt(collateralMarket, eModeCategoryId);

//         return
//             rawCollateralValue(
//                 quote(collateralMarket, borrowedMarket, amount).percentDiv(lt)
//             );
//     }
// }

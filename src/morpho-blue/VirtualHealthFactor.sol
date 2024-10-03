// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Id, IMorpho, MarketParams} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IOracle} from "../../lib/morpho-blue/src/interfaces/IOracle.sol";

import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {MorphoLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoLib.sol";
import {MathLib} from "../../lib/morpho-blue/src/libraries/MathLib.sol";

import {ORACLE_PRICE_SCALE} from "../../lib/morpho-blue/src/libraries/ConstantsLib.sol";

/// @title Morpho Blue Snippets
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice The Virtual Health Factor Snippets contract.
contract VirtualHealthFactorSnippets {
    using MathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;

    /* IMMUTABLES */

    IMorpho public immutable morpho;

    /* CONSTRUCTOR */

    /// @notice Constructs the contract.
    /// @param morphoAddress The address of the Morpho Blue contract.
    constructor(address morphoAddress) {
        require(morphoAddress != address(0), "Invalid Morpho address");
        morpho = IMorpho(morphoAddress);
    }

    /*  VIEW FUNCTIONS */

    /// @notice Calculates the health factor of a user in a specific market.
    /// @param marketParams The parameters of the market.
    /// @param id The identifier of the market.
    /// @param user The address of the user whose health factor is being calculated.
    /// @return healthFactor The calculated health factor.
    function userHealthFactor(MarketParams memory marketParams, Id id, address user)
        public
        view
        returns (uint256)
    {
        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        uint256 collateral = morpho.collateral(id, user);
        uint256 borrowed = morpho.expectedBorrowAssets(marketParams, user);

        uint256 maxBorrow = collateral.mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(marketParams.lltv);

        if (borrowed == 0) return type(uint256).max;
        healthFactor = maxBorrow.wDivDown(borrowed);
    }

    /// @notice Calculates the health factor of a user after a virtual repayment.
    /// @param marketParams The parameters of the market.
    /// @param id The identifier of the market.
    /// @param user The address of the user whose health factor is being calculated.
    /// @param repaymentAmount The amount of assets to be virtually repaid.
    /// @return healthFactor The calculated health factor after the virtual repayment.
    function userHypotheticalHealthFactor(
        MarketParams memory marketParams,
        Id id,
        address user,
        uint256 repaymentAmount
    ) public view returns (uint256) {
        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        uint256 collateral = morpho.collateral(id, user);
        uint256 borrowed = morpho.expectedBorrowAssets(marketParams, user);

        // Revert if repaymentAmount exceeds the borrowed amount
        require(repaymentAmount <= borrowed, "Repayment amount exceeds borrowed amount");

        uint256 newBorrowed = borrowed - repaymentAmount;
        uint256 maxBorrow = collateral.mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(marketParams.lltv);

        return newBorrowed == 0 ? type(uint256).max : maxBorrow.wDivDown(newBorrowed);
    }

    /// @notice Calculates the health factor of a user after a virtual borrow.
    /// @param marketParams The parameters of the market.
    /// @param id The identifier of the market.
    /// @param user The address of the user whose health factor is being calculated.
    /// @param borrowAmount The amount of assets to be virtually borrowed.
    /// @return healthFactor The calculated health factor after the virtual borrow.
    function userHealthFactorAfterVirtualBorrow(
        MarketParams memory marketParams,
        Id id,
        address user,
        uint256 borrowAmount
    ) public view returns (uint256 healthFactor) {
        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        uint256 collateral = morpho.collateral(id, user);
        uint256 borrowed = morpho.expectedBorrowAssets(marketParams, user);

        uint256 newBorrowed = borrowed + borrowAmount;

        uint256 maxBorrow = collateral.mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(marketParams.lltv);

        return newBorrowed == 0 ? type(uint256).max : maxBorrow.wDivDown(newBorrowed);
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Id, IMorpho, MarketParams, Market} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IERC20} from "../../lib/morpho-blue/src/interfaces/IERC20.sol";
import {IIrm} from "../../lib/morpho-blue/src/interfaces/IIrm.sol";
import {IOracle} from "../../lib/morpho-blue/src/interfaces/IOracle.sol";

import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {MorphoLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoLib.sol";
import {MorphoStorageLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoStorageLib.sol";
import {MathLib} from "../../lib/morpho-blue/src/libraries/MathLib.sol";

import {SharesMathLib} from "../../lib/morpho-blue/src/libraries/SharesMathLib.sol";

import {ORACLE_PRICE_SCALE} from "../../lib/morpho-blue/src/libraries/ConstantsLib.sol";

/// @title Snippets
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice The Morpho Snippets contract.
contract MorphoBlueSnippets {
    using MathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using SafeERC20 for ERC20;
    using SharesMathLib for uint256;

    /* IMMUTABLES */

    IMorpho public immutable morpho;

    /* CONSTRUCTOR */

    /// @notice Constructs the contract.
    /// @param morphoAddress The address of the Morpho Blue contract.
    constructor(address morphoAddress) {
        morpho = IMorpho(morphoAddress);
    }

    /*  VIEW FUNCTIONS */

    /// @notice Calculates the supply APY (Annual Percentage Yield) for a given market.
    /// @param marketParams The parameters of the market.
    /// @param market The market for which the supply APY is being calculated.
    /// @return supplyRate The calculated supply APY (scaled by WAD).
    function supplyAPY(MarketParams memory marketParams, Market memory market)
        public
        view
        returns (uint256 supplyRate)
    {
        (uint256 totalSupplyAssets,, uint256 totalBorrowAssets,) = morpho.expectedMarketBalances(marketParams);

        // Get the borrow rate
        if (marketParams.irm != address(0)) {
            uint256 borrowRate = IIrm(marketParams.irm).borrowRateView(marketParams, market);
            uint256 utilization = totalBorrowAssets == 0 ? 0 : totalBorrowAssets.wDivUp(totalSupplyAssets);
            supplyRate = borrowRate.wMulDown(1 ether - market.fee).wMulDown(utilization).wTaylorCompounded(365 days);
        }
    }

    /// @notice Calculates the borrow APY (Annual Percentage Yield) for a given market.
    /// @param marketParams The parameters of the market.
    /// @param market The market for which the borrow APY is being calculated.
    /// @return borrowRate The calculated borrow APY (scaled by WAD).
    function borrowAPY(MarketParams memory marketParams, Market memory market)
        public
        view
        returns (uint256 borrowRate)
    {
        if (marketParams.irm != address(0)) {
            borrowRate = IIrm(marketParams.irm).borrowRateView(marketParams, market).wTaylorCompounded(365 days);
        }
    }

    /// @notice Calculates the total supply balance of a given user in a specific market.
    /// @param marketParams The parameters of the market.
    /// @param user The address of the user whose supply balance is being calculated.
    /// @return totalSupplyAssets The calculated total supply balance.
    function supplyAssetsUser(MarketParams memory marketParams, address user)
        public
        view
        returns (uint256 totalSupplyAssets)
    {
        totalSupplyAssets = morpho.expectedSupplyAssets(marketParams, user);
    }

    /// @notice Calculates the total borrow balance of a given user in a specific market.
    /// @param marketParams The parameters of the market.
    /// @param user The address of the user whose borrow balance is being calculated.
    /// @return totalBorrowAssets The calculated total borrow balance.
    function borrowAssetsUser(MarketParams memory marketParams, address user)
        public
        view
        returns (uint256 totalBorrowAssets)
    {
        totalBorrowAssets = morpho.expectedBorrowAssets(marketParams, user);
    }

    /// @notice Calculates the total collateral balance of a given user in a specific market.
    /// @dev It uses extSloads to load only one storage slot of the Position struct and save gas.
    /// @param marketId The identifier of the market.
    /// @param user The address of the user whose collateral balance is being calculated.
    /// @return totalCollateralAssets The calculated total collateral balance.
    function collateralAssetsUser(Id marketId, address user) public view returns (uint256 totalCollateralAssets) {
        bytes32[] memory slots = new bytes32[](1);
        slots[0] = MorphoStorageLib.positionBorrowSharesAndCollateralSlot(marketId, user);
        bytes32[] memory values = morpho.extSloads(slots);
        totalCollateralAssets = uint256(values[0] >> 128);
    }

    /// @notice Calculates the total supply of assets in a specific market.
    /// @param marketParams The parameters of the market.
    /// @return totalSupplyAssets The calculated total supply of assets.
    function marketTotalSupply(MarketParams memory marketParams) public view returns (uint256 totalSupplyAssets) {
        totalSupplyAssets = morpho.expectedTotalSupplyAssets(marketParams);
    }

    /// @notice Calculates the total borrow of assets in a specific market.
    /// @param marketParams The parameters of the market.
    /// @return totalBorrowAssets The calculated total borrow of assets.
    function marketTotalBorrow(MarketParams memory marketParams) public view returns (uint256 totalBorrowAssets) {
        totalBorrowAssets = morpho.expectedTotalBorrowAssets(marketParams);
    }

    /// @notice Calculates the health factor of a user in a specific market.
    /// @param marketParams The parameters of the market.
    /// @param id The identifier of the market.
    /// @param user The address of the user whose health factor is being calculated.
    /// @return healthFactor The calculated health factor.
    function userHealthFactor(MarketParams memory marketParams, Id id, address user)
        public
        view
        returns (uint256 healthFactor)
    {
        uint256 collateralPrice = IOracle(marketParams.oracle).price();
        uint256 collateral = morpho.collateral(id, user);
        uint256 borrowed = morpho.expectedBorrowAssets(marketParams, user);

        uint256 maxBorrow = collateral.mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(marketParams.lltv);

        if (borrowed == 0) return type(uint256).max;
        healthFactor = maxBorrow.wDivDown(borrowed);
    }

    // ---- MANAGING FUNCTIONS ----

    /// @notice Handles the supply of assets by the caller to a specific market.
    /// @param marketParams The parameters of the market.
    /// @param amount The amount of assets the user is supplying.
    /// @return assetsSupplied The actual amount of assets supplied.
    /// @return sharesSupplied The shares supplied in return for the assets.
    function supply(MarketParams memory marketParams, uint256 amount)
        external
        returns (uint256 assetsSupplied, uint256 sharesSupplied)
    {
        ERC20(marketParams.loanToken).forceApprove(address(morpho), type(uint256).max);
        ERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), amount);

        uint256 shares = 0;
        address onBehalf = msg.sender;

        (assetsSupplied, sharesSupplied) = morpho.supply(marketParams, amount, shares, onBehalf, hex"");
    }

    /// @notice Handles the supply of collateral by the caller to a specific market.
    /// @param marketParams The parameters of the market.
    /// @param amount The amount of collateral the user is supplying.
    function supplyCollateral(MarketParams memory marketParams, uint256 amount) external {
        ERC20(marketParams.collateralToken).forceApprove(address(morpho), type(uint256).max);
        ERC20(marketParams.collateralToken).safeTransferFrom(msg.sender, address(this), amount);

        address onBehalf = msg.sender;

        morpho.supplyCollateral(marketParams, amount, onBehalf, hex"");
    }

    /// @notice Handles the withdrawal of collateral by the caller from a specific market of a specific amount.
    /// @param marketParams The parameters of the market.
    /// @param amount The amount of collateral the user is withdrawing.
    function withdrawCollateral(MarketParams memory marketParams, uint256 amount) external {
        address onBehalf = msg.sender;
        address receiver = msg.sender;

        morpho.withdrawCollateral(marketParams, amount, onBehalf, receiver);
    }

    /// @notice Handles the withdrawal of a specified amount of assets by the caller from a specific market.
    /// @param marketParams The parameters of the market.
    /// @param amount The amount of assets the user is withdrawing.
    /// @return assetsWithdrawn The actual amount of assets withdrawn.
    /// @return sharesWithdrawn The shares withdrawn in return for the assets.
    function withdrawAmount(MarketParams memory marketParams, uint256 amount)
        external
        returns (uint256 assetsWithdrawn, uint256 sharesWithdrawn)
    {
        uint256 shares = 0;
        address onBehalf = msg.sender;
        address receiver = msg.sender;

        (assetsWithdrawn, sharesWithdrawn) = morpho.withdraw(marketParams, amount, shares, onBehalf, receiver);
    }

    /// @notice Handles the withdrawal of 50% of the assets by the caller from a specific market.
    /// @param marketParams The parameters of the market.
    /// @return assetsWithdrawn The actual amount of assets withdrawn.
    /// @return sharesWithdrawn The shares withdrawn in return for the assets.
    function withdraw50Percent(MarketParams memory marketParams)
        external
        returns (uint256 assetsWithdrawn, uint256 sharesWithdrawn)
    {
        Id marketId = marketParams.id();
        uint256 supplyShares = morpho.position(marketId, msg.sender).supplyShares;
        uint256 amount = 0;
        uint256 shares = supplyShares / 2;

        address onBehalf = msg.sender;
        address receiver = msg.sender;

        (assetsWithdrawn, sharesWithdrawn) = morpho.withdraw(marketParams, amount, shares, onBehalf, receiver);
    }

    /// @notice Handles the withdrawal of all the assets by the caller from a specific market.
    /// @param marketParams The parameters of the market.
    /// @return assetsWithdrawn The actual amount of assets withdrawn.
    /// @return sharesWithdrawn The shares withdrawn in return for the assets.
    function withdrawAll(MarketParams memory marketParams)
        external
        returns (uint256 assetsWithdrawn, uint256 sharesWithdrawn)
    {
        Id marketId = marketParams.id();
        uint256 supplyShares = morpho.position(marketId, msg.sender).supplyShares;
        uint256 amount = 0;

        address onBehalf = msg.sender;
        address receiver = msg.sender;

        (assetsWithdrawn, sharesWithdrawn) = morpho.withdraw(marketParams, amount, supplyShares, onBehalf, receiver);
    }

    /// @notice Handles the withdrawal of a specified amount of assets by the caller from a specific market. If the
    /// amount is greater than the total amount suplied by the user, withdraws all the shares of the user.
    /// @param marketParams The parameters of the market.
    /// @param amount The amount of assets the user is withdrawing.
    /// @return assetsWithdrawn The actual amount of assets withdrawn.
    /// @return sharesWithdrawn The shares withdrawn in return for the assets.
    function withdrawAmountOrAll(MarketParams memory marketParams, uint256 amount)
        external
        returns (uint256 assetsWithdrawn, uint256 sharesWithdrawn)
    {
        Id id = marketParams.id();

        address onBehalf = msg.sender;
        address receiver = msg.sender;

        morpho.accrueInterest(marketParams);
        uint256 totalSupplyAssets = morpho.totalSupplyAssets(id);
        uint256 totalSupplyShares = morpho.totalSupplyShares(id);
        uint256 shares = morpho.supplyShares(id, msg.sender);

        uint256 assetsMax = shares.toAssetsDown(totalSupplyAssets, totalSupplyShares);

        if (amount >= assetsMax) {
            (assetsWithdrawn, sharesWithdrawn) = morpho.withdraw(marketParams, 0, shares, onBehalf, receiver);
        } else {
            (assetsWithdrawn, sharesWithdrawn) = morpho.withdraw(marketParams, amount, 0, onBehalf, receiver);
        }
    }

    /// @notice Handles the borrowing of assets by the caller from a specific market.
    /// @param marketParams The parameters of the market.
    /// @param amount The amount of assets the user is borrowing.
    /// @return assetsBorrowed The actual amount of assets borrowed.
    /// @return sharesBorrowed The shares borrowed in return for the assets.
    function borrow(MarketParams memory marketParams, uint256 amount)
        external
        returns (uint256 assetsBorrowed, uint256 sharesBorrowed)
    {
        uint256 shares = 0;
        address onBehalf = msg.sender;
        address receiver = msg.sender;

        (assetsBorrowed, sharesBorrowed) = morpho.borrow(marketParams, amount, shares, onBehalf, receiver);
    }

    /// @notice Handles the repayment of a specified amount of assets by the caller to a specific market.
    /// @param marketParams The parameters of the market.
    /// @param amount The amount of assets the user is repaying.
    /// @return assetsRepaid The actual amount of assets repaid.
    /// @return sharesRepaid The shares repaid in return for the assets.
    function repayAmount(MarketParams memory marketParams, uint256 amount)
        external
        returns (uint256 assetsRepaid, uint256 sharesRepaid)
    {
        ERC20(marketParams.loanToken).forceApprove(address(morpho), type(uint256).max);
        ERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), amount);

        uint256 shares = 0;
        address onBehalf = msg.sender;
        (assetsRepaid, sharesRepaid) = morpho.repay(marketParams, amount, shares, onBehalf, hex"");
    }

    /// @notice Handles the repayment of 50% of the borrowed assets by the caller to a specific market.
    /// @param marketParams The parameters of the market.
    /// @return assetsRepaid The actual amount of assets repaid.
    /// @return sharesRepaid The shares repaid in return for the assets.
    function repay50Percent(MarketParams memory marketParams)
        external
        returns (uint256 assetsRepaid, uint256 sharesRepaid)
    {
        ERC20(marketParams.loanToken).forceApprove(address(morpho), type(uint256).max);

        Id marketId = marketParams.id();

        (,, uint256 totalBorrowAssets, uint256 totalBorrowShares) = morpho.expectedMarketBalances(marketParams);
        uint256 borrowShares = morpho.position(marketId, msg.sender).borrowShares;

        uint256 repaidAmount = (borrowShares / 2).toAssetsUp(totalBorrowAssets, totalBorrowShares);
        ERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), repaidAmount);

        uint256 amount = 0;
        address onBehalf = msg.sender;

        (assetsRepaid, sharesRepaid) = morpho.repay(marketParams, amount, borrowShares / 2, onBehalf, hex"");
    }

    /// @notice Handles the repayment of all the borrowed assets by the caller to a specific market.
    /// @param marketParams The parameters of the market.
    /// @return assetsRepaid The actual amount of assets repaid.
    /// @return sharesRepaid The shares repaid in return for the assets.
    function repayAll(MarketParams memory marketParams) external returns (uint256 assetsRepaid, uint256 sharesRepaid) {
        ERC20(marketParams.loanToken).forceApprove(address(morpho), type(uint256).max);

        Id marketId = marketParams.id();

        (,, uint256 totalBorrowAssets, uint256 totalBorrowShares) = morpho.expectedMarketBalances(marketParams);
        uint256 borrowShares = morpho.position(marketId, msg.sender).borrowShares;

        uint256 repaidAmount = borrowShares.toAssetsUp(totalBorrowAssets, totalBorrowShares);
        ERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), repaidAmount);

        uint256 amount = 0;
        address onBehalf = msg.sender;
        (assetsRepaid, sharesRepaid) = morpho.repay(marketParams, amount, borrowShares, onBehalf, hex"");
    }

    /// @notice Handles the repayment of a specified amount of assets by the caller to a specific market. If the amount
    /// is greater than the total amount borrowed by the user, repays all the shares of the user.
    /// @param marketParams The parameters of the market.
    /// @param amount The amount of assets the user is repaying.
    /// @return assetsRepaid The actual amount of assets repaid.
    /// @return sharesRepaid The shares repaid in return for the assets.
    function repayAmountOrAll(MarketParams memory marketParams, uint256 amount)
        external
        returns (uint256 assetsRepaid, uint256 sharesRepaid)
    {
        ERC20(marketParams.loanToken).forceApprove(address(morpho), type(uint256).max);

        Id id = marketParams.id();

        address onBehalf = msg.sender;

        morpho.accrueInterest(marketParams);
        uint256 totalBorrowAssets = morpho.totalBorrowAssets(id);
        uint256 totalBorrowShares = morpho.totalBorrowShares(id);
        uint256 shares = morpho.borrowShares(id, msg.sender);
        uint256 assetsMax = shares.toAssetsUp(totalBorrowAssets, totalBorrowShares);

        if (amount >= assetsMax) {
            ERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), assetsMax);
            (assetsRepaid, sharesRepaid) = morpho.repay(marketParams, 0, shares, onBehalf, hex"");
        } else {
            ERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), amount);
            (assetsRepaid, sharesRepaid) = morpho.repay(marketParams, amount, 0, onBehalf, hex"");
        }
    }
}

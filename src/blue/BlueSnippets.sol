// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Id, IMorpho, MarketParams, Market} from "@morpho-blue/interfaces/IMorpho.sol";
import {IERC20} from "@morpho-blue/interfaces/IERC20.sol";
import {IIrm} from "@morpho-blue/interfaces/IIrm.sol";
import {IOracle} from "@morpho-blue/interfaces/IOracle.sol";

import {ERC20} from "@openzeppelin4/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin4/token/ERC20/utils/SafeERC20.sol";
import {MorphoBalancesLib} from "@morpho-blue/libraries/periphery/MorphoBalancesLib.sol";
import {MarketParamsLib} from "@morpho-blue/libraries/MarketParamsLib.sol";
import {MorphoLib} from "@morpho-blue/libraries/periphery/MorphoLib.sol";
import {MorphoStorageLib} from "@morpho-blue/libraries/periphery/MorphoStorageLib.sol";
import {MathLib} from "@morpho-blue/libraries/MathLib.sol";

import {SharesMathLib} from "@morpho-blue/libraries/SharesMathLib.sol";

import {ORACLE_PRICE_SCALE} from "@morpho-blue/libraries/ConstantsLib.sol";

/// @title Snippets
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice The Morpho Snippets contract.
contract BlueSnippets {
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

    // INFORMATIONAL: No 'Total Supply' and no 'Total Borrow' functions to calculate on chain as there could be some
    // weird oracles / markets created

    /**
     * @notice Calculates the supply APY (Annual Percentage Yield) for a given market.
     * @param marketParams The parameters of the market.
     * @param market The market for which the supply APY is being calculated.
     * @return supplyRate The calculated supply APY.
     */
    function supplyAPY(MarketParams memory marketParams, Market memory market)
        public
        view
        returns (uint256 supplyRate)
    {
        (uint256 totalSupplyAssets,, uint256 totalBorrowAssets,) = morpho.expectedMarketBalances(marketParams);

        // Get the borrow rate
        uint256 borrowRate = borrowAPY(marketParams, market);

        // Get the supply rate
        uint256 utilization = totalBorrowAssets == 0 ? 0 : totalBorrowAssets.wDivUp(totalSupplyAssets);

        supplyRate = borrowRate.wMulDown(1 ether - market.fee).wMulDown(utilization);
    }

    /**
     * @notice Calculates the borrow APY (Annual Percentage Yield) for a given market.
     * @param marketParams The parameters of the market.
     * @param market The market for which the borrow APY is being calculated.
     * @return borrowRate The calculated borrow APY.
     */
    function borrowAPY(MarketParams memory marketParams, Market memory market)
        public
        view
        returns (uint256 borrowRate)
    {
        if (marketParams.irm != address(0)) {
            borrowRate = IIrm(marketParams.irm).borrowRateView(marketParams, market).wTaylorCompounded(1);
        }
    }

    /**
     * @notice Calculates the total supply balance of a given user in a specific market.
     * @param marketParams The parameters of the market.
     * @param user The address of the user whose supply balance is being calculated.
     * @return totalSupplyAssets The calculated total supply balance.
     */
    function supplyAssetsUser(MarketParams memory marketParams, address user)
        public
        view
        returns (uint256 totalSupplyAssets)
    {
        totalSupplyAssets = morpho.expectedSupplyAssets(marketParams, user);
    }

    /**
     * @notice Calculates the total borrow balance of a given user in a specific market.
     * @param marketParams The parameters of the market.
     * @param user The address of the user whose borrow balance is being calculated.
     * @return totalBorrowAssets The calculated total borrow balance.
     */
    function borrowAssetsUser(MarketParams memory marketParams, address user)
        public
        view
        returns (uint256 totalBorrowAssets)
    {
        totalBorrowAssets = morpho.expectedBorrowAssets(marketParams, user);
    }

    /**
     * @notice Calculates the total collateral balance of a given user in a specific market.
     * @dev It uses extSloads to load only one storage slot of the Position struct and save gas.
     * @param marketId The identifier of the market.
     * @param user The address of the user whose collateral balance is being calculated.
     * @return totalCollateralAssets The calculated total collateral balance.
     */
    function collateralAssetsUser(Id marketId, address user) public view returns (uint256 totalCollateralAssets) {
        bytes32[] memory slots = new bytes32[](1);
        slots[0] = MorphoStorageLib.positionBorrowSharesAndCollateralSlot(marketId, user);
        bytes32[] memory values = morpho.extSloads(slots);
        totalCollateralAssets = uint256(values[0] >> 128);
    }

    /**
     * @notice Calculates the total supply of assets in a specific market.
     * @param marketParams The parameters of the market.
     * @return totalSupplyAssets The calculated total supply of assets.
     */
    function marketTotalSupply(MarketParams memory marketParams) public view returns (uint256 totalSupplyAssets) {
        totalSupplyAssets = morpho.expectedTotalSupplyAssets(marketParams);
    }

    /**
     * @notice Calculates the total borrow of assets in a specific market.
     * @param marketParams The parameters of the market.
     * @return totalBorrowAssets The calculated total borrow of assets.
     */
    function marketTotalBorrow(MarketParams memory marketParams) public view returns (uint256 totalBorrowAssets) {
        totalBorrowAssets = morpho.expectedTotalBorrowAssets(marketParams);
    }

    /**
     * @notice Calculates the health factor of a user in a specific market.
     * @param marketParams The parameters of the market.
     * @param id The identifier of the market.
     * @param user The address of the user whose health factor is being calculated.
     * @return healthFactor The calculated health factor.
     */
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

    /**
     * @notice Handles the supply of assets by the caller to a specific market.
     * @param marketParams The parameters of the market.
     * @param amount The amount of assets the user is supplying.
     * @return assetsSupplied The actual amount of assets supplied.
     * @return sharesSupplied The shares supplied in return for the assets.
     */
    function supply(MarketParams memory marketParams, uint256 amount)
        external
        returns (uint256 assetsSupplied, uint256 sharesSupplied)
    {
        ERC20(marketParams.loanToken).safeApprove(address(morpho), type(uint256).max);
        ERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), amount);

        uint256 shares = 0;
        address onBehalf = msg.sender;

        (assetsSupplied, sharesSupplied) = morpho.supply(marketParams, amount, shares, onBehalf, hex"");
    }

    /**
     * @notice Handles the supply of collateral by the caller to a specific market.
     * @param marketParams The parameters of the market.
     * @param amount The amount of collateral the user is supplying.
     */
    function supplyCollateral(MarketParams memory marketParams, uint256 amount) external {
        ERC20(marketParams.collateralToken).safeApprove(address(morpho), type(uint256).max);
        ERC20(marketParams.collateralToken).safeTransferFrom(msg.sender, address(this), amount);

        address onBehalf = msg.sender;

        morpho.supplyCollateral(marketParams, amount, onBehalf, hex"");
    }

    /**
     * @notice Handles the withdrawal of collateral by the caller from a specific market of a specific amount. The
     * withdrawn funds are going to the receiver.
     * @param marketParams The parameters of the market.
     * @param amount The amount of collateral the user is withdrawing.
     */
    function withdrawCollateral(MarketParams memory marketParams, uint256 amount) external {
        address onBehalf = msg.sender;
        address receiver = msg.sender;

        morpho.withdrawCollateral(marketParams, amount, onBehalf, receiver);
    }

    /**
     * @notice Handles the withdrawal of a specified amount of assets by the caller from a specific market.
     * @param marketParams The parameters of the market.
     * @param amount The amount of assets the user is withdrawing.
     * @return assetsWithdrawn The actual amount of assets withdrawn.
     * @return sharesWithdrawn The shares withdrawn in return for the assets.
     */
    function withdrawAmount(MarketParams memory marketParams, uint256 amount)
        external
        returns (uint256 assetsWithdrawn, uint256 sharesWithdrawn)
    {
        uint256 shares = 0;
        address onBehalf = msg.sender;
        address receiver = msg.sender;

        (assetsWithdrawn, sharesWithdrawn) = morpho.withdraw(marketParams, amount, shares, onBehalf, receiver);
    }

    /**
     * @notice Handles the withdrawal of 50% of the assets by the caller from a specific market.
     * @param marketParams The parameters of the market.
     * @return assetsWithdrawn The actual amount of assets withdrawn.
     * @return sharesWithdrawn The shares withdrawn in return for the assets.
     */
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

    /**
     * @notice Handles the withdrawal of all the assets by the caller from a specific market.
     * @param marketParams The parameters of the market.
     * @return assetsWithdrawn The actual amount of assets withdrawn.
     * @return sharesWithdrawn The shares withdrawn in return for the assets.
     */
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

    /**
     * @notice Handles the borrowing of assets by the caller from a specific market.
     * @param marketParams The parameters of the market.
     * @param amount The amount of assets the user is borrowing.
     * @return assetsBorrowed The actual amount of assets borrowed.
     * @return sharesBorrowed The shares borrowed in return for the assets.
     */
    function borrow(MarketParams memory marketParams, uint256 amount)
        external
        returns (uint256 assetsBorrowed, uint256 sharesBorrowed)
    {
        uint256 shares = 0;
        address onBehalf = msg.sender;
        address receiver = msg.sender;

        (assetsBorrowed, sharesBorrowed) = morpho.borrow(marketParams, amount, shares, onBehalf, receiver);
    }

    /**
     * @notice Handles the repayment of a specified amount of assets by the caller to a specific market.
     * @param marketParams The parameters of the market.
     * @param amount The amount of assets the user is repaying.
     * @return assetsRepaid The actual amount of assets repaid.
     * @return sharesRepaid The shares repaid in return for the assets.
     */
    function repayAmount(MarketParams memory marketParams, uint256 amount)
        external
        returns (uint256 assetsRepaid, uint256 sharesRepaid)
    {
        ERC20(marketParams.loanToken).safeApprove(address(morpho), type(uint256).max);
        ERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), amount);

        uint256 shares = 0;
        address onBehalf = msg.sender;
        (assetsRepaid, sharesRepaid) = morpho.repay(marketParams, amount, shares, onBehalf, hex"");
    }

    /**
     * @notice Handles the repayment of 50% of the borrowed assets by the caller to a specific market.
     * @param marketParams The parameters of the market.
     * @return assetsRepaid The actual amount of assets repaid.
     * @return sharesRepaid The shares repaid in return for the assets.
     */
    function repay50Percent(MarketParams memory marketParams)
        external
        returns (uint256 assetsRepaid, uint256 sharesRepaid)
    {
        ERC20(marketParams.loanToken).safeApprove(address(morpho), type(uint256).max);

        Id marketId = marketParams.id();

        (,, uint256 totalBorrowAssets, uint256 totalBorrowShares) = morpho.expectedMarketBalances(marketParams);
        uint256 borrowShares = morpho.position(marketId, msg.sender).borrowShares;

        uint256 repaidAmount = (borrowShares / 2).toAssetsUp(totalBorrowAssets, totalBorrowShares);
        ERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), repaidAmount);

        uint256 amount = 0;
        address onBehalf = msg.sender;

        (assetsRepaid, sharesRepaid) = morpho.repay(marketParams, amount, borrowShares / 2, onBehalf, hex"");
    }

    /**
     * @notice Handles the repayment of all the borrowed assets by the caller to a specific market.
     * @param marketParams The parameters of the market.
     * @return assetsRepaid The actual amount of assets repaid.
     * @return sharesRepaid The shares repaid in return for the assets.
     */
    function repayAll(MarketParams memory marketParams) external returns (uint256 assetsRepaid, uint256 sharesRepaid) {
        ERC20(marketParams.loanToken).safeApprove(address(morpho), type(uint256).max);

        Id marketId = marketParams.id();

        (,, uint256 totalBorrowAssets, uint256 totalBorrowShares) = morpho.expectedMarketBalances(marketParams);
        uint256 borrowShares = morpho.position(marketId, msg.sender).borrowShares;

        uint256 repaidAmount = borrowShares.toAssetsUp(totalBorrowAssets, totalBorrowShares);
        ERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), repaidAmount);

        uint256 amount = 0;
        address onBehalf = msg.sender;
        (assetsRepaid, sharesRepaid) = morpho.repay(marketParams, amount, borrowShares, onBehalf, hex"");
    }
}

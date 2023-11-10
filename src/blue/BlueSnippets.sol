// SPDX-License-Identifier: AGPL-3.0-only
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
     * @notice Calculates the supply APR (Annual Percentage Rate) for a given market.
     * @param marketParams The parameters of the market.
     * @param market The market for which the supply APR is being calculated.
     * @return supplyRate The calculated supply APR.
     */
    function supplyAPR(MarketParams memory marketParams, Market memory market)
        public
        view
        returns (uint256 supplyRate)
    {
        (uint256 totalSupplyAssets,, uint256 totalBorrowAssets,) = morpho.expectedMarketBalances(marketParams);

        // Get the borrow rate
        uint256 borrowRate = IIrm(marketParams.irm).borrowRateView(marketParams, market);

        // Get the supply rate
        uint256 utilization = totalBorrowAssets == 0 ? 0 : totalBorrowAssets.wDivUp(totalSupplyAssets);

        supplyRate = borrowRate.wMulDown(1 ether - market.fee).wMulDown(utilization);
    }

    /**
     * @notice Calculates the borrow APR (Annual Percentage Rate) for a given market.
     * @param marketParams The parameters of the market.
     * @param market The market for which the borrow APR is being calculated.
     * @return borrowRate The calculated borrow APR.
     */
    function borrowAPR(MarketParams memory marketParams, Market memory market)
        public
        view
        returns (uint256 borrowRate)
    {
        borrowRate = IIrm(marketParams.irm).borrowRateView(marketParams, market);
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
     * @notice Handles the supply of assets by a user to a specific market.
     * @param marketParams The parameters of the market.
     * @param amount The amount of assets the user is supplying.
     * @param user The address of the user supplying the assets onBehalf of.
     * @return assetsSupplied The actual amount of assets supplied.
     * @return sharesSupplied The shares supplied in return for the assets.
     */
    function supply(MarketParams memory marketParams, uint256 amount, address user)
        external
        returns (uint256 assetsSupplied, uint256 sharesSupplied)
    {
        ERC20(marketParams.loanToken).safeApprove(address(morpho), type(uint256).max);
        uint256 shares = 0;
        address onBehalf = user;
        (assetsSupplied, sharesSupplied) = morpho.supply(marketParams, amount, shares, onBehalf, hex"");
    }

    /**
     * @notice Handles the supply of collateral by a user to a specific market.
     * @param marketParams The parameters of the market.
     * @param amount The amount of collateral the user is supplying.
     * @param user The address of the user supplying the collateral on behalf of.
     */
    function supplyCollateral(MarketParams memory marketParams, uint256 amount, address user) external {
        ERC20(marketParams.collateralToken).safeApprove(address(morpho), type(uint256).max);
        address onBehalf = user;
        morpho.supplyCollateral(marketParams, amount, onBehalf, hex"");
    }

    /**
     * @notice Handles the withdrawal of collateral by a user from a specific market of a specific amount. The withdrawn
     * funds are going to the receiver.
     * @param marketParams The parameters of the market.
     * @param amount The amount of collateral the user is withdrawing.
     * @param user The address of the user withdrawing the collateral.
     */
    function withdrawCollateral(MarketParams memory marketParams, uint256 amount, address user) external {
        address onBehalf = user;
        address receiver = user;

        morpho.withdrawCollateral(marketParams, amount, onBehalf, receiver);
    }

    /**
     * @notice Handles the withdrawal of a specified amount of assets by a user from a specific market.
     * @param marketParams The parameters of the market.
     * @param amount The amount of assets the user is withdrawing.
     * @param user The address of the user withdrawing the assets.
     * @return assetsWithdrawn The actual amount of assets withdrawn.
     * @return sharesWithdrawn The shares withdrawn in return for the assets.
     */
    function withdrawAmount(MarketParams memory marketParams, uint256 amount, address user)
        external
        returns (uint256 assetsWithdrawn, uint256 sharesWithdrawn)
    {
        uint256 shares = 0;
        address onBehalf = user;
        address receiver = user;

        (assetsWithdrawn, sharesWithdrawn) = morpho.withdraw(marketParams, amount, shares, onBehalf, receiver);
    }

    /**
     * @notice Handles the withdrawal of 50% of the assets by a user from a specific market.
     * @param marketParams The parameters of the market.
     * @param user The address of the user withdrawing the assets.
     * @return assetsWithdrawn The actual amount of assets withdrawn.
     * @return sharesWithdrawn The shares withdrawn in return for the assets.
     */
    function withdraw50Percent(MarketParams memory marketParams, address user)
        external
        returns (uint256 assetsWithdrawn, uint256 sharesWithdrawn)
    {
        Id marketId = marketParams.id();
        uint256 supplyShares = morpho.position(marketId, address(this)).supplyShares;
        uint256 amount = 0;
        uint256 shares = supplyShares / 2;

        address onBehalf = user;
        address receiver = user;

        (assetsWithdrawn, sharesWithdrawn) = morpho.withdraw(marketParams, amount, shares, onBehalf, receiver);
    }

    /**
     * @notice Handles the withdrawal of all the assets by a user from a specific market.
     * @param marketParams The parameters of the market.
     * @param user The address of the user withdrawing the assets.
     * @return assetsWithdrawn The actual amount of assets withdrawn.
     * @return sharesWithdrawn The shares withdrawn in return for the assets.
     */
    function withdrawAll(MarketParams memory marketParams, address user)
        external
        returns (uint256 assetsWithdrawn, uint256 sharesWithdrawn)
    {
        Id marketId = marketParams.id();
        uint256 supplyShares = morpho.position(marketId, address(this)).supplyShares;
        uint256 amount = 0;

        address onBehalf = user;
        address receiver = user;

        (assetsWithdrawn, sharesWithdrawn) = morpho.withdraw(marketParams, amount, supplyShares, onBehalf, receiver);
    }

    /**
     * @notice Handles the borrowing of assets by a user from a specific market.
     * @param marketParams The parameters of the market.
     * @param amount The amount of assets the user is borrowing.
     * @param user The address of the user borrowing the assets.
     * @return assetsBorrowed The actual amount of assets borrowed.
     * @return sharesBorrowed The shares borrowed in return for the assets.
     */
    function borrow(MarketParams memory marketParams, uint256 amount, address user)
        external
        returns (uint256 assetsBorrowed, uint256 sharesBorrowed)
    {
        ERC20(marketParams.loanToken).safeApprove(address(morpho), type(uint256).max);
        uint256 shares = 0;
        address onBehalf = user;
        address receiver = user;

        (assetsBorrowed, sharesBorrowed) = morpho.borrow(marketParams, amount, shares, onBehalf, receiver);
    }

    /**
     * @notice Handles the repayment of a specified amount of assets by a user to a specific market.
     * @param marketParams The parameters of the market.
     * @param amount The amount of assets the user is repaying.
     * @param user The address of the user repaying the assets.
     * @return assetsRepaid The actual amount of assets repaid.
     * @return sharesRepaid The shares repaid in return for the assets.
     */
    function repayAmount(MarketParams memory marketParams, uint256 amount, address user)
        external
        returns (uint256 assetsRepaid, uint256 sharesRepaid)
    {
        uint256 shares = 0;
        address onBehalf = user;
        (assetsRepaid, sharesRepaid) = morpho.repay(marketParams, amount, shares, onBehalf, hex"");
    }

    /**
     * @notice Handles the repayment of 50% of the borrowed assets by a user to a specific market.
     * @param marketParams The parameters of the market.
     * @param user The address of the user repaying the assets.
     * @return assetsRepaid The actual amount of assets repaid.
     * @return sharesRepaid The shares repaid in return for the assets.
     */
    function repay50Percent(MarketParams memory marketParams, address user)
        external
        returns (uint256 assetsRepaid, uint256 sharesRepaid)
    {
        Id marketId = marketParams.id();
        bytes32[] memory slots = new bytes32[](1);
        slots[0] = MorphoStorageLib.positionBorrowSharesAndCollateralSlot(marketId, user);
        bytes32[] memory values = morpho.extSloads(slots);
        uint256 borrowShares = uint128(uint256(values[0]));

        uint256 amount = 0;
        address onBehalf = user;
        (assetsRepaid, sharesRepaid) = morpho.repay(marketParams, amount, borrowShares / 2, onBehalf, hex"");
    }

    /**
     * @notice Handles the repayment of all the borrowed assets by a user to a specific market.
     * @param marketParams The parameters of the market.
     * @param user The address of the user repaying the assets.
     * @return assetsRepaid The actual amount of assets repaid.
     * @return sharesRepaid The shares repaid in return for the assets.
     */
    function repayAll(MarketParams memory marketParams, address user)
        external
        returns (uint256 assetsRepaid, uint256 sharesRepaid)
    {
        Id marketId = marketParams.id();

        bytes32[] memory slots = new bytes32[](1);
        slots[0] = MorphoStorageLib.positionBorrowSharesAndCollateralSlot(marketId, user);
        bytes32[] memory values = morpho.extSloads(slots);
        uint256 borrowShares = uint128(uint256(values[0]));

        // alternative that works, but is more costly
        // (, uint256 borrowShares, ) = morpho.position(marketId, address(this));
        uint256 amount = 0;
        address onBehalf = user;
        (assetsRepaid, sharesRepaid) = morpho.repay(marketParams, amount, borrowShares, onBehalf, hex"");
    }
}

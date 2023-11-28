// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IMetaMorpho} from "@metamorpho/interfaces/IMetaMorpho.sol";
import {ConstantsLib} from "@metamorpho/libraries/ConstantsLib.sol";

import {MarketParamsLib} from "../../lib/metamorpho/lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {Id, IMorpho, Market, MarketParams} from "../../lib/metamorpho/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IIrm} from "../../lib/metamorpho/lib/morpho-blue/src/interfaces/IIrm.sol";
import {MorphoBalancesLib} from "../../lib/metamorpho/lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {MathLib, WAD} from "../../lib/metamorpho/lib/morpho-blue/src/libraries/MathLib.sol";

import {Math} from "@openzeppelin/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";

contract MetamorphoSnippets {
    IMorpho public immutable morpho;

    using MathLib for uint256;
    using Math for uint256;
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;

    constructor(address morphoAddress) {
        morpho = IMorpho(morphoAddress);
    }

    // --- VIEW FUNCTIONS ---

    /// @notice Returns the total assets deposited into a metamorpho `vault`.
    /// @dev it doesn't take into account the fees accrued since the last update.
    /// @param vault The address of the metamorpho vault.
    function totalDepositVault(address vault) public view returns (uint256 totalAssets) {
        totalAssets = IMetaMorpho(vault).lastTotalAssets();
    }

    /// @notice Returns the total assets supplied into a specific morpho blue market by a metamorpho `vault`.
    /// @param vault The address of the metamorpho vault.
    /// @param marketParams The morpho blue market.
    function vaultAssetsInMarket(address vault, MarketParams memory marketParams)
        public
        view
        returns (uint256 vaultAmount)
    {
        vaultAmount = morpho.expectedSupplyAssets(marketParams, vault);
    }

    /// @notice Returns the total shares balance of a `user` on a metamorpho `vault`.
    /// @param vault The address of the metamorpho vault.
    /// @param user The address of the user.
    function totalSharesUserVault(address vault, address user) public view returns (uint256 totalSharesUser) {
        totalSharesUser = IMetaMorpho(vault).balanceOf(user);
    }

    /// @notice Returns the supply queue a metamorpho `vault`.
    /// @param vault The address of the metamorpho vault.
    function supplyQueueVault(address vault) public view returns (Id[] memory supplyQueueList) {
        uint256 queueLength = IMetaMorpho(vault).supplyQueueLength();
        supplyQueueList = new Id[](queueLength);

        for (uint256 i; i < queueLength; ++i) {
            supplyQueueList[i] = IMetaMorpho(vault).supplyQueue(i);
        }

        return supplyQueueList;
    }

    /// @notice Returns the withdraw queue a metamorpho `vault`.
    /// @param vault The address of the metamorpho vault.
    function withdrawQueueVault(address vault) public view returns (Id[] memory withdrawQueueList) {
        uint256 queueLength = IMetaMorpho(vault).supplyQueueLength();
        withdrawQueueList = new Id[](queueLength);

        for (uint256 i; i < queueLength; ++i) {
            withdrawQueueList[i] = IMetaMorpho(vault).withdrawQueue(i);
        }

        return withdrawQueueList;
    }

    /// @notice Returns the supply cap of a market on a metamorpho `vault`.
    /// @param vault The address of the metamorpho vault.
    /// @param marketParams The morpho blue market.
    function capMarket(address vault, MarketParams memory marketParams) public view returns (uint192 cap) {
        Id id = marketParams.id();
        cap = IMetaMorpho(vault).config(id).cap;
    }

    /// @notice Returns the current APR (Annual Percentage Rate) of a morpho blue market.
    /// @param marketParams The morpho blue market parameters.
    /// @param market The morpho blue market state.
    function supplyAPRMarket(MarketParams memory marketParams, Market memory market)
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

    /// @notice Returns the current APR (Annual Percentage Rate) of a metamorpho vault.
    /// @dev It is computed as the sum of all APR of enabled markets weighted by the supply on these markets.
    /// @param vault The address of the metamorpho vault.
    function supplyAPRVault(address vault) public view returns (uint256 avgSupplyRate) {
        uint256 ratio;
        uint256 queueLength = IMetaMorpho(vault).withdrawQueueLength();

        uint256 totalAmount = totalDepositVault(vault);

        for (uint256 i; i < queueLength; ++i) {
            Id idMarket = IMetaMorpho(vault).withdrawQueue(i);

            MarketParams memory marketParams = morpho.idToMarketParams(idMarket);
            Market memory market = morpho.market(idMarket);

            uint256 currentSupplyAPR = supplyAPRMarket(marketParams, market);
            uint256 vaultAsset = vaultAssetsInMarket(vault, marketParams);
            ratio += currentSupplyAPR.wMulDown(vaultAsset);
        }

        avgSupplyRate = ratio.wDivUp(totalAmount);
    }

    // // --- MANAGING FUNCTIONS ---

    /// @notice Deposit `assets` into the `vault` on behalf of `onBehalf`.
    /// @dev Sender must approve the snippets contract to manage his tokens before the call.
    /// @param vault The address of the metamorpho vault.
    /// @param assets the amount to deposit.
    /// @param onBehalf The address that will own the increased deposit position.
    function depositInVault(address vault, uint256 assets, address onBehalf) public returns (uint256 shares) {
        ERC20(IMetaMorpho(vault).asset()).transferFrom(msg.sender, address(this), assets);

        _approveMaxVault(vault);

        shares = IMetaMorpho(vault).deposit(assets, onBehalf);
    }

    /// @notice Withdraws `assets` from the `vault` on behalf of the sender, and sends them to `receiver`.
    /// @dev Sender must approve the snippets contract to manage his tokens before the call.
    /// @param vault The address of the metamorpho vault.
    /// @param assets the amount to withdraw.
    /// @param receiver The address that will receive the withdrawn assets.
    function withdrawFromVaultAmount(address vault, uint256 assets, address receiver)
        public
        returns (uint256 redeemed)
    {
        redeemed = IMetaMorpho(vault).withdraw(assets, receiver, msg.sender);
    }

    /// @notice Withdraws the whole sender's position from the `vault`, and sends the withdrawn amount to `receiver`.
    /// @param vault The address of the metamorpho vault.
    /// @param receiver The address that will receive the withdrawn assets.
    function withdrawFromVaultAll(address vault, address receiver) public returns (uint256 redeemed) {
        uint256 assets = IMetaMorpho(vault).maxWithdraw(msg.sender);
        redeemed = IMetaMorpho(vault).withdraw(assets, receiver, msg.sender);
    }

    /// @notice Redeems the whole sender's position from the `vault`, and sends the withdrawn amount to `receiver`.
    /// @param vault The address of the metamorpho vault.
    /// @param receiver The address that will receive the withdrawn assets.
    function redeemAllFromVault(address vault, address receiver) public returns (uint256 redeemed) {
        uint256 maxToRedeem = IMetaMorpho(vault).maxRedeem(msg.sender);
        redeemed = IMetaMorpho(vault).redeem(maxToRedeem, receiver, msg.sender);
    }

    function _approveMaxVault(address vault) internal {
        if (ERC20(IMetaMorpho(vault).asset()).allowance(address(this), vault) == 0) {
            ERC20(IMetaMorpho(vault).asset()).approve(vault, type(uint256).max);
        }
    }
}

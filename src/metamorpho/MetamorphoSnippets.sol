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
    IMetaMorpho public immutable vault;

    using MathLib for uint256;
    using Math for uint256;
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;

    constructor(address vaultAddress, address morphoAddress) {
        morpho = IMorpho(morphoAddress);
        vault = IMetaMorpho(vaultAddress);
    }

    // --- VIEW FUNCTIONS ---

    /// @dev note that it corresponds to when the fee was last accrued.
    function totalDepositVault() public view returns (uint256 totalAssets) {
        totalAssets = vault.lastTotalAssets();
    }

    function vaultAssetsInMarket(MarketParams memory marketParams) public view returns (uint256 vaultAmount) {
        vaultAmount = morpho.expectedSupplyAssets(marketParams, address(vault));
    }

    function totalSharesUserVault(address user) public view returns (uint256 totalSharesUser) {
        totalSharesUser = vault.balanceOf(user);
    }

    // The following function will return the current supply queue of the vault
    function supplyQueueVault() public view returns (Id[] memory supplyQueueList) {
        uint256 queueLength = vault.supplyQueueLength();
        supplyQueueList = new Id[](queueLength);
        for (uint256 i; i < queueLength; ++i) {
            supplyQueueList[i] = vault.supplyQueue(i);
        }
        return supplyQueueList;
    }

    // // The following function will return the current withdraw queue of the vault
    function withdrawQueueVault() public view returns (Id[] memory withdrawQueueList) {
        uint256 queueLength = vault.supplyQueueLength();
        withdrawQueueList = new Id[](queueLength);
        for (uint256 i; i < queueLength; ++i) {
            withdrawQueueList[i] = vault.withdrawQueue(i);
        }
        return withdrawQueueList;
    }

    function capMarket(MarketParams memory marketParams) public view returns (uint192 cap) {
        Id id = marketParams.id();
        cap = vault.config(id).cap;
    }

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

    function supplyAPRVault() public view returns (uint256 avgSupplyRate) {
        uint256 ratio;
        uint256 queueLength = vault.withdrawQueueLength();
        uint256 totalAmount = totalDepositVault();

        for (uint256 i; i < queueLength; ++i) {
            Id idMarket = vault.withdrawQueue(i);
            MarketParams memory marketParams = morpho.idToMarketParams(idMarket);
            Market memory market = morpho.market(idMarket);

            uint256 currentSupplyAPR = supplyAPRMarket(marketParams, market);
            uint256 vaultAsset = vaultAssetsInMarket(marketParams);
            ratio += currentSupplyAPR.wMulDown(vaultAsset);
        }

        avgSupplyRate = ratio.wDivUp(totalAmount);
    }

    // // --- MANAGING FUNCTIONS ---

    // deposit in the vault a nb of asset
    function depositInVault(uint256 assets, address onBehalf) public returns (uint256 shares) {
        shares = vault.deposit(assets, onBehalf);
    }

    // withdraw from the vault a nb of asset
    function withdrawFromVaultAmount(uint256 assets, address onBehalf) public returns (uint256 redeemed) {
        address receiver = onBehalf;
        redeemed = vault.withdraw(assets, receiver, onBehalf);
    }

    // maxWithdraw from the vault
    function withdrawFromVaultAll(address onBehalf) public returns (uint256 redeemed) {
        address receiver = onBehalf;
        uint256 assets = vault.maxWithdraw(address(this));
        redeemed = vault.withdraw(assets, receiver, onBehalf);
    }

    // maxRedeem from the vault
    function redeemAllFromVault(address onBehalf) public returns (uint256 redeemed) {
        address receiver = onBehalf;
        uint256 maxToRedeem = vault.maxRedeem(address(this));
        redeemed = vault.redeem(maxToRedeem, receiver, onBehalf);
    }

    // // TODO:
    // // Reallocation example
}

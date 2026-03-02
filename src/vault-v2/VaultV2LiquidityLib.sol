// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IVaultV2} from "../../lib/vault-v2/src/interfaces/IVaultV2.sol";
import {IERC20} from "../../lib/vault-v2/src/interfaces/IERC20.sol";
import {IMorphoMarketV1AdapterV2} from "../../lib/vault-v2/src/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";
import {IMorphoVaultV1Adapter} from "../../lib/vault-v2/src/adapters/interfaces/IMorphoVaultV1Adapter.sol";
import {IERC4626} from "../../lib/vault-v2/src/interfaces/IERC4626.sol";
import {IMorpho, MarketParams, Id} from "../../lib/vault-v2/lib/metamorpho/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/vault-v2/lib/metamorpho/lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {SharesMathLib} from "../../lib/vault-v2/lib/metamorpho/lib/morpho-blue/src/libraries/SharesMathLib.sol";
import {MorphoBalancesLib} from "../../lib/vault-v2/lib/metamorpho/lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";

/// @title VaultV2LiquidityLib
/// @notice Library to compute available liquidity and max withdrawable amounts for VaultV2
/// @dev DEMO / INTEGRATION HELPER ONLY: this library is not a generic adapter router and should not be treated as a
///      canonical source of truth for all VaultV2 adapter families.
/// @dev Adapter coverage is intentionally limited to:
///      - MorphoMarketV1AdapterV2
///      - MorphoVaultV1Adapter
/// @dev Unknown adapters are conservatively ignored and contribute 0 liquidity.
/// @dev If new Morpho protocols or adapter types are added, this library must be updated to support them explicitly.
/// @dev This provides the "view" equivalent of maxWithdraw/maxRedeem that VaultV2 returns 0 for.
/// @dev Designed to help integrators who need a liquidity() view getter.
/// @dev IMPORTANT: The vault's exit() function only auto-withdraws from the single market encoded
///      in liquidityData, not from all markets in the adapter. This library mirrors that behavior.
library VaultV2LiquidityLib {
    using SharesMathLib for uint256;
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;

    /// @notice Computes the available liquidity for instant withdrawal from a VaultV2
    /// @param vault The VaultV2 address
    /// @return liquidity The amount of assets that can be withdrawn instantly
    function availableLiquidity(address vault) internal view returns (uint256 liquidity) {
        address asset = IVaultV2(vault).asset();

        // Start with idle assets in the vault
        liquidity = IERC20(asset).balanceOf(vault);

        // Add available liquidity from the liquidity adapter if set
        address liquidityAdapter = IVaultV2(vault).liquidityAdapter();
        if (liquidityAdapter != address(0)) {
            bytes memory liqData = IVaultV2(vault).liquidityData();
            liquidity += adapterAvailableLiquidity(liquidityAdapter, liqData);
        }
    }

    /// @notice Computes the available liquidity from an adapter
    /// @dev Supports MorphoMarketV1AdapterV2 and MorphoVaultV1Adapter
    /// @dev Unknown adapter types return 0.
    /// @param adapter The adapter address
    /// @param liqData The liquidityData from the vault (encodes the single exit market)
    /// @return liquidity The amount of assets available for withdrawal
    function adapterAvailableLiquidity(address adapter, bytes memory liqData) internal view returns (uint256 liquidity) {
        // Try MorphoMarketV1AdapterV2 first (direct market adapter)
        try IMorphoMarketV1AdapterV2(adapter).morpho() returns (address morpho) {
            liquidity = morphoMarketAdapterLiquidity(adapter, morpho, liqData);
        } catch {
            // Try MorphoVaultV1Adapter (V1 vault wrapper)
            try IMorphoVaultV1Adapter(adapter).morphoVaultV1() returns (address morphoVaultV1) {
                liquidity = morphoVaultV1AdapterLiquidity(adapter, morphoVaultV1);
            } catch {
                // Unknown adapter type - return 0 (conservative)
                liquidity = 0;
            }
        }
    }

    /// @notice Computes available liquidity from a MorphoMarketV1AdapterV2
    /// @dev Only considers the single market encoded in liquidityData (the exit market),
    ///      not all markets the adapter has positions in.
    /// @param adapter The adapter address
    /// @param morpho The Morpho Blue address
    /// @param liqData The liquidityData encoding the single MarketParams for exit
    /// @return liquidity Available liquidity from the exit market
    function morphoMarketAdapterLiquidity(address adapter, address morpho, bytes memory liqData)
        internal
        view
        returns (uint256 liquidity)
    {
        if (liqData.length == 0) return 0;

        // Decode the single exit market from liquidityData
        MarketParams memory marketParams = abi.decode(liqData, (MarketParams));
        bytes32 marketId = Id.unwrap(marketParams.id());

        // Get adapter's supply shares in this market
        uint256 adapterSupplyShares = IMorphoMarketV1AdapterV2(adapter).supplyShares(marketId);
        if (adapterSupplyShares == 0) return 0;

        // Get expected market balances (with accrued interest) via MorphoBalancesLib
        (uint256 totalSupplyAssets, uint256 totalSupplyShares, uint256 totalBorrowAssets,) =
            IMorpho(morpho).expectedMarketBalances(marketParams);

        // Adapter's supply in assets
        uint256 adapterSupplyAssets = adapterSupplyShares.toAssetsDown(totalSupplyAssets, totalSupplyShares);

        // Market's available liquidity (supply - borrow)
        uint256 marketLiquidity =
            totalSupplyAssets > totalBorrowAssets ? totalSupplyAssets - totalBorrowAssets : 0;

        // Cap by actual token balance held in Morpho singleton
        uint256 morphoBalance = IERC20(marketParams.loanToken).balanceOf(morpho);
        if (morphoBalance < marketLiquidity) {
            marketLiquidity = morphoBalance;
        }

        // Adapter can withdraw min(its position, market liquidity)
        liquidity = adapterSupplyAssets < marketLiquidity ? adapterSupplyAssets : marketLiquidity;
    }

    /// @notice Computes available liquidity from a MorphoVaultV1Adapter
    /// @dev The underlying vault can be either a MetaMorpho V1 or a VaultV2.
    ///      - V1: maxWithdraw works correctly (loops through markets internally).
    ///      - V2: maxWithdraw always returns 0 by design, so we compute liquidity manually.
    /// @dev When the underlying is a VaultV2, this recurses into availableLiquidity().
    ///      Recursion depth is bounded by the vault nesting depth (practically 2-3 levels).
    ///      Safe for view calls; gas is negligible for off-chain usage.
    /// @param adapter The adapter address
    /// @param underlyingVault The vault address wrapped by the adapter (V1 or V2)
    /// @return The available liquidity from the underlying vault
    function morphoVaultV1AdapterLiquidity(address adapter, address underlyingVault) internal view returns (uint256) {
        // Detect if the underlying vault is a VaultV2 by probing a V2-specific function.
        try IVaultV2(underlyingVault).liquidityAdapter() {
            // Underlying is a VaultV2 -> maxWithdraw returns 0, so compute manually.
            uint256 adapterAssets =
                IERC4626(underlyingVault).previewRedeem(IERC4626(underlyingVault).balanceOf(adapter));
            // Recurse: compute the inner V2's available liquidity (idle + its own liquidity adapter).
            uint256 innerLiquidity = availableLiquidity(underlyingVault);
            return adapterAssets < innerLiquidity ? adapterAssets : innerLiquidity;
        } catch {
            // Underlying is a V1 vault -> maxWithdraw loops through markets and returns correctly.
            return IERC4626(underlyingVault).maxWithdraw(adapter);
        }
    }

    /// @notice Computes the maximum amount a user can withdraw from a VaultV2
    /// @param vault The VaultV2 address
    /// @param owner The owner address
    /// @return maxAssets The maximum assets the owner can withdraw
    function maxWithdrawView(address vault, address owner) internal view returns (uint256 maxAssets) {
        uint256 shares = IVaultV2(vault).balanceOf(owner);
        if (shares == 0) return 0;

        // Convert shares to assets using the preview function
        uint256 ownerAssets = IVaultV2(vault).previewRedeem(shares);

        // Get available liquidity
        uint256 liquidity = availableLiquidity(vault);

        // Owner can withdraw min(their position, available liquidity)
        maxAssets = ownerAssets < liquidity ? ownerAssets : liquidity;
    }

    /// @notice Computes the maximum shares a user can redeem from a VaultV2
    /// @param vault The VaultV2 address
    /// @param owner The owner address
    /// @return maxShares The maximum shares the owner can redeem
    function maxRedeemView(address vault, address owner) internal view returns (uint256 maxShares) {
        uint256 shares = IVaultV2(vault).balanceOf(owner);
        if (shares == 0) return 0;

        // Get available liquidity in assets
        uint256 liquidity = availableLiquidity(vault);

        // Convert liquidity to shares
        uint256 liquidityShares = IVaultV2(vault).previewWithdraw(liquidity);

        // Owner can redeem min(their shares, shares for available liquidity)
        maxShares = shares < liquidityShares ? shares : liquidityShares;
    }
}

/// @title VaultV2LiquidityLens
/// @notice External view contract that exposes VaultV2LiquidityLib functions
/// @dev Can be used for off-chain queries or on-chain integrations
contract VaultV2LiquidityLens {
    /// @notice Returns the available liquidity for instant withdrawal from a VaultV2
    function availableLiquidity(address vault) external view returns (uint256) {
        return VaultV2LiquidityLib.availableLiquidity(vault);
    }

    /// @notice Returns the maximum assets a user can withdraw from a VaultV2
    function maxWithdraw(address vault, address owner) external view returns (uint256) {
        return VaultV2LiquidityLib.maxWithdrawView(vault, owner);
    }

    /// @notice Returns the maximum shares a user can redeem from a VaultV2
    function maxRedeem(address vault, address owner) external view returns (uint256) {
        return VaultV2LiquidityLib.maxRedeemView(vault, owner);
    }

    /// @notice Returns the available liquidity from a specific adapter
    /// @param adapter The adapter address
    /// @param liqData The liquidityData encoding the exit market
    function adapterLiquidity(address adapter, bytes memory liqData) external view returns (uint256) {
        return VaultV2LiquidityLib.adapterAvailableLiquidity(adapter, liqData);
    }
}

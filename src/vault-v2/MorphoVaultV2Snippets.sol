// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVaultV2, Caps} from "../../lib/vault-v2/src/interfaces/IVaultV2.sol";
import {IAdapter} from "../../lib/vault-v2/src/interfaces/IAdapter.sol";
import {IERC20} from "../../lib/vault-v2/src/interfaces/IERC20.sol";
import {IMorphoMarketV1Adapter} from "../../lib/vault-v2/src/adapters/interfaces/IMorphoMarketV1Adapter.sol";

import {Id, IMorpho, Market, MarketParams} from "../../lib/vault-v2/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IIrm} from "../../lib/vault-v2/lib/morpho-blue/src/interfaces/IIrm.sol";
import {SharesMathLib} from "../../lib/vault-v2/lib/morpho-blue/src/libraries/SharesMathLib.sol";
import {MorphoLib} from "../../lib/vault-v2/lib/morpho-blue/src/libraries/periphery/MorphoLib.sol";
import {MorphoBalancesLib} from "../../lib/vault-v2/lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {MathLib, WAD} from "../../lib/vault-v2/lib/morpho-blue/src/libraries/MathLib.sol";
import {MarketParamsLib} from "../../lib/vault-v2/lib/morpho-blue/src/libraries/MarketParamsLib.sol";

import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

/// @title MorphoVaultV2Snippets
/// @notice Snippets contract for interacting with Morpho VaultV2.
/// @dev VaultV2 uses an adapter-based architecture where allocators deploy capital to various adapters.
/// @dev Each adapter can invest in underlying markets and report their real asset values back to the vault.
/// @dev The vault tracks allocations per ID, which can be shared across multiple adapters to cap exposure.
contract MorphoVaultV2Snippets {
    using Math for uint256;
    using SharesMathLib for uint256;
    using MathLib for uint256;
    using MarketParamsLib for MarketParams;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;

    IMorpho public immutable morpho;

    constructor(address morphoAddress) {
        require(morphoAddress != address(0), "morpho address cannot be zero");
        morpho = IMorpho(morphoAddress);
    }

    // --- VIEW FUNCTIONS ---

    /// @notice Returns the total assets deposited into a VaultV2 `vault`.
    /// @dev This includes both idle assets in the vault and assets allocated to adapters.
    /// @dev The value is computed by accruing interest and aggregating adapter positions.
    /// @param vault The address of the VaultV2 vault.
    /// @return totalAssets The total assets controlled by the vault.
    function totalDepositVault(address vault) public view returns (uint256 totalAssets) {
        totalAssets = IVaultV2(vault).totalAssets();
    }

    /// @notice Returns the total shares balance of a `user` in a VaultV2 `vault`.
    /// @dev VaultV2 is ERC4626 compliant, so balanceOf returns the user's shares.
    /// @param vault The address of the VaultV2 vault.
    /// @param user The address of the user.
    /// @return totalSharesUser The total shares owned by the user.
    function totalSharesUserVault(address vault, address user) public view returns (uint256 totalSharesUser) {
        totalSharesUser = IVaultV2(vault).balanceOf(user);
    }

    /// @notice Returns the current share price of the VaultV2 `vault`.
    /// @dev Share price is calculated as totalAssets per share, including virtual shares.
    /// @param vault The address of the VaultV2 vault.
    /// @return sharePrice The current share price (in asset terms per share).
    function sharePriceVault(address vault) public view returns (uint256 sharePrice) {
        uint256 totalAssets = IVaultV2(vault).totalAssets();
        uint256 totalSupply = IVaultV2(vault).totalSupply();
        uint256 virtualShares = IVaultV2(vault).virtualShares();

        if (totalSupply + virtualShares == 0) return 0;
        sharePrice = (totalAssets + 1).mulDiv(1e18, totalSupply + virtualShares);
    }

    /// @notice Returns the list of all adapters registered in a VaultV2 `vault`.
    /// @dev Adapters are contracts that allocate vault assets to underlying markets.
    /// @param vault The address of the VaultV2 vault.
    /// @return adaptersList An array of adapter addresses.
    function adaptersListVault(address vault) public view returns (address[] memory adaptersList) {
        uint256 length = IVaultV2(vault).adaptersLength();
        adaptersList = new address[](length);

        for (uint256 i; i < length; ++i) {
            adaptersList[i] = IVaultV2(vault).adapters(i);
        }
    }

    /// @notice Returns the current allocation for a specific `id` in a VaultV2 `vault`.
    /// @dev IDs are used to track allocations across markets. Multiple adapters can share the same ID.
    /// @dev The allocation represents the estimated amount of assets currently allocated to markets with this ID.
    /// @param vault The address of the VaultV2 vault.
    /// @param idData The raw bytes data representing the ID (will be hashed to get the actual ID).
    /// @return allocation The current allocation for this ID.
    function allocationById(address vault, bytes memory idData) public view returns (uint256 allocation) {
        bytes32 id = keccak256(idData);
        allocation = IVaultV2(vault).allocation(id);
    }

    /// @notice Returns the absolute cap for a specific `id` in a VaultV2 `vault`.
    /// @dev The absolute cap is the maximum amount of assets that can be allocated to markets with this ID.
    /// @dev A cap of 0 prevents new allocations to this ID.
    /// @param vault The address of the VaultV2 vault.
    /// @param idData The raw bytes data representing the ID (will be hashed to get the actual ID).
    /// @return absoluteCap The absolute cap for this ID.
    function absoluteCapById(address vault, bytes memory idData) public view returns (uint256 absoluteCap) {
        bytes32 id = keccak256(idData);
        absoluteCap = IVaultV2(vault).absoluteCap(id);
    }

    /// @notice Returns the relative cap for a specific `id` in a VaultV2 `vault`.
    /// @dev The relative cap is the maximum percentage of total vault assets that can be allocated to markets with this ID.
    /// @dev Expressed in WAD (1e18 = 100%).
    /// @param vault The address of the VaultV2 vault.
    /// @param idData The raw bytes data representing the ID (will be hashed to get the actual ID).
    /// @return relativeCap The relative cap for this ID (in WAD).
    function relativeCapById(address vault, bytes memory idData) public view returns (uint256 relativeCap) {
        bytes32 id = keccak256(idData);
        relativeCap = IVaultV2(vault).relativeCap(id);
    }

    /// @notice Returns the full caps structure (allocation, absolute cap, relative cap) for a specific `id`.
    /// @param vault The address of the VaultV2 vault.
    /// @param idData The raw bytes data representing the ID (will be hashed to get the actual ID).
    /// @return caps The Caps struct containing allocation, absoluteCap, and relativeCap.
    function capsById(address vault, bytes memory idData) public view returns (Caps memory caps) {
        bytes32 id = keccak256(idData);
        caps = Caps({
            allocation: IVaultV2(vault).allocation(id),
            absoluteCap: uint128(IVaultV2(vault).absoluteCap(id)),
            relativeCap: uint128(IVaultV2(vault).relativeCap(id))
        });
    }

    /// @notice Returns the real assets held by a specific `adapter`.
    /// @dev This queries the adapter directly to get the current value of its investments.
    /// @param adapter The address of the adapter.
    /// @return realAssets The current value of assets managed by the adapter.
    function realAssetsAdapter(address adapter) public view returns (uint256 realAssets) {
        realAssets = IAdapter(adapter).realAssets();
    }

    /// @notice Returns the idle assets (not allocated to any adapter) in a VaultV2 `vault`.
    /// @dev Idle assets are held directly by the vault contract and available for immediate withdrawal.
    /// @param vault The address of the VaultV2 vault.
    /// @return idleAssets The amount of idle assets in the vault.
    function idleAssetsVault(address vault) public view returns (uint256 idleAssets) {
        address asset = IVaultV2(vault).asset();
        idleAssets = IERC20(asset).balanceOf(vault);
    }

    /// @notice Returns the current APY information including performance and management fees.
    /// @dev This function returns the performance fee, management fee, and max rate.
    /// @dev The max rate caps how quickly the share price can increase due to interest.
    /// @param vault The address of the VaultV2 vault.
    /// @return performanceFee The performance fee (in WAD, 1e18 = 100%).
    /// @return managementFee The management fee (in WAD, annualized).
    /// @return maxRate The maximum rate of increase for total assets (in WAD per second).
    function feeInfoVault(address vault)
        public
        view
        returns (uint96 performanceFee, uint96 managementFee, uint64 maxRate)
    {
        performanceFee = IVaultV2(vault).performanceFee();
        managementFee = IVaultV2(vault).managementFee();
        maxRate = IVaultV2(vault).maxRate();
    }

    /// @notice Returns the liquidity adapter configuration for a VaultV2 `vault`.
    /// @dev The liquidity adapter is used for deposits (to allocate incoming assets) and withdrawals (to cover exits).
    /// @param vault The address of the VaultV2 vault.
    /// @return liquidityAdapter The address of the liquidity adapter.
    /// @return liquidityData The data passed to the liquidity adapter on allocate/deallocate.
    function liquidityAdapterVault(address vault)
        public
        view
        returns (address liquidityAdapter, bytes memory liquidityData)
    {
        liquidityAdapter = IVaultV2(vault).liquidityAdapter();
        liquidityData = IVaultV2(vault).liquidityData();
    }

    /// @notice Simulates interest accrual and returns the updated state.
    /// @dev This is a view function that shows what would happen if accrueInterest() were called.
    /// @param vault The address of the VaultV2 vault.
    /// @return newTotalAssets The total assets after accruing interest.
    /// @return performanceFeeShares The shares minted to the performance fee recipient.
    /// @return managementFeeShares The shares minted to the management fee recipient.
    function accrueInterestView(address vault)
        public
        view
        returns (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares)
    {
        (newTotalAssets, performanceFeeShares, managementFeeShares) = IVaultV2(vault).accrueInterestView();
    }

    /// @notice Returns the amount of shares that would be minted for a given `assets` deposit.
    /// @dev Uses the vault's previewDeposit function which accounts for fees and current exchange rate.
    /// @param vault The address of the VaultV2 vault.
    /// @param assets The amount of assets to deposit.
    /// @return shares The amount of shares that would be minted.
    function previewDepositVault(address vault, uint256 assets) public view returns (uint256 shares) {
        shares = IVaultV2(vault).previewDeposit(assets);
    }

    /// @notice Returns the amount of assets needed to mint a given number of `shares`.
    /// @dev Uses the vault's previewMint function which accounts for fees and current exchange rate.
    /// @param vault The address of the VaultV2 vault.
    /// @param shares The amount of shares to mint.
    /// @return assets The amount of assets needed.
    function previewMintVault(address vault, uint256 shares) public view returns (uint256 assets) {
        assets = IVaultV2(vault).previewMint(shares);
    }

    /// @notice Returns the amount of shares that would be burned for a given `assets` withdrawal.
    /// @dev Uses the vault's previewWithdraw function which accounts for fees and current exchange rate.
    /// @param vault The address of the VaultV2 vault.
    /// @param assets The amount of assets to withdraw.
    /// @return shares The amount of shares that would be burned.
    function previewWithdrawVault(address vault, uint256 assets) public view returns (uint256 shares) {
        shares = IVaultV2(vault).previewWithdraw(assets);
    }

    /// @notice Returns the amount of assets that would be withdrawn for a given number of `shares`.
    /// @dev Uses the vault's previewRedeem function which accounts for fees and current exchange rate.
    /// @param vault The address of the VaultV2 vault.
    /// @param shares The amount of shares to redeem.
    /// @return assets The amount of assets that would be withdrawn.
    function previewRedeemVault(address vault, uint256 shares) public view returns (uint256 assets) {
        assets = IVaultV2(vault).previewRedeem(shares);
    }

    /// @notice Returns the total assets held by a specific `adapter`.
    /// @dev This is equivalent to vaultAssetsInMarket for MetaMorpho, showing allocation per adapter.
    /// @param adapter The address of the adapter.
    /// @return assets The total assets managed by this adapter.
    function vaultAssetsInAdapter(address adapter) public view returns (uint256 assets) {
        assets = IAdapter(adapter).realAssets();
    }

    /// @notice Returns the list of markets that a Morpho Market adapter is allocated to.
    /// @dev Only works with IMorphoMarketV1Adapter adapters.
    /// @param adapter The address of the Morpho Market adapter.
    /// @return marketsList An array of MarketParams structs representing all markets this adapter allocates to.
    function adapterMarketsList(address adapter) public view returns (MarketParams[] memory marketsList) {
        uint256 length = IMorphoMarketV1Adapter(adapter).marketParamsListLength();
        marketsList = new MarketParams[](length);

        for (uint256 i; i < length; ++i) {
            (address loanToken, address collateralToken, address oracle, address irm, uint256 lltv) =
                IMorphoMarketV1Adapter(adapter).marketParamsList(i);
            marketsList[i] = MarketParams({
                loanToken: loanToken,
                collateralToken: collateralToken,
                oracle: oracle,
                irm: irm,
                lltv: lltv
            });
        }
    }

    /// @notice Returns the allocation for a specific market within a Morpho Market adapter.
    /// @dev Shows how much of the adapter's assets are allocated to this specific market.
    /// @param adapter The address of the Morpho Market adapter.
    /// @param marketParams The market parameters to query.
    /// @return allocation The allocation for this market within the adapter.
    function adapterAllocationInMarket(address adapter, MarketParams memory marketParams)
        public
        view
        returns (uint256 allocation)
    {
        allocation = IMorphoMarketV1Adapter(adapter).allocation(marketParams);
    }

    /// @notice Returns the effective cap for a specific `id` in a VaultV2 `vault`.
    /// @dev The effective cap is the minimum of the absolute cap and the relative cap applied to total assets.
    /// @dev This represents the actual maximum allocation that can be made to markets with this ID.
    /// @param vault The address of the VaultV2 vault.
    /// @param idData The raw bytes data representing the ID (will be hashed to get the actual ID).
    /// @return effectiveCap The effective cap (minimum of absolute and relative caps).
    function effectiveCapById(address vault, bytes memory idData) public view returns (uint256 effectiveCap) {
        bytes32 id = keccak256(idData);
        uint256 absoluteCap = IVaultV2(vault).absoluteCap(id);
        uint256 relativeCap = IVaultV2(vault).relativeCap(id);
        uint256 totalAssets = IVaultV2(vault).totalAssets();

        uint256 relativeCapInAssets = relativeCap.mulDiv(totalAssets, WAD);
        effectiveCap = Math.min(absoluteCap, relativeCapInAssets);
    }

    /// @notice Returns the current supply APY of a Morpho Blue market.
    /// @dev This is the same calculation as in MetaMorphoSnippets for consistency.
    /// @param marketParams The morpho blue market parameters.
    /// @param market The morpho blue market state.
    /// @return supplyApy The annualized supply APY (in WAD, 1e18 = 100%).
    function supplyAPYMarket(MarketParams memory marketParams, Market memory market)
        public
        view
        returns (uint256 supplyApy)
    {
        // Get the borrow rate
        uint256 borrowRate;
        if (marketParams.irm == address(0)) {
            return 0;
        } else {
            borrowRate = IIrm(marketParams.irm).borrowRateView(marketParams, market).wTaylorCompounded(365 days);
        }

        (uint256 totalSupplyAssets,, uint256 totalBorrowAssets,) = morpho.expectedMarketBalances(marketParams);

        // Get the supply rate
        uint256 utilization = (totalBorrowAssets == 0 || totalSupplyAssets == 0) ? 0 : totalBorrowAssets.wDivUp(totalSupplyAssets);

        supplyApy = borrowRate.wMulDown(WAD - market.fee).wMulDown(utilization);
    }

    /// @notice Returns the current supply APY of a Morpho Market adapter.
    /// @dev This is calculated as the weighted average APY across all markets the adapter is allocated to.
    /// @param adapter The address of the Morpho Market adapter.
    /// @return avgSupplyApy The weighted average supply APY of the adapter (in WAD, 1e18 = 100%).
    function supplyAPYAdapter(address adapter) public view returns (uint256 avgSupplyApy) {
        uint256 totalAdapterAssets = IAdapter(adapter).realAssets();
        if (totalAdapterAssets == 0) return 0;

        uint256 length = IMorphoMarketV1Adapter(adapter).marketParamsListLength();
        uint256 weightedSum;

        for (uint256 i; i < length; ++i) {
            (address loanToken, address collateralToken, address oracle, address irm, uint256 lltv) =
                IMorphoMarketV1Adapter(adapter).marketParamsList(i);

            MarketParams memory marketParams = MarketParams({
                loanToken: loanToken,
                collateralToken: collateralToken,
                oracle: oracle,
                irm: irm,
                lltv: lltv
            });

            Id marketId = marketParams.id();
            Market memory market = morpho.market(marketId);

            uint256 marketAllocation = IMorphoMarketV1Adapter(adapter).allocation(marketParams);
            uint256 currentSupplyAPY = supplyAPYMarket(marketParams, market);

            weightedSum += currentSupplyAPY.wMulDown(marketAllocation);
        }

        avgSupplyApy = weightedSum.mulDivDown(WAD, totalAdapterAssets);
    }

    /// @notice Returns the current supply APY of a VaultV2 vault.
    /// @dev This is calculated as the weighted average APY across all adapters, accounting for fees.
    /// @dev Only works with Morpho Market adapters. For other adapter types, their contribution is skipped.
    /// @param vault The address of the VaultV2 vault.
    /// @return avgSupplyApy The weighted average supply APY of the vault after fees (in WAD, 1e18 = 100%).
    function supplyAPYVaultV2(address vault) public view returns (uint256 avgSupplyApy) {
        uint256 totalAssets = IVaultV2(vault).totalAssets();
        if (totalAssets == 0) return 0;

        uint256 adapterCount = IVaultV2(vault).adaptersLength();
        uint256 weightedSum;

        for (uint256 i; i < adapterCount; ++i) {
            address adapter = IVaultV2(vault).adapters(i);

            // Try to treat as Morpho Market adapter
            try IMorphoMarketV1Adapter(adapter).marketParamsListLength() returns (uint256) {
                uint256 adapterAssets = IAdapter(adapter).realAssets();
                uint256 adapterAPY = supplyAPYAdapter(adapter);
                weightedSum += adapterAPY.wMulDown(adapterAssets);
            } catch {
                // If not a Morpho Market adapter, skip (could be other adapter type)
                continue;
            }
        }

        // Apply performance fee (performance fee is taken on the yield)
        uint96 performanceFee = IVaultV2(vault).performanceFee();
        avgSupplyApy = weightedSum.mulDivDown(WAD - performanceFee, totalAssets);
    }

    // --- MANAGING FUNCTIONS ---

    /// @notice Deposits `assets` into the `vault` on behalf of `onBehalf`.
    /// @dev Sender must approve the snippets contract to manage their tokens before the call.
    /// @dev The vault must allow the sender to send assets (checked via sendAssetsGate if configured).
    /// @dev The `onBehalf` address must be allowed to receive shares (checked via receiveSharesGate if configured).
    /// @param vault The address of the VaultV2 vault.
    /// @param assets The amount of assets to deposit.
    /// @param onBehalf The address that will receive the minted shares.
    /// @return shares The amount of shares minted.
    function depositInVault(address vault, uint256 assets, address onBehalf) public returns (uint256 shares) {
        address asset = IVaultV2(vault).asset();
        IERC20(asset).transferFrom(msg.sender, address(this), assets);

        _approveMaxVault(vault);

        shares = IVaultV2(vault).deposit(assets, onBehalf);
    }

    /// @notice Mints exactly `shares` from the `vault` on behalf of `onBehalf`.
    /// @dev Sender must approve the snippets contract to manage their tokens before the call.
    /// @dev The vault must allow the sender to send assets (checked via sendAssetsGate if configured).
    /// @dev The `onBehalf` address must be allowed to receive shares (checked via receiveSharesGate if configured).
    /// @param vault The address of the VaultV2 vault.
    /// @param shares The exact amount of shares to mint.
    /// @param onBehalf The address that will receive the minted shares.
    /// @return assets The amount of assets deposited.
    function mintInVault(address vault, uint256 shares, address onBehalf) public returns (uint256 assets) {
        assets = IVaultV2(vault).previewMint(shares);

        address asset = IVaultV2(vault).asset();
        IERC20(asset).transferFrom(msg.sender, address(this), assets);

        _approveMaxVault(vault);

        IVaultV2(vault).mint(shares, onBehalf);
    }

    /// @notice Withdraws `assets` from the `vault` on behalf of the sender, and sends them to `receiver`.
    /// @dev Sender must approve the snippets contract to manage their shares before the call (if not withdrawing own shares).
    /// @dev The sender must be allowed to send shares (checked via sendSharesGate if configured).
    /// @dev The `receiver` must be allowed to receive assets (checked via receiveAssetsGate if configured).
    /// @param vault The address of the VaultV2 vault.
    /// @param assets The amount of assets to withdraw.
    /// @param receiver The address that will receive the withdrawn assets.
    /// @param owner The address that owns the shares being redeemed.
    /// @return shares The amount of shares burned.
    function withdrawFromVault(address vault, uint256 assets, address receiver, address owner)
        public
        returns (uint256 shares)
    {
        shares = IVaultV2(vault).withdraw(assets, receiver, owner);
    }

    /// @notice Redeems `shares` from the `vault`, and sends the withdrawn assets to `receiver`.
    /// @dev Sender must approve the snippets contract to manage their shares before the call (if not redeeming own shares).
    /// @dev The sender must be allowed to send shares (checked via sendSharesGate if configured).
    /// @dev The `receiver` must be allowed to receive assets (checked via receiveAssetsGate if configured).
    /// @param vault The address of the VaultV2 vault.
    /// @param shares The amount of shares to redeem.
    /// @param receiver The address that will receive the withdrawn assets.
    /// @param owner The address that owns the shares being redeemed.
    /// @return assets The amount of assets withdrawn.
    function redeemFromVault(address vault, uint256 shares, address receiver, address owner)
        public
        returns (uint256 assets)
    {
        assets = IVaultV2(vault).redeem(shares, receiver, owner);
    }

    /// @notice Redeems all shares owned by the sender from the `vault`, and sends the withdrawn assets to `receiver`.
    /// @dev Convenient function to exit the vault completely.
    /// @dev The sender must be allowed to send shares (checked via sendSharesGate if configured).
    /// @dev The `receiver` must be allowed to receive assets (checked via receiveAssetsGate if configured).
    /// @param vault The address of the VaultV2 vault.
    /// @param receiver The address that will receive the withdrawn assets.
    /// @return assets The amount of assets withdrawn.
    function redeemAllFromVault(address vault, address receiver) public returns (uint256 assets) {
        uint256 shares = IVaultV2(vault).balanceOf(msg.sender);
        assets = IVaultV2(vault).redeem(shares, receiver, msg.sender);
    }

    /// @notice Accrues interest on the vault, updating total assets and minting fee shares.
    /// @dev Interest is accrued based on adapter reported values and is capped by the maxRate.
    /// @dev Performance fees are taken on interest, management fees are taken on total assets over time.
    /// @param vault The address of the VaultV2 vault.
    function accrueInterestVault(address vault) public {
        IVaultV2(vault).accrueInterest();
    }

    // --- INTERNAL HELPERS ---

    /// @notice Approves the vault to spend the maximum amount of the underlying asset if not already approved.
    /// @dev This is an internal helper to avoid repeated approvals.
    /// @param vault The address of the VaultV2 vault.
    function _approveMaxVault(address vault) internal {
        address asset = IVaultV2(vault).asset();
        if (IERC20(asset).allowance(address(this), vault) == 0) {
            IERC20(asset).approve(vault, type(uint256).max);
        }
    }
}

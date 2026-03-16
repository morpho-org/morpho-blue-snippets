// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IVaultV2Factory} from "../../lib/vault-v2/src/interfaces/IVaultV2Factory.sol";
import {IVaultV2} from "../../lib/vault-v2/src/interfaces/IVaultV2.sol";
import {IMorphoVaultV1AdapterFactory} from "../../lib/vault-v2/src/adapters/interfaces/IMorphoVaultV1AdapterFactory.sol";
import {MAX_MAX_RATE, MAX_FORCE_DEALLOCATE_PENALTY, WAD} from "../../lib/vault-v2/src/libraries/ConstantsLib.sol";

/// @title FeeWrapperDeployer
/// @notice Deploys and configures a VaultV2 "fee wrapper" on top of an existing Morpho Vault V2 child vault.
///
/// A fee wrapper is a VaultV2 that wraps a single child vault via a fixed MorphoVaultV1Adapter.
/// Users deposit into the fee wrapper, which routes funds to the child vault. The wrapper owner
/// charges performance and/or management fees on the yield.
///
/// IMPORTANT: The child vault MUST be a Morpho Vault V2. Do not deploy fee wrappers on Morpho Vault V1 instances.
/// The adapter name "MorphoVaultV1Adapter" is a legacy naming artifact; the adapter is ERC4626-compatible,
/// but V2 is the only audited and recommended configuration.
///
/// ---- What is FIXED at deployment (cannot be changed after) ----
///
///   - addAdapter:     ABDICATED (the single adapter pointing to the child vault is permanent)
///   - removeAdapter:  ABDICATED (the adapter cannot be removed)
///
/// ---- What is set to RECOMMENDED DEFAULTS ----
///
///   - Absolute cap:              type(uint128).max (no restriction)
///   - Relative cap:              WAD / 100% (all funds can flow to the child vault)
///   - Max rate:                  MAX_MAX_RATE / 200% APR (does not artificially cap child vault returns)
///   - Force deallocate penalty:  MAX_FORCE_DEALLOCATE_PENALTY / 2% (disincentivizes forceAllocate spam)
///   - Liquidity adapter:         The MorphoVaultV1Adapter with empty data
///   - Allocator:                 The owner
///   - Sentinel:                  The owner
///   - Curator:                   The owner
///
/// ---- What is CONFIGURABLE by the deployer ----
///
///   - owner:                     The final owner of the fee wrapper (MUST be a safe wallet, e.g. multisig)
///   - name / symbol:             The ERC20 name and symbol of the fee wrapper token
///   - performanceFee:            Performance fee (in WAD, max 50%). Set to 0 to skip.
///   - managementFee:             Management fee (in WAD per second, max ~5% APR). Set to 0 to skip.
///   - feeRecipient:              The address receiving both performance and management fees
///   - abdicateNonCriticalGates:  If true, permanently abdicates 3 gate setters (receiveShares, sendShares,
///                                receiveAssets) to guarantee non-custodial operation. The sendAssets gate is
///                                not abdicated because it is non-critical (cannot lock user funds).
///                                See "Gates & Non-Custodiality" below.
///
/// ---- Gates & Non-Custodiality ----
///
///   By default, all four gates are set to address(0) (disabled / permissionless).
///   This means anyone can deposit, withdraw, and transfer freely.
///
///   For NON-CUSTODIAL guarantees: set abdicateNonCriticalGates = true.
///   This permanently locks the three critical gates to address(0), ensuring no one can ever
///   restrict deposits, withdrawals, or transfers. This is the recommended setup for DeFi-native
///   deployments where trustless access matters.
///
///   For COMPLIANCE use cases (e.g. KYC/AML allowlists, Fireblocks, institutional mandates):
///   leave abdicateNonCriticalGates = false. The owner/curator retains the ability to set gates
///   later via the timelock mechanism. Be aware this makes the vault partially custodial.
///
/// ---- Roles & Responsibilities ----
///
///   Owner:     Full control. Sets curator, sentinels, name/symbol. Must be a secure wallet.
///              The owner carries real operational responsibility. Do NOT use a personal hot wallet.
///   Curator:   Same as owner. Sets fees, gates, caps, allocators, timelocks, adapter registry.
///   Allocator: Same as owner. Rebalances liquidity, sets liquidity adapter and max rate.
///   Sentinel:  Same as owner (or a dedicated monitoring bot). Emergency fund recovery: if the
///              child vault is compromised, the sentinel can set caps to zero and deallocate
///              funds back to idle. Do NOT skip this role.
///
/// ---- Auth Model Recap ----
///
///   Owner functions (no timelock):  setOwner, setCurator, setIsSentinel, setName, setSymbol
///   Curator functions (timelocked): addAdapter, removeAdapter, abdicate, setIsAllocator,
///                                   set*Gate, increaseAbsoluteCap, increaseRelativeCap,
///                                   setPerformanceFee, setManagementFee, set*FeeRecipient,
///                                   setForceDeallocatePenalty, increaseTimelock, decreaseTimelock,
///                                   setAdapterRegistry
///   Allocator functions (no timelock): allocate, deallocate, setLiquidityAdapterAndData, setMaxRate
///
///   At vault creation, all timelocks are 0. This allows the deployer to submit + execute
///   curator functions atomically in the same transaction.
contract FeeWrapperDeployer {
    /// @notice Configuration for a fee wrapper deployment.
    struct FeeWrapperConfig {
        // ---- Required ----
        address owner; // Final owner. MUST be a safe wallet (multisig, institutional, etc.).
        bytes32 salt; // CREATE2 salt for deterministic deployment.
        address childVault; // The underlying Morpho Vault V2 to wrap. MUST be a V2 vault.
        // ---- Token metadata ----
        string name; // ERC20 name for the fee wrapper token. Can be empty (settable later by owner).
        string symbol; // ERC20 symbol for the fee wrapper token. Can be empty (settable later by owner).
        // ---- Fees (optional, can be configured later by curator) ----
        uint256 performanceFee; // Performance fee in WAD (e.g. 0.1e18 = 10%). Set to 0 to skip.
        uint256 managementFee; // Management fee in WAD/second (e.g. ~1.585e9 for ~5% APR). Set to 0 to skip.
        address feeRecipient; // Address receiving fees. Required if either fee > 0.
        // ---- Non-custodiality option ----
        bool abdicateNonCriticalGates; // If true, abdicate 3 gate setters for non-custodial guarantees.
    }

    /// @notice Deploys and fully configures a fee wrapper VaultV2.
    /// @param morphoVaultV2Factory The VaultV2Factory address.
    /// @param morphoVaultV1AdapterFactory The MorphoVaultV1AdapterFactory address.
    /// @param config The fee wrapper configuration.
    /// @return vault The address of the deployed fee wrapper vault.
    function createFeeWrapper(
        address morphoVaultV2Factory,
        address morphoVaultV1AdapterFactory,
        FeeWrapperConfig calldata config
    ) external returns (address vault) {
        // =====================================================================
        //  PHASE 1: VAULT CREATION
        //  The deployer contract becomes temporary owner so it can configure
        //  everything atomically. Ownership is transferred at the very end.
        // =====================================================================

        // Verify the child vault is a Morpho Vault V2 created by the canonical factory.
        // This prevents wrapping V1 vaults or arbitrary ERC4626 contracts, which are
        // outside the audited configuration.
        require(
            IVaultV2Factory(morphoVaultV2Factory).isVaultV2(config.childVault),
            "FeeWrapperDeployer: child vault must be a Morpho Vault V2"
        );

        // Create the wrapper vault. The deployer is the initial owner.
        vault = IVaultV2Factory(morphoVaultV2Factory).createVaultV2(
            address(this), // temporary owner = this deployer
            IVaultV2(config.childVault).asset(), // same asset as child vault
            config.salt
        );

        // Make the deployer the curator so it can submit + execute timelocked functions.
        // (setCurator is an owner function, no timelock needed.)
        IVaultV2(vault).setCurator(address(this));

        // =====================================================================
        //  PHASE 2: ADAPTER SETUP (curator functions: submit + execute)
        //  Create the adapter, add it, then permanently lock the adapter config
        //  by abdicating addAdapter and removeAdapter.
        // =====================================================================

        // Create the MorphoVaultV1Adapter pointing to the child vault.
        // Despite the "V1" naming, this adapter is ERC4626-compatible and works with V2 child vaults.
        address adapter = IMorphoVaultV1AdapterFactory(morphoVaultV1AdapterFactory).createMorphoVaultV1Adapter(
            vault, config.childVault
        );

        // The adapter's id data, used for cap configuration.
        // This matches the adapterId computed inside the MorphoVaultV1Adapter constructor:
        //   adapterId = keccak256(abi.encode("this", address(this)))
        bytes memory adapterIdData = abi.encode("this", adapter);

        // Add the adapter to the vault (timelocked, but timelock is 0 at creation).
        IVaultV2(vault).submit(abi.encodeCall(IVaultV2.addAdapter, (adapter)));
        IVaultV2(vault).addAdapter(adapter);

        // Permanently abdicate addAdapter: no new adapters can ever be added.
        IVaultV2(vault).submit(abi.encodeCall(IVaultV2.abdicate, (IVaultV2.addAdapter.selector)));
        IVaultV2(vault).abdicate(IVaultV2.addAdapter.selector);

        // Permanently abdicate removeAdapter: the existing adapter can never be removed.
        // Together with addAdapter abdication, this guarantees the fee wrapper will always
        // point to the same child vault.
        IVaultV2(vault).submit(abi.encodeCall(IVaultV2.abdicate, (IVaultV2.removeAdapter.selector)));
        IVaultV2(vault).abdicate(IVaultV2.removeAdapter.selector);

        // =====================================================================
        //  PHASE 3: ALLOCATOR SETUP (curator functions: submit + execute)
        //  The deployer needs to be an allocator to call setLiquidityAdapterAndData
        //  and setMaxRate in Phase 5. The final owner also becomes an allocator.
        // =====================================================================

        // Make the deployer a temporary allocator (needed for Phase 5).
        IVaultV2(vault).submit(abi.encodeCall(IVaultV2.setIsAllocator, (address(this), true)));
        IVaultV2(vault).setIsAllocator(address(this), true);

        // Make the final owner an allocator (permanent).
        IVaultV2(vault).submit(abi.encodeCall(IVaultV2.setIsAllocator, (config.owner, true)));
        IVaultV2(vault).setIsAllocator(config.owner, true);

        // =====================================================================
        //  PHASE 4: CAPS CONFIGURATION (curator functions: submit + execute)
        //  Set caps to maximum so the fee wrapper imposes no additional restriction
        //  beyond what the child vault itself enforces.
        // =====================================================================

        // Absolute cap = type(uint128).max: no limit on how many assets can be allocated.
        IVaultV2(vault).submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (adapterIdData, type(uint128).max)));
        IVaultV2(vault).increaseAbsoluteCap(adapterIdData, type(uint128).max);

        // Relative cap = WAD (100%): all assets can flow to the child vault.
        IVaultV2(vault).submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (adapterIdData, WAD)));
        IVaultV2(vault).increaseRelativeCap(adapterIdData, WAD);

        // =====================================================================
        //  PHASE 5: ALLOCATOR CONFIGURATION (allocator functions, no timelock)
        //  These require isAllocator[msg.sender], which we set in Phase 3.
        // =====================================================================

        // Set the liquidity adapter so deposits/withdrawals are automatically routed
        // through the adapter to the child vault. Empty data (hex"") because the
        // MorphoVaultV1Adapter expects zero-length data.
        IVaultV2(vault).setLiquidityAdapterAndData(adapter, hex"");

        // Set max rate to 200% APR. This avoids artificially capping returns from the
        // child vault. The max rate limits how fast the share price can increase per
        // second, protecting against donation-based manipulation.
        IVaultV2(vault).setMaxRate(MAX_MAX_RATE);

        // =====================================================================
        //  PHASE 6: PENALTY CONFIGURATION (curator function: submit + execute)
        //  Set the forceAllocate penalty to 2% (MAX_FORCE_DEALLOCATE_PENALTY).
        //  This disincentivizes forceAllocate spam: an attacker loses 2% each time
        //  they call forceDeallocate, making it economically irrational.
        // =====================================================================

        IVaultV2(vault).submit(
            abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (adapter, MAX_FORCE_DEALLOCATE_PENALTY))
        );
        IVaultV2(vault).setForceDeallocatePenalty(adapter, MAX_FORCE_DEALLOCATE_PENALTY);

        // =====================================================================
        //  PHASE 7: OPTIONAL FEES (curator functions: submit + execute)
        //  Fee recipients must be set BEFORE fees, because the vault enforces:
        //    fee != 0 => recipient != address(0)
        //  If fees are 0, this phase is skipped entirely.
        // =====================================================================

        if (config.performanceFee > 0) {
            // Set recipient first (fee is still 0, so the recipient invariant is satisfied).
            IVaultV2(vault).submit(
                abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (config.feeRecipient))
            );
            IVaultV2(vault).setPerformanceFeeRecipient(config.feeRecipient);

            // Now set the fee (recipient is already set).
            IVaultV2(vault).submit(abi.encodeCall(IVaultV2.setPerformanceFee, (config.performanceFee)));
            IVaultV2(vault).setPerformanceFee(config.performanceFee);
        }

        if (config.managementFee > 0) {
            // Set recipient first.
            IVaultV2(vault).submit(
                abi.encodeCall(IVaultV2.setManagementFeeRecipient, (config.feeRecipient))
            );
            IVaultV2(vault).setManagementFeeRecipient(config.feeRecipient);

            // Now set the fee.
            IVaultV2(vault).submit(abi.encodeCall(IVaultV2.setManagementFee, (config.managementFee)));
            IVaultV2(vault).setManagementFee(config.managementFee);
        }

        // =====================================================================
        //  PHASE 8: OPTIONAL NON-CUSTODIAL GATES (curator functions: submit + execute)
        //
        //  By default, all gates are address(0) (permissionless). Abdicating the gate
        //  setters permanently locks them to address(0), guaranteeing that no one can
        //  ever restrict deposits, withdrawals, or transfers.
        //
        //  Three gates are abdicated (the "critical" ones that can lock user funds):
        //    - setReceiveSharesGate:  controls who can receive shares (deposit/transfer)
        //    - setSendSharesGate:     controls who can send shares (withdraw/transfer)
        //    - setReceiveAssetsGate:  controls who can receive assets (withdraw)
        //
        //  The fourth gate (setSendAssetsGate) is NOT abdicated because it is non-critical:
        //  it can only restrict who deposits, but cannot lock existing user funds.
        //
        //  If you need compliance gates (KYC/AML), leave abdicateNonCriticalGates = false
        //  and configure gates later via the curator + timelock mechanism.
        // =====================================================================

        if (config.abdicateNonCriticalGates) {
            IVaultV2(vault).submit(abi.encodeCall(IVaultV2.abdicate, (IVaultV2.setReceiveSharesGate.selector)));
            IVaultV2(vault).abdicate(IVaultV2.setReceiveSharesGate.selector);

            IVaultV2(vault).submit(abi.encodeCall(IVaultV2.abdicate, (IVaultV2.setSendSharesGate.selector)));
            IVaultV2(vault).abdicate(IVaultV2.setSendSharesGate.selector);

            IVaultV2(vault).submit(abi.encodeCall(IVaultV2.abdicate, (IVaultV2.setReceiveAssetsGate.selector)));
            IVaultV2(vault).abdicate(IVaultV2.setReceiveAssetsGate.selector);
        }

        // =====================================================================
        //  PHASE 9: TOKEN METADATA (owner functions, no timelock)
        // =====================================================================

        if (bytes(config.name).length > 0) {
            IVaultV2(vault).setName(config.name);
        }
        if (bytes(config.symbol).length > 0) {
            IVaultV2(vault).setSymbol(config.symbol);
        }

        // =====================================================================
        //  PHASE 10: OWNERSHIP TRANSFER
        //  Remove the deployer's temporary privileges and hand everything over
        //  to the final owner.
        //
        //  Order matters here:
        //    1. Remove deployer as allocator (curator function, deployer is still curator)
        //    2. Set sentinel for owner (owner function, deployer is still owner)
        //    3. Transfer curator to owner (owner function, deployer is still owner)
        //    4. Transfer ownership to owner (owner function, MUST BE LAST)
        //
        //  After step 4, the deployer has zero privileges on the vault.
        // =====================================================================

        // 1. Remove the deployer as allocator (curator function: submit + execute).
        IVaultV2(vault).submit(abi.encodeCall(IVaultV2.setIsAllocator, (address(this), false)));
        IVaultV2(vault).setIsAllocator(address(this), false);

        // 2. Set the owner as sentinel.
        //    The sentinel can deallocate funds in emergencies (e.g. child vault compromised).
        //    This is a critical safety role. Do NOT skip.
        IVaultV2(vault).setIsSentinel(config.owner, true);

        // 3. Transfer curator role to the final owner.
        IVaultV2(vault).setCurator(config.owner);

        // 4. Transfer ownership. THIS MUST BE THE LAST CALL.
        //    After this, the deployer contract has no privileges on the vault.
        IVaultV2(vault).setOwner(config.owner);
    }
}

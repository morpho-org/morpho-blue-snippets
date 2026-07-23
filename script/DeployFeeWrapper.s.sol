// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {FeeWrapperDeployer} from "../src/vault-v2/FeeWrapperDeployer.sol";
import {IVaultV2Factory} from "../lib/vault-v2/src/interfaces/IVaultV2Factory.sol";
import {IVaultV2} from "../lib/vault-v2/src/interfaces/IVaultV2.sol";

/// @notice Sanctioned deployment path for a VaultV2 fee wrapper.
///
/// @dev WHY A SCRIPT (and not an ad-hoc contract call):
/// The deterministic (CREATE2) address of a fee wrapper is bound to the caller that creates it —
/// the effective salt is keccak256(abi.encode(msg.sender, owner, childVault, salt)). This is what
/// prevents mempool front-runners from squatting a victim's pre-computed address. As a direct
/// consequence, the address is only meaningful relative to a KNOWN, PINNED deployer. This script
/// pins that deployer (the broadcaster), logs the resulting deterministic address, and verifies
/// on-chain provenance so deployments stay reproducible and auditable. Always deploy fee wrappers
/// through this script — never by calling FeeWrapperDeployer.createFeeWrapper from unpinned tooling
/// or from another contract.
///
/// @dev USAGE (all values are read from the environment):
///   # Required
///   export MORPHO_VAULT_V2_FACTORY=0x...            # canonical VaultV2Factory
///   export MORPHO_VAULT_V1_ADAPTER_FACTORY=0x...    # canonical MorphoVaultV1AdapterFactory
///   export FW_OWNER=0x...                           # final owner (MUST be a safe wallet / multisig)
///   export FW_CHILD_VAULT=0x...                     # child vault to wrap (MUST be a Morpho Vault V2)
///   export FW_SALT=0x0000...0001                    # user entropy (bytes32)
///   # Optional
///   export FW_DEPLOYER=0x...                        # reuse an existing FeeWrapperDeployer singleton
///   export FW_NAME="Fee Wrapped Vault"
///   export FW_SYMBOL="fwVAULT"
///   export FW_PERFORMANCE_FEE=0                      # WAD, e.g. 100000000000000000 = 10%
///   export FW_MANAGEMENT_FEE=0                       # WAD per second
///   export FW_FEE_RECIPIENT=0x...                    # required if either fee > 0
///   export FW_ABDICATE_GATES=false                   # true for non-custodial guarantees
///
///   forge script script/DeployFeeWrapper.s.sol:DeployFeeWrapper --rpc-url <rpc> --broadcast
///
/// Run without --broadcast first to see the deterministic address and the full plan (dry run).
contract DeployFeeWrapper is Script {
    function run() external returns (address vault) {
        // ---- Required inputs ----
        address vaultV2Factory = vm.envAddress("MORPHO_VAULT_V2_FACTORY");
        address adapterFactory = vm.envAddress("MORPHO_VAULT_V1_ADAPTER_FACTORY");

        FeeWrapperDeployer.FeeWrapperConfig memory config = FeeWrapperDeployer.FeeWrapperConfig({
            owner: vm.envAddress("FW_OWNER"),
            salt: vm.envBytes32("FW_SALT"),
            childVault: vm.envAddress("FW_CHILD_VAULT"),
            name: vm.envOr("FW_NAME", string("")),
            symbol: vm.envOr("FW_SYMBOL", string("")),
            performanceFee: vm.envOr("FW_PERFORMANCE_FEE", uint256(0)),
            managementFee: vm.envOr("FW_MANAGEMENT_FEE", uint256(0)),
            feeRecipient: vm.envOr("FW_FEE_RECIPIENT", address(0)),
            abdicateNonCriticalGates: vm.envOr("FW_ABDICATE_GATES", false)
        });

        // The broadcaster is the pinned deployer. It is part of the CREATE2 salt, so it fully
        // determines (together with the config) the fee wrapper's address.
        address broadcaster = msg.sender;

        vm.startBroadcast();

        // Reuse an existing deployer singleton if provided, otherwise deploy a fresh one.
        FeeWrapperDeployer deployer;
        if (vm.envOr("FW_DEPLOYER", address(0)) != address(0)) {
            deployer = FeeWrapperDeployer(vm.envAddress("FW_DEPLOYER"));
        } else {
            deployer = new FeeWrapperDeployer();
            console.log("Deployed new FeeWrapperDeployer at:", address(deployer));
        }

        // The effective CREATE2 salt that will be used, bound to (broadcaster, owner, childVault, salt).
        bytes32 effectiveSalt = deployer.feeWrapperSalt(broadcaster, config.owner, config.childVault, config.salt);

        vault = deployer.createFeeWrapper(vaultV2Factory, adapterFactory, config);

        vm.stopBroadcast();

        // ---- Perfected CREATE2 info: verify the deployed address matches the bound salt ----
        // The factory records vaultV2[initialOwner][asset][salt]; initialOwner is the deployer
        // contract and salt is the effective (bound) salt. If these do not agree, something in the
        // deployment path diverged from the expected CREATE2 derivation and must be investigated.
        address asset = IVaultV2(config.childVault).asset();
        address expected = IVaultV2Factory(vaultV2Factory).vaultV2(address(deployer), asset, effectiveSalt);
        require(expected == vault, "DeployFeeWrapper: CREATE2 address mismatch");
        require(IVaultV2Factory(vaultV2Factory).isVaultV2(vault), "DeployFeeWrapper: not a registered VaultV2");
        require(IVaultV2(vault).owner() == config.owner, "DeployFeeWrapper: unexpected owner");

        console.log("===== Fee Wrapper Deployed =====");
        console.log("Deployer (pinned CREATE2 sender):", broadcaster);
        console.log("FeeWrapperDeployer:", address(deployer));
        console.log("Child vault:", config.childVault);
        console.log("Asset:", asset);
        console.log("Final owner:", config.owner);
        console.logBytes32(config.salt);
        console.log("Effective (bound) salt:");
        console.logBytes32(effectiveSalt);
        console.log("Fee wrapper vault (deterministic address):", vault);
    }
}

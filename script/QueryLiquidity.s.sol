// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {VaultV2LiquidityLens} from "../src/vault-v2/VaultV2LiquidityLib.sol";

/// @notice Script to deploy the VaultV2LiquidityLens and query vaults
/// @dev Usage: forge script script/QueryLiquidity.s.sol --rpc-url base --broadcast
contract DeployLens is Script {
    function run() external {
        vm.startBroadcast();

        VaultV2LiquidityLens lens = new VaultV2LiquidityLens();
        console.log("VaultV2LiquidityLens deployed at:", address(lens));

        vm.stopBroadcast();
    }
}

/// @notice Script to query liquidity for a vault (dry-run, no broadcast needed)
/// @dev Usage: forge script script/QueryLiquidity.s.sol:QueryVault --rpc-url base -vvv --sig "run(address,address)" <vault> <owner>
contract QueryVault is Script {
    function run(address vault, address owner) external {
        // Deploy lens locally for the query (doesn't need to be deployed on-chain)
        VaultV2LiquidityLens lens = new VaultV2LiquidityLens();

        console.log("===== VaultV2 Liquidity Query =====");
        console.log("Vault:", vault);
        console.log("Owner:", owner);
        console.log("");

        uint256 liquidity = lens.availableLiquidity(vault);
        console.log("Available Liquidity:", liquidity);

        uint256 maxWithdraw = lens.maxWithdraw(vault, owner);
        console.log("Max Withdraw:", maxWithdraw);

        uint256 maxRedeem = lens.maxRedeem(vault, owner);
        console.log("Max Redeem:", maxRedeem);
    }
}

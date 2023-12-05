# Morpho-Blue snippets

## Typescript & Solidity based snippets related to Morpho Protocols.

IMPORTANT
This repository contains smart contracts that have been developed for educational, experimental, or demonstration purposes only. By using or interacting with these smart contracts, you acknowledge and accept the following:

1. The smart contracts in this repository have not been audited and are provided "as is" with no guarantees, warranties, or assurances of any kind. The authors and maintainers of this repository are not responsible for any damages, losses, or liabilities that may arise from the use or deployment of these smart contracts.

2. The smart contracts in this repository are not intended for use in production environments or for the management of real-world assets, funds, or resources. Any use or deployment of these smart contracts for such purposes is done entirely at your own risk.

3. The smart contracts are provided for reference and learning purposes, and you are solely responsible for understanding, modifying, and deploying them as needed.

## Morpho-Blue related functions in Solidity:

One can use the logic provided in the following:

1. functions to get data:

- supplyAPY
- borrowAPY
- supplyAssetsUser
- borrowAssetsUser
- collateralAssetsUser
- marketTotalSupply
- marketTotalBorrow
- userHealthFactor

2. functions to modify state:

- supply
- supplyCollateral
- withdrawCollateral
- withdrawAmount
- withdraw50Percent
- withdrawAll

3. functions using callbacks:

- leverageMe
- deLeverageMe

## MetaMorpho related functions in Solidity:

One can use the logic provided in the following:

1. functions to get data:

- totalDepositVault
- vaultAssetsInMarket
- totalSharesUserVault
- supplyQueueVault
- withdrawQueueVault
- totalCapCollateral
- supplyAPYMarket
- supplyAPYVault

2. functions to modify state

- depositInVault
- withdrawFromVaultAmount
- redeemAllFromVault

## Getting Started

- Install Foundry.
- Install yarn
- Run foundryup
- Run forge install
- Create a .env file according to the .env.example file.

## Testing with Foundry 🔨

You can run the test by running the command:

```bash
forge test
```

Questions & Feedback
For any question or feedback you can send an email to merlin@morpho.xyz.

Licensing
The code is under the MIT License. See License.

# Morpho-Blue-Snippets

## Solidity & Typescript based snippets related to Morpho Blue Protocol.

## IMPORTANT

This repository contains smart contracts that have been developed for educational, experimental, or demonstration purposes only. By using or interacting with these smart contracts, you acknowledge and accept the following:

- The smart contracts in this repository have not been audited and are provided "as is" with no guarantees, warranties, or assurances of any kind. The authors and maintainers of this repository are not responsible for any damages, losses, or liabilities that may arise from the use or deployment of these smart contracts.

- The smart contracts in this repository are not intended for use in production environments or for the management of real-world assets, funds, or resources. Any use or deployment of these smart contracts for such purposes is done entirely at your own risk.

- The smart contracts are provided for reference and learning purposes, and you are solely responsible for understanding, modifying, and deploying them as needed.

### Morpho-Blue related functions, in Solidity.

One can use one of the following functions to get relevant data:

View Functions:

- supplyAPR
- borrowAPR

- supplyBalance
- collateralBalance
- borrowBalance

- marketTotalSupply
- marketTotalBorrow

- userHealthFactor

State-Changing Functions:

- supply
- supplyCollateral

- withdrawCollateral
- withdrawAmount
- withdraw50Percent
- withdrawAll

- borrow

- repayAmount
- repay50Percent
- repayAll

Some libraries were used in the snippets. You can visit them here: [periphery](https://github.com/morpho-org/morpho-blue/tree/main/src/libraries/periphery) to have a look at all the data available from the Morpho Contract.

### Morpho-Blue related functions in Typescript.

[INCOMING]

### Getting Started

- Install [Foundry](https://github.com/foundry-rs/foundry).
- Install yarn
- Run foundryup
- Run forge install
- Create a `.env` file according to the [`.env.example`](./.env.example) file.

### Testing with [Foundry](https://github.com/foundry-rs/foundry) 🔨

Tests are run against a fork of real networks, which allows us to interact directly with liquidity pools of Aave V3. Note that you need to have an RPC provider that have access to Ethereum.

You can run the test by running the command: `forge test`

### VSCode setup

Configure your VSCode to automatically format a file on save, using `forge fmt`:

- Install [emeraldwalk.runonsave](https://marketplace.visualstudio.com/items?itemName=emeraldwalk.RunOnSave)
- Update your `settings.json`:

```json
{
  "[solidity]": {
    "editor.formatOnSave": false
  },
  "emeraldwalk.runonsave": {
    "commands": [
      {
        "match": ".sol",
        "isAsync": true,
        "cmd": "forge fmt ${file}"
      }
    ]
  }
}
```

## Questions & Feedback

For any question or feedback you can send an email to [tom@morpho.xyz](mailto:tom@morpho.xyz).

---

## Licensing

The code is under the GNU AFFERO GENERAL PUBLIC LICENSE v3.0, see [`LICENSE`](./LICENSE).

# Morpho Blue Snippets

## Typescript & Solidity based snippets related to Morpho Protocols

> [!IMPORTANT]
> This repository contains smart contracts that have been developed for educational, experimental, or demonstration purposes only.
By using or interacting with these smart contracts, you acknowledge and accept the following:
> 1. The smart contracts in this repository have not been audited and are provided "as is" with no guarantees, warranties, or assurances of any kind. The authors and maintainers of this repository are not responsible for any damages, losses, or liabilities that may arise from the use or deployment of these smart contracts.
> 2. The smart contracts in this repository are not intended for use in production environments or for the management of real-world assets, funds, or resources. Any use or deployment of these smart contracts for such purposes is done entirely at your own risk.
> 3. The smart contracts are provided for reference and learning purposes, and you are solely responsible for understanding, modifying, and deploying them as needed.

## Morpho Blue related functions in Solidity

One can use the logic provided in the following:

1. Functions to get data:

- `supplyAPY`
- `borrowAPY`
- `supplyAssetsUser`
- `borrowAssetsUser`
- `collateralAssetsUser`
- `marketTotalSupply`
- `marketTotalBorrow`
- `userHealthFactor`

2. Functions to modify state:

- `supply`
- `supplyCollateral`
- `withdrawCollateral`
- `withdrawAmount`
- `withdraw50Percent`
- `withdrawAll`

3. Functions using callbacks:

- `leverageMe`
- `deLeverageMe`

4. Origination fee examples:

- `borrowWithOriginationFee` through `OriginationFeeSnippets.sol`, where the user authorizes an owner-managed router on
  Morpho Blue. The owner can update the fee recipient and fee bps within the hard-coded fee cap.
- `borrowWithOriginationFee` through `OriginationFeeExecutor.sol`, where an EOA delegates to the executor with
  EIP-7702 and calls itself.

These reference examples charge a one-shot fee on the borrowed asset at borrow time. The fee is paid in the loan token,
and the borrower accrues interest on the net amount received plus the fee.

## MetaMorpho related functions in Solidity:

One can use the logic provided in the following:

1. Functions to get data:

- `totalDepositVault`
- `vaultAssetsInMarket`
- `totalSharesUserVault`
- `supplyQueueVault`
- `withdrawQueueVault`
- `totalCapCollateral`
- `supplyAPYMarket`
- `supplyAPYVault`

2. Functions to modify state:

- `depositInVault`
- `withdrawFromVaultAmount`
- `redeemAllFromVault`

## VaultV2 related functions in Solidity:

One can use the logic provided in the following:

1. Functions to get data:

- `totalDepositVaultV2`
- `totalSharesUserVaultV2`
- `sharePriceVaultV2`
- `adaptersListVaultV2`
- `allocationById`
- `absoluteCapById`
- `relativeCapById`
- `capsById`
- `realAssetsPerAdapter`
- `idleAssetsVaultV2`
- `feeInfoVaultV2`
- `liquidityAdapterVaultV2`
- `accrueInterestView`
- `previewDepositVaultV2`
- `previewMintVaultV2`
- `previewWithdrawVaultV2`
- `previewRedeemVaultV2`
- `effectiveCapById`
- `vaultV2AssetsInMarket`
- `marketsInVaultV2`
- `vaultV1AssetsInMarket` (legacy helper for MetaMorpho V1)
- `supplyAPYVaultV2`

2. Functions to modify state:

- `depositInVaultV2`
- `mintInVaultV2`
- `withdrawFromVaultV2`
- `redeemFromVaultV2`
- `redeemAllFromVaultV2`
- `accrueInterestVaultV2`

> [!NOTE]
> The VaultV2 snippets support MorphoMarketV1AdapterV2 and MorphoVaultV1Adapter.
> For MorphoVaultV1Adapter, nested VaultV2 wrappers are supported and MetaMorpho V1 handling is kept as a legacy fallback path.

## VaultV2 Liquidity Lib (Alternative View for maxWithdraw / maxRedeem)

`VaultV2` intentionally returns `0` for default `maxWithdraw` and `maxRedeem` in many integrations, which can make
UI/analytics liquidity estimation harder.

`VaultV2LiquidityLib` and `VaultV2LiquidityLens` provide an alternative view-only way to recompute withdrawable
liquidity from current state:

- `availableLiquidity(vault)`: recomputes instant exit liquidity as `idle assets + liquidity from the configured liquidity adapter`
- `maxWithdraw(vault, owner)`: recomputes `min(owner assets, available liquidity)`
- `maxRedeem(vault, owner)`: recomputes `min(owner shares, shares implied by available liquidity)`
- `adapterLiquidity(adapter, liqData)`: exposes adapter-level liquidity computation

How liquidity is recomputed:

- Idle part: token balance held directly by the vault
- Adapter part: derived from the current `liquidityAdapter` + `liquidityData` configuration
- For Morpho market adapter path, computation mirrors the single exit market encoded in `liquidityData`

> [!NOTE]
> This library is a demo/integration helper and currently supports only:
> - `MorphoMarketV1AdapterV2`
> - `MorphoVaultV1Adapter`
> Unknown adapter families are ignored (contribute `0`), so new adapter types require explicit library updates.

## VaultV2 Fee Wrapper Deployer

`FeeWrapperDeployer` deploys and configures a VaultV2 "fee wrapper" on top of an existing Morpho Vault V2 in a single
atomic transaction. A fee wrapper is a VaultV2 that wraps a child vault via a MorphoVaultV1Adapter: users deposit into
the wrapper, funds are routed to the child vault, and the wrapper owner charges performance and/or management fees on
the yield.

The deployer handles all setup atomically:

1. Creates the wrapper vault and adapter pointing to the child vault
2. Permanently locks the adapter configuration (addAdapter and removeAdapter are abdicated)
3. Sets caps, liquidity routing, max rate, and force-deallocate penalty to recommended defaults
4. Optionally configures performance fee, management fee, and fee recipient
5. Optionally abdicates gate setters for non-custodial guarantees
6. Transfers ownership to the final owner (must be a safe wallet)

Configurable parameters via `FeeWrapperConfig`:

- `owner` / `salt` / `childVault` (required)
- `name` / `symbol` (ERC20 metadata, settable later by owner)
- `performanceFee` / `managementFee` / `feeRecipient` (optional, configurable later by curator)
- `abdicateNonCriticalGates` (if true, permanently locks gates open for non-custodial operation)

> [!IMPORTANT]
> The child vault **must** be a Morpho Vault V2. The "MorphoVaultV1Adapter" name is a legacy artifact; the adapter is
> ERC4626-compatible but V2 is the only audited and recommended configuration.

> [!NOTE]
> For compliance use cases (KYC/AML), leave `abdicateNonCriticalGates = false` and configure gates later via the
> curator + timelock mechanism.

### Deterministic address & front-running protection

The wrapper is deployed via `CREATE2`, so its address is deterministic. A naive implementation that forwarded the
raw `config.salt` to the factory would be vulnerable to **address squatting**: because the deployer is always the
initial `owner`, the CREATE2 init-code hash is identical for every caller, so the address would depend only on
`(factory, salt, asset)`. A mempool observer could copy a pending `salt`, substitute their own `owner` and a malicious
same-asset `childVault`, front-run the victim, and occupy the victim's pre-computed address with a fund-draining
configuration.

To make this impossible, `createFeeWrapper` does **not** use `config.salt` directly. It derives an *effective salt*
bound to the authenticated deployment parameters:

```solidity
effectiveSalt = keccak256(abi.encode(msg.sender, owner, childVault, salt));
```

As a result the address is a pure function of `(deployer, owner, childVault, salt)`. A front-runner necessarily has a
different `msg.sender` (or substitutes `owner`/`childVault`), so they land on a different address and can never occupy
the address a victim pre-computed. Use `FeeWrapperDeployer.feeWrapperSalt(...)` to reproduce the effective salt
off-chain, and a `FeeWrapperCreated(vault, caller, owner, childVault, salt)` event is emitted for provenance.

> [!IMPORTANT]
> Because the address is bound to `msg.sender`, always deploy through the sanctioned script
> [`script/DeployFeeWrapper.s.sol`](./script/DeployFeeWrapper.s.sol), which pins the broadcaster, logs the resulting
> deterministic address, and verifies on-chain provenance. Do **not** call `createFeeWrapper` ad hoc from other
> contracts or unpinned tooling — the address is only meaningful relative to the caller that created it.

```bash
# Configure the deployment (see the script's NatSpec for the full list of variables)
export MORPHO_VAULT_V2_FACTORY=0x...
export MORPHO_VAULT_V1_ADAPTER_FACTORY=0x...
export FW_OWNER=0x...          # final owner (MUST be a safe wallet / multisig)
export FW_CHILD_VAULT=0x...    # child vault to wrap (MUST be a Morpho Vault V2)
export FW_SALT=0x0000000000000000000000000000000000000000000000000000000000000001

# Dry run first to preview the deterministic address, then add --broadcast
forge script script/DeployFeeWrapper.s.sol:DeployFeeWrapper --rpc-url <rpc>
```

## Getting Started

- Install [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Install [yarn](https://classic.yarnpkg.com/lang/en/docs/install/#mac-stable)
- Run `foundryup`
- Run `forge install`
- Create a `.env` file according to the `.env.example` file.

## Testing with Foundry

You can run tests by running the command:

```bash
forge test
```

## Questions & Feedbacks

If you have any questions or need further assistance, please don't hesitate to reach out on [Discord](https://discord.morpho.org).

## License

The code is under the MIT License. See [`LICENSE`](./LICENSE).

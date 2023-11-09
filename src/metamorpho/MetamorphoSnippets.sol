// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IMetaMorpho} from "@metamorpho/interfaces/IMetaMorpho.sol";
import {ConstantsLib} from "@metamorpho/libraries/ConstantsLib.sol";

import {MarketParamsLib} from "@morpho-blue/libraries/MarketParamsLib.sol";
import {Id, IMorpho, Market, MarketParams} from "@morpho-blue/interfaces/IMorpho.sol";
import {IrmMock} from "@metamorpho/mocks/IrmMock.sol";
import {MorphoBalancesLib} from "@morpho-blue/libraries/periphery/MorphoBalancesLib.sol";
import {MathLib, WAD} from "@morpho-blue/libraries/MathLib.sol";

import {Math} from "@openzeppelin/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";

contract MetamorphoSnippets {
    uint256 constant FEE = 0.2 ether; // 20%

    IMetaMorpho public immutable vault;
    IMorpho public immutable morpho;

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

    /// @dev note that one can adapt the address in the call to the morpho contract
    function vaultAmountInMarket(MarketParams memory marketParams) public view returns (uint256 vaultAmount) {
        vaultAmount = morpho.expectedSupplyAssets(marketParams, address(vault));
    }

    function totalSharesUserVault(address user) public view returns (uint256 totalSharesUser) {
        totalSharesUser = vault.balanceOf(user);
    }

    function supplyQueueVault() public view returns (Id[] memory supplyQueueList) {
        uint256 queueLength = vault.supplyQueueLength();
        supplyQueueList = new Id[](queueLength);
        for (uint256 i; i < queueLength; ++i) {
            supplyQueueList[i] = vault.supplyQueue(i);
        }
        return supplyQueueList;
    }

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

    // TO TEST
    function supplyAPRMarket(MarketParams memory marketParams, Market memory market)
        public
        view
        returns (uint256 supplyRate)
    {
        (uint256 totalSupplyAssets,, uint256 totalBorrowAssets,) = morpho.expectedMarketBalances(marketParams);

        // Get the borrow rate
        uint256 borrowRate = IrmMock(marketParams.irm).borrowRateView(marketParams, market);

        // Get the supply rate
        uint256 utilization = totalBorrowAssets == 0 ? 0 : totalBorrowAssets.wDivUp(totalSupplyAssets);

        supplyRate = borrowRate.wMulDown(1 ether - market.fee).wMulDown(utilization);
    }

    // TODO: edit comment + Test function
    // same function as Morpho Blue Snippets
    // a amount at 6%, B amount at 3 %:
    // (a*6%) + (B*3%) / (a+b+ IDLE)

    function supplyAPRVault() public view returns (uint256 avgSupplyRate) {
        uint256 ratio;
        uint256 queueLength = vault.withdrawQueueLength();

        // TODO: Verify that the idle liquidity is taken into account
        uint256 totalAmount = totalDepositVault();

        for (uint256 i; i < queueLength; ++i) {
            Id idMarket = vault.withdrawQueue(i);

            // To change once the cantina-review branch is merged
            (address loanToken, address collateralToken, address oracle, address irm, uint256 lltv) =
                (morpho.idToMarketParams(idMarket));

            MarketParams memory marketParams = MarketParams(loanToken, collateralToken, oracle, irm, lltv);
            Market memory market = morpho.market(idMarket);

            uint256 currentSupplyAPR = supplyAPRMarket(marketParams, market);
            uint256 vaultAsset = vaultAmountInMarket(marketParams);
            ratio += currentSupplyAPR.wMulDown(vaultAsset);
        }

        avgSupplyRate = ratio.wDivUp(totalAmount);
    }

    // --- MANAGING FUNCTIONS ---

    // deposit in the vault a nb of asset
    function depositInVault(uint256 assets, address onBehalf) public returns (uint256 shares) {
        shares = vault.deposit(assets, onBehalf);
    }

    function withdrawFromVault(uint256 assets, address onBehalf) public returns (uint256 redeemed) {
        address receiver = onBehalf;
        redeemed = vault.withdraw(assets, receiver, onBehalf);
    }

    function redeemAllFromVault(address receiver) public returns (uint256 redeemed) {
        uint256 maxToRedeem = vault.maxRedeem(address(this));
        redeemed = vault.redeem(maxToRedeem, receiver, address(this));
    }

    // TODO:
    // Reallocation example
}

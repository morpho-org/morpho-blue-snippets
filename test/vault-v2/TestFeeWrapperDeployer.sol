// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import "../../lib/vault-v2/test/integration/MorphoVaultV1IntegrationTest.sol";
import {FeeWrapperDeployer} from "../../src/vault-v2/FeeWrapperDeployer.sol";
import {IVaultV2} from "../../lib/vault-v2/src/interfaces/IVaultV2.sol";
import {IVaultV2Factory} from "../../lib/vault-v2/src/interfaces/IVaultV2Factory.sol";
import {IERC20} from "../../lib/vault-v2/src/interfaces/IERC20.sol";
import {MAX_MAX_RATE, MAX_FORCE_DEALLOCATE_PENALTY, WAD} from "../../lib/vault-v2/src/libraries/ConstantsLib.sol";

contract TestFeeWrapperDeployer is MorphoVaultV1IntegrationTest {
    FeeWrapperDeployer internal deployer;

    address internal DEPOSITOR = makeAddr("Depositor");
    address internal FEE_RECIPIENT = makeAddr("FeeRecipient");

    function setUp() public virtual override {
        super.setUp();

        deployer = new FeeWrapperDeployer();

        setSupplyQueueAllMarkets();
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    function _basicConfig() internal view returns (FeeWrapperDeployer.FeeWrapperConfig memory) {
        return FeeWrapperDeployer.FeeWrapperConfig({
            owner: owner,
            salt: bytes32(uint256(1)),
            childVault: address(vault),
            name: "",
            symbol: "",
            performanceFee: 0,
            managementFee: 0,
            feeRecipient: address(0),
            abdicateNonCriticalGates: false
        });
    }

    function _deployWrapper(FeeWrapperDeployer.FeeWrapperConfig memory config) internal returns (IVaultV2) {
        return IVaultV2(
            deployer.createFeeWrapper(address(vaultFactory), address(morphoVaultV1AdapterFactory), config)
        );
    }

    // -----------------------------------------------------------------------
    // Tests
    // -----------------------------------------------------------------------

    function testDeployBasicFeeWrapper() public {
        FeeWrapperDeployer.FeeWrapperConfig memory config = _basicConfig();
        IVaultV2 wrapper = _deployWrapper(config);

        assertEq(wrapper.owner(), owner, "owner");
        assertEq(wrapper.curator(), owner, "curator");
        assertTrue(wrapper.isAllocator(owner), "owner is allocator");
        assertTrue(wrapper.isSentinel(owner), "owner is sentinel");
        assertEq(wrapper.asset(), IVaultV2(address(vault)).asset(), "asset matches child vault");
    }

    function testDeployWithNameAndSymbol() public {
        FeeWrapperDeployer.FeeWrapperConfig memory config = _basicConfig();
        config.name = "Fee Wrapped Vault";
        config.symbol = "fwVAULT";
        config.salt = bytes32(uint256(2));

        IVaultV2 wrapper = _deployWrapper(config);

        assertEq(wrapper.name(), "Fee Wrapped Vault", "name");
        assertEq(wrapper.symbol(), "fwVAULT", "symbol");
    }

    function testDeployWithPerformanceFee() public {
        FeeWrapperDeployer.FeeWrapperConfig memory config = _basicConfig();
        config.performanceFee = 0.1e18; // 10%
        config.feeRecipient = FEE_RECIPIENT;
        config.salt = bytes32(uint256(3));

        IVaultV2 wrapper = _deployWrapper(config);

        assertEq(wrapper.performanceFee(), 0.1e18, "performance fee");
        assertEq(wrapper.performanceFeeRecipient(), FEE_RECIPIENT, "performance fee recipient");
    }

    function testDeployWithManagementFee() public {
        FeeWrapperDeployer.FeeWrapperConfig memory config = _basicConfig();
        config.managementFee = 0.03e18 / uint256(365 days); // ~3% APR
        config.feeRecipient = FEE_RECIPIENT;
        config.salt = bytes32(uint256(4));

        IVaultV2 wrapper = _deployWrapper(config);

        assertEq(wrapper.managementFee(), config.managementFee, "management fee");
        assertEq(wrapper.managementFeeRecipient(), FEE_RECIPIENT, "management fee recipient");
    }

    function testDeployWithBothFees() public {
        FeeWrapperDeployer.FeeWrapperConfig memory config = _basicConfig();
        config.performanceFee = 0.15e18; // 15%
        config.managementFee = 0.02e18 / uint256(365 days); // ~2% APR
        config.feeRecipient = FEE_RECIPIENT;
        config.salt = bytes32(uint256(5));

        IVaultV2 wrapper = _deployWrapper(config);

        assertEq(wrapper.performanceFee(), 0.15e18, "performance fee");
        assertEq(wrapper.performanceFeeRecipient(), FEE_RECIPIENT, "performance fee recipient");
        assertEq(wrapper.managementFee(), config.managementFee, "management fee");
        assertEq(wrapper.managementFeeRecipient(), FEE_RECIPIENT, "management fee recipient");
    }

    function testDeployWithGateAbdication() public {
        FeeWrapperDeployer.FeeWrapperConfig memory config = _basicConfig();
        config.abdicateNonCriticalGates = true;
        config.salt = bytes32(uint256(6));

        IVaultV2 wrapper = _deployWrapper(config);

        assertTrue(wrapper.abdicated(IVaultV2.setReceiveSharesGate.selector), "receiveSharesGate abdicated");
        assertTrue(wrapper.abdicated(IVaultV2.setSendSharesGate.selector), "sendSharesGate abdicated");
        assertTrue(wrapper.abdicated(IVaultV2.setReceiveAssetsGate.selector), "receiveAssetsGate abdicated");
        assertFalse(wrapper.abdicated(IVaultV2.setSendAssetsGate.selector), "sendAssetsGate NOT abdicated");
    }

    function testDeployFullConfig() public {
        FeeWrapperDeployer.FeeWrapperConfig memory config = FeeWrapperDeployer.FeeWrapperConfig({
            owner: owner,
            salt: bytes32(uint256(7)),
            childVault: address(vault),
            name: "Full Config Wrapper",
            symbol: "FULL",
            performanceFee: 0.2e18,
            managementFee: 0.04e18 / uint256(365 days),
            feeRecipient: FEE_RECIPIENT,
            abdicateNonCriticalGates: true
        });

        IVaultV2 wrapper = _deployWrapper(config);

        assertEq(wrapper.owner(), owner, "owner");
        assertEq(wrapper.name(), "Full Config Wrapper", "name");
        assertEq(wrapper.symbol(), "FULL", "symbol");
        assertEq(wrapper.performanceFee(), 0.2e18, "performance fee");
        assertEq(wrapper.managementFee(), config.managementFee, "management fee");
        assertTrue(wrapper.abdicated(IVaultV2.setReceiveSharesGate.selector), "gate abdicated");
    }

    function testAdapterPermanentlyLocked() public {
        IVaultV2 wrapper = _deployWrapper(_basicConfig());

        assertTrue(wrapper.abdicated(IVaultV2.addAdapter.selector), "addAdapter abdicated");
        assertTrue(wrapper.abdicated(IVaultV2.removeAdapter.selector), "removeAdapter abdicated");
    }

    function testDeployerHasNoPrivilegesAfter() public {
        IVaultV2 wrapper = _deployWrapper(_basicConfig());

        assertTrue(wrapper.owner() != address(deployer), "deployer is not owner");
        assertTrue(wrapper.curator() != address(deployer), "deployer is not curator");
        assertFalse(wrapper.isAllocator(address(deployer)), "deployer is not allocator");
        assertFalse(wrapper.isSentinel(address(deployer)), "deployer is not sentinel");
    }

    function testCapsAndAllocatorConfig() public {
        IVaultV2 wrapper = _deployWrapper(_basicConfig());

        address adapter = wrapper.adapters(0);
        bytes memory adapterIdData = abi.encode("this", adapter);
        bytes32 adapterId = keccak256(adapterIdData);

        assertEq(wrapper.absoluteCap(adapterId), type(uint128).max, "absolute cap max");
        assertEq(wrapper.relativeCap(adapterId), WAD, "relative cap WAD");
        assertEq(wrapper.liquidityAdapter(), adapter, "liquidity adapter set");
        assertEq(wrapper.maxRate(), MAX_MAX_RATE, "max rate");
        assertEq(wrapper.forceDeallocatePenalty(adapter), MAX_FORCE_DEALLOCATE_PENALTY, "force deallocate penalty");
    }

    function testDepositIntoFeeWrapper() public {
        IVaultV2 wrapper = _deployWrapper(_basicConfig());

        uint256 amount = 1e18;
        deal(address(underlyingToken), DEPOSITOR, amount);

        vm.startPrank(DEPOSITOR);
        underlyingToken.approve(address(wrapper), amount);
        wrapper.deposit(amount, DEPOSITOR);
        vm.stopPrank();

        assertGt(wrapper.totalAssets(), 0, "totalAssets > 0");
        assertGt(wrapper.balanceOf(DEPOSITOR), 0, "shares > 0");
    }

    function testDepositAndWithdrawRoundTrip() public {
        IVaultV2 wrapper = _deployWrapper(_basicConfig());

        uint256 amount = 1e18;
        deal(address(underlyingToken), DEPOSITOR, amount);

        vm.startPrank(DEPOSITOR);
        underlyingToken.approve(address(wrapper), amount);
        wrapper.deposit(amount, DEPOSITOR);

        uint256 shares = wrapper.balanceOf(DEPOSITOR);
        wrapper.redeem(shares, DEPOSITOR, DEPOSITOR);
        vm.stopPrank();

        assertApproxEqAbs(underlyingToken.balanceOf(DEPOSITOR), amount, 1, "got assets back");
    }

    function testRevertNonV2ChildVault() public {
        FeeWrapperDeployer.FeeWrapperConfig memory config = _basicConfig();
        config.childVault = makeAddr("notAVault");
        config.salt = bytes32(uint256(99));

        vm.expectRevert("FeeWrapperDeployer: child vault must be a Morpho Vault V2");
        deployer.createFeeWrapper(address(vaultFactory), address(morphoVaultV1AdapterFactory), config);
    }
}

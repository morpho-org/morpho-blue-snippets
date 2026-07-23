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
        return IVaultV2(deployer.createFeeWrapper(address(vaultFactory), address(morphoVaultV1AdapterFactory), config));
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

    // -----------------------------------------------------------------------
    // CREATE2 salt binding / front-running protection
    //
    // The effective CREATE2 salt is keccak256(abi.encode(msg.sender, owner, childVault, salt)).
    // These tests prove the deterministic address is bound to (caller, owner, childVault, salt),
    // so a mempool front-runner can never occupy a victim's pre-computed address.
    // -----------------------------------------------------------------------

    /// @dev Deploys a second, distinct Morpho Vault V2 with the same asset, usable as a child vault.
    function _secondChildVault() internal returns (address) {
        return vaultFactory.createVaultV2(owner, IVaultV2(address(vault)).asset(), bytes32(uint256(0xC0FFEE)));
    }

    function testFeeWrapperSaltIsDeterministic() public {
        address caller = makeAddr("caller");
        bytes32 expected = keccak256(abi.encode(caller, owner, address(vault), bytes32(uint256(1))));
        assertEq(deployer.feeWrapperSalt(caller, owner, address(vault), bytes32(uint256(1))), expected, "salt");
    }

    function testAddressBoundToSender() public {
        FeeWrapperDeployer.FeeWrapperConfig memory config = _basicConfig();
        config.salt = bytes32(uint256(0x5E11DE7));

        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        vm.prank(alice);
        address vaultA = deployer.createFeeWrapper(address(vaultFactory), address(morphoVaultV1AdapterFactory), config);

        // Same config, same user salt, DIFFERENT sender -> different address, no collision.
        vm.prank(bob);
        address vaultB = deployer.createFeeWrapper(address(vaultFactory), address(morphoVaultV1AdapterFactory), config);

        assertTrue(vaultA != vaultB, "sender binds address");
    }

    function testAddressBoundToOwner() public {
        FeeWrapperDeployer.FeeWrapperConfig memory config = _basicConfig();
        config.salt = bytes32(uint256(0x0116E5));

        config.owner = makeAddr("ownerOne");
        vm.prank(address(this));
        address vault1 = deployer.createFeeWrapper(address(vaultFactory), address(morphoVaultV1AdapterFactory), config);

        // Same sender, same user salt, DIFFERENT owner -> different address.
        config.owner = makeAddr("ownerTwo");
        address vault2 = deployer.createFeeWrapper(address(vaultFactory), address(morphoVaultV1AdapterFactory), config);

        assertTrue(vault1 != vault2, "owner binds address");
    }

    function testAddressBoundToChildVault() public {
        FeeWrapperDeployer.FeeWrapperConfig memory config = _basicConfig();
        config.salt = bytes32(uint256(0xC411D));

        address vaultA = deployer.createFeeWrapper(address(vaultFactory), address(morphoVaultV1AdapterFactory), config);

        // Same sender, same owner, same user salt, DIFFERENT child vault -> different address.
        config.childVault = _secondChildVault();
        address vaultB = deployer.createFeeWrapper(address(vaultFactory), address(morphoVaultV1AdapterFactory), config);

        assertTrue(vaultA != vaultB, "childVault binds address");
    }

    /// @dev The headline regression test for the CREATE2 squatting finding.
    /// An attacker front-runs by copying the victim's user salt, but with their own sender and a
    /// malicious child vault. They land on a DIFFERENT address, so the victim's deployment still
    /// succeeds at its own (untouched) address, owned by the victim's owner.
    function testFrontRunnerCannotHijackVictimAddress() public {
        address victim = makeAddr("victim");
        address victimOwner = makeAddr("victimOwner");
        address attacker = makeAddr("attacker");
        address attackerOwner = makeAddr("attackerOwner");
        bytes32 sharedSalt = bytes32(uint256(0xBEEF));

        // Attacker mines first, reusing the victim's user salt but with their own params.
        FeeWrapperDeployer.FeeWrapperConfig memory attackerConfig = _basicConfig();
        attackerConfig.owner = attackerOwner;
        attackerConfig.salt = sharedSalt;
        attackerConfig.childVault = _secondChildVault(); // a same-asset "malicious" child
        vm.prank(attacker);
        address attackerVault =
            deployer.createFeeWrapper(address(vaultFactory), address(morphoVaultV1AdapterFactory), attackerConfig);

        // Victim's original tx still executes successfully at its OWN address.
        FeeWrapperDeployer.FeeWrapperConfig memory victimConfig = _basicConfig();
        victimConfig.owner = victimOwner;
        victimConfig.salt = sharedSalt;
        victimConfig.childVault = address(vault);
        vm.prank(victim);
        address victimVault =
            deployer.createFeeWrapper(address(vaultFactory), address(morphoVaultV1AdapterFactory), victimConfig);

        assertTrue(attackerVault != victimVault, "front-runner lands on a different address");
        assertEq(IVaultV2(victimVault).owner(), victimOwner, "victim owns its vault");

        // Even if the attacker copies the victim's owner AND child vault verbatim, their differing
        // sender still yields a different address: they can never occupy the victim's slot.
        FeeWrapperDeployer.FeeWrapperConfig memory copycatConfig = _basicConfig();
        copycatConfig.owner = victimOwner;
        copycatConfig.salt = sharedSalt;
        copycatConfig.childVault = address(vault);
        vm.prank(attacker);
        address copycatVault =
            deployer.createFeeWrapper(address(vaultFactory), address(morphoVaultV1AdapterFactory), copycatConfig);

        assertTrue(copycatVault != victimVault, "attacker cannot reproduce victim's address");
    }

    function testIdenticalDeploymentRevertsOnCollision() public {
        FeeWrapperDeployer.FeeWrapperConfig memory config = _basicConfig();
        config.salt = bytes32(uint256(0xDEAD));

        deployer.createFeeWrapper(address(vaultFactory), address(morphoVaultV1AdapterFactory), config);

        // Same sender, owner, childVault and user salt => same effective salt => CREATE2 collision.
        vm.expectRevert();
        deployer.createFeeWrapper(address(vaultFactory), address(morphoVaultV1AdapterFactory), config);
    }

    function testEmitsFeeWrapperCreatedEvent() public {
        FeeWrapperDeployer.FeeWrapperConfig memory config = _basicConfig();
        config.salt = bytes32(uint256(0xE7E27));

        // The vault address (topic1) is not known ahead of time, so skip it; check caller (topic2),
        // owner (topic3) and the data (childVault, userSalt).
        vm.expectEmit(false, true, true, true, address(deployer));
        emit FeeWrapperDeployer.FeeWrapperCreated(address(0), address(this), owner, address(vault), config.salt);
        deployer.createFeeWrapper(address(vaultFactory), address(morphoVaultV1AdapterFactory), config);
    }
}

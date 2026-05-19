// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "../../lib/morpho-blue/test/forge/BaseTest.sol";
import {OriginationFeeExecutor} from "../../src/morpho-blue/OriginationFeeExecutor.sol";
import {OriginationFeeSnippets} from "../../src/morpho-blue/OriginationFeeSnippets.sol";
import {ErrorsLib} from "../../lib/morpho-blue/src/libraries/ErrorsLib.sol";

interface Vm7702 {
    struct SignedDelegation {
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint64 nonce;
        address implementation;
    }

    function attachDelegation(SignedDelegation calldata signedDelegation) external;
    function signDelegation(address implementation, uint256 privateKey)
        external
        returns (SignedDelegation memory signedDelegation);
}

contract OriginationFeeSnippetsTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    Vm7702 internal constant vm7702 = Vm7702(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant FEE_BPS = 200;
    uint256 internal constant MAX_FEE_BPS = 1_000;
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    address internal feeRecipient;
    OriginationFeeSnippets internal snippets;
    OriginationFeeExecutor internal executor;

    event OriginationFeeCharged(address indexed borrower, Id indexed marketId, uint256 userAssets, uint256 feeAmount);
    event FeeRecipientSet(address indexed newFeeRecipient);
    event FeeBpsSet(uint256 newFeeBps);

    function setUp() public virtual override {
        super.setUp();

        feeRecipient = makeAddr("OriginationFeeRecipient");
        snippets = new OriginationFeeSnippets(morpho, feeRecipient, FEE_BPS);
        executor = new OriginationFeeExecutor();

        vm.prank(BORROWER);
        morpho.setAuthorization(address(snippets), true);
    }

    function testBorrowWithFeeHappyPath(uint256 userAssets) public {
        userAssets = _boundBorrowAmount(userAssets);
        uint256 feeAmount = _fee(userAssets, FEE_BPS);
        uint256 totalBorrowed = userAssets + feeAmount;

        _supplyLiquidity(MAX_TEST_AMOUNT);
        _supplyCollateralForBorrower(BORROWER);

        vm.expectEmit(true, true, false, true, address(snippets));
        emit OriginationFeeCharged(BORROWER, id, userAssets, feeAmount);

        vm.prank(BORROWER);
        (uint256 returnedFee, uint256 returnedBorrowed) = snippets.borrowWithOriginationFee(marketParams, userAssets);

        assertEq(returnedFee, feeAmount, "returned fee");
        assertEq(returnedBorrowed, totalBorrowed, "returned borrowed");
        _assertOriginationFeeOutcome(BORROWER, feeRecipient, userAssets, feeAmount);
    }

    function testRevertWhenNotAuthorized() public {
        address borrower = makeAddr("notAuthorizedBorrower");

        _supplyLiquidity(MAX_TEST_AMOUNT);
        _supplyCollateralForBorrower(borrower);

        vm.prank(borrower);
        vm.expectRevert(bytes(ErrorsLib.UNAUTHORIZED));
        snippets.borrowWithOriginationFee(marketParams, MIN_TEST_AMOUNT);
    }

    function testRevertWhenInsufficientCollateral() public {
        _supplyLiquidity(MAX_TEST_AMOUNT);

        vm.prank(BORROWER);
        vm.expectRevert(bytes(ErrorsLib.INSUFFICIENT_COLLATERAL));
        snippets.borrowWithOriginationFee(marketParams, MIN_TEST_AMOUNT);
    }

    function testRevertOnZeroUserAssets() public {
        vm.prank(BORROWER);
        vm.expectRevert(bytes(ErrorsLib.INCONSISTENT_INPUT));
        snippets.borrowWithOriginationFee(marketParams, 0);
    }

    function testConstructorBounds() public {
        vm.expectRevert(bytes("ZERO_RECIPIENT"));
        new OriginationFeeSnippets(morpho, address(0), FEE_BPS);

        vm.expectRevert(bytes("INVALID_FEE_BPS"));
        new OriginationFeeSnippets(morpho, feeRecipient, 0);

        vm.expectRevert(bytes("INVALID_FEE_BPS"));
        new OriginationFeeSnippets(morpho, feeRecipient, MAX_FEE_BPS + 1);
    }

    function testOwnerCanSetFeeConfigAndBorrowUsesIt(uint256 userAssets) public {
        userAssets = _boundBorrowAmount(userAssets);
        address newFeeRecipient = makeAddr("newFeeRecipient");
        uint256 newFeeBps = 350;
        uint256 feeAmount = _fee(userAssets, newFeeBps);
        uint256 totalBorrowed = userAssets + feeAmount;

        vm.expectEmit(true, false, false, true, address(snippets));
        emit FeeRecipientSet(newFeeRecipient);
        snippets.setFeeRecipient(newFeeRecipient);

        vm.expectEmit(false, false, false, true, address(snippets));
        emit FeeBpsSet(newFeeBps);
        snippets.setFeeBps(newFeeBps);

        assertEq(snippets.feeRecipient(), newFeeRecipient, "fee recipient");
        assertEq(snippets.feeBps(), newFeeBps, "fee bps");

        _supplyLiquidity(MAX_TEST_AMOUNT);
        _supplyCollateralForBorrower(BORROWER);

        vm.prank(BORROWER);
        (uint256 returnedFee, uint256 returnedBorrowed) = snippets.borrowWithOriginationFee(marketParams, userAssets);

        assertEq(returnedFee, feeAmount, "returned fee");
        assertEq(returnedBorrowed, totalBorrowed, "returned borrowed");
        assertEq(loanToken.balanceOf(feeRecipient), 0, "old fee recipient balance");
        _assertOriginationFeeOutcome(BORROWER, newFeeRecipient, userAssets, feeAmount);
    }

    function testOnlyOwnerCanSetFeeConfig() public {
        address newFeeRecipient = makeAddr("newFeeRecipient");

        vm.startPrank(BORROWER);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        snippets.setFeeRecipient(newFeeRecipient);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        snippets.setFeeBps(350);
        vm.stopPrank();
    }

    function testSetFeeConfigBounds() public {
        vm.expectRevert(bytes("ZERO_RECIPIENT"));
        snippets.setFeeRecipient(address(0));

        vm.expectRevert(bytes("INVALID_FEE_BPS"));
        snippets.setFeeBps(0);

        vm.expectRevert(bytes("INVALID_FEE_BPS"));
        snippets.setFeeBps(MAX_FEE_BPS + 1);
    }

    function testInterestAccruesOnGrossAmount() public {
        uint256 userAssets = 1_000 ether;
        uint256 feeAmount = _fee(userAssets, FEE_BPS);
        uint256 totalBorrowed = userAssets + feeAmount;

        _supplyLiquidity(10_000 ether);
        _supplyCollateralForBorrower(BORROWER);

        vm.prank(BORROWER);
        snippets.borrowWithOriginationFee(marketParams, userAssets);

        uint256 elapsed = 30 days;
        uint256 borrowRate = morpho.totalBorrowAssets(id).wDivDown(morpho.totalSupplyAssets(id)) / 365 days;
        uint256 expectedInterest = totalBorrowed.wMulDown(borrowRate.wTaylorCompounded(elapsed));

        _forward(elapsed);
        morpho.accrueInterest(marketParams);

        assertEq(morpho.totalBorrowAssets(id), totalBorrowed + expectedInterest, "gross debt accrued interest");
        assertGt(morpho.expectedBorrowAssets(marketParams, BORROWER), userAssets, "debt should exceed net amount");
    }

    function test7702HappyPath(uint256 userAssets) public {
        userAssets = _boundBorrowAmount(userAssets);
        uint256 feeAmount = _fee(userAssets, FEE_BPS);
        uint256 totalBorrowed = userAssets + feeAmount;
        (address user, uint256 userPk) = makeAddrAndKey("user_7702");

        _supplyLiquidity(MAX_TEST_AMOUNT);
        _supplyCollateralForBorrower(user);
        _attachDelegation(userPk, address(executor));

        vm.expectEmit(true, true, false, true, user);
        emit OriginationFeeCharged(user, id, userAssets, feeAmount);

        vm.prank(user);
        (uint256 returnedFee, uint256 returnedBorrowed) = OriginationFeeExecutor(user)
            .borrowWithOriginationFee(morpho, marketParams, userAssets, FEE_BPS, feeRecipient);

        assertEq(returnedFee, feeAmount, "returned fee");
        assertEq(returnedBorrowed, totalBorrowed, "returned borrowed");
        assertFalse(morpho.isAuthorized(user, address(executor)), "executor should not be authorized");
        _assertOriginationFeeOutcome(user, feeRecipient, userAssets, feeAmount);
    }

    function test7702RevertsOnInvalidParams() public {
        (address user, uint256 userPk) = makeAddrAndKey("invalid_params_7702");
        _attachDelegation(userPk, address(executor));

        vm.startPrank(user);
        vm.expectRevert(bytes("ZERO_RECIPIENT"));
        OriginationFeeExecutor(user)
            .borrowWithOriginationFee(morpho, marketParams, MIN_TEST_AMOUNT, FEE_BPS, address(0));

        vm.expectRevert(bytes("INVALID_FEE_BPS"));
        OriginationFeeExecutor(user).borrowWithOriginationFee(morpho, marketParams, MIN_TEST_AMOUNT, 0, feeRecipient);

        vm.expectRevert(bytes("INVALID_FEE_BPS"));
        OriginationFeeExecutor(user)
            .borrowWithOriginationFee(morpho, marketParams, MIN_TEST_AMOUNT, MAX_FEE_BPS + 1, feeRecipient);
        vm.stopPrank();
    }

    function test7702RevertsWhenCallerIsNotDelegatedEoa() public {
        (address user, uint256 userPk) = makeAddrAndKey("guarded_user_7702");
        address attacker = makeAddr("attacker");

        _attachDelegation(userPk, address(executor));

        vm.prank(attacker);
        vm.expectRevert(bytes("ONLY_SELF"));
        OriginationFeeExecutor(user).borrowWithOriginationFee(morpho, marketParams, MIN_TEST_AMOUNT, FEE_BPS, attacker);
    }

    function test7702DelegationCanBeCleared() public {
        (address user, uint256 userPk) = makeAddrAndKey("clearable_user_7702");

        _attachDelegation(userPk, address(executor));
        vm.prank(user);
        uint256 maxFeeBps = OriginationFeeExecutor(user).MAX_FEE_BPS();
        assertEq(maxFeeBps, executor.MAX_FEE_BPS(), "delegation setup call failed");
        assertGt(user.code.length, 0, "delegation should install code");

        _attachDelegation(userPk, address(0));
        vm.prank(user);
        (bool clearCallSuccess,) = user.call("");
        assertTrue(clearCallSuccess, "delegation clear call failed");
        assertEq(user.code.length, 0, "delegation should be cleared");
    }

    function _supplyLiquidity(uint256 assets) internal {
        loanToken.setBalance(SUPPLIER, assets);
        vm.prank(SUPPLIER);
        morpho.supply(marketParams, assets, 0, SUPPLIER, hex"");
    }

    function _attachDelegation(uint256 privateKey, address implementation) internal {
        vm7702.attachDelegation(vm7702.signDelegation(implementation, privateKey));
    }

    function _assertOriginationFeeOutcome(address borrower, address recipient, uint256 userAssets, uint256 feeAmount)
        internal
    {
        assertEq(loanToken.balanceOf(borrower), userAssets, "borrower loan balance");
        assertEq(loanToken.balanceOf(recipient), feeAmount, "recipient fee balance");
        assertEq(morpho.expectedBorrowAssets(marketParams, borrower), userAssets + feeAmount, "borrow debt");
        assertGt(morpho.borrowShares(id, borrower), 0, "borrow shares");
    }

    function _boundBorrowAmount(uint256 userAssets) internal pure returns (uint256) {
        return bound(userAssets, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT * 9 / 10);
    }

    function _fee(uint256 userAssets, uint256 feeBps) internal pure returns (uint256) {
        return userAssets * feeBps / BPS_DENOMINATOR;
    }
}

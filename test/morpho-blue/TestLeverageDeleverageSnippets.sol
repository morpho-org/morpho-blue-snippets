// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "../../lib/morpho-blue/test/forge/BaseTest.sol";
import {ISwap} from "../../src/morpho-blue/interfaces/ISwap.sol";
import {SwapMock} from "../../src/morpho-blue/mocks/SwapMock.sol";
import {LeverageDeleverageSnippets} from "../../src/morpho-blue/LeverageDeleverageSnippets.sol";
import {ERC20} from "../../lib/solmate/src/utils/SafeTransferLib.sol";

contract LeverageDeleverageTest is BaseTest {
    using MathLib for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;

    address internal BORROWER_;

    ISwap internal swapper;

    LeverageDeleverageSnippets public snippets;

    function setUp() public virtual override {
        super.setUp();

        BORROWER_ = makeAddr("User");

        swapper = ISwap(address(new SwapMock(address(collateralToken), address(loanToken), address(oracle))));
        snippets = new LeverageDeleverageSnippets(morpho, swapper);

        vm.startPrank(BORROWER_);
        collateralToken.approve(address(snippets), type(uint256).max);
        morpho.setAuthorization(address(snippets), true);
        vm.stopPrank();
    }

    function testLeverageMe(uint256 initAmountCollateral, uint256 leverageFactor) public {
        uint256 maxLeverageFactor = WAD / (WAD - marketParams.lltv);

        leverageFactor = bound(leverageFactor, 2, maxLeverageFactor);
        initAmountCollateral = bound(initAmountCollateral, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT / leverageFactor);
        uint256 finalAmountCollateral = initAmountCollateral * leverageFactor;

        oracle.setPrice(ORACLE_PRICE_SCALE);
        loanToken.setBalance(SUPPLIER, finalAmountCollateral);
        collateralToken.setBalance(BORROWER_, initAmountCollateral);

        vm.prank(SUPPLIER);
        morpho.supply(marketParams, finalAmountCollateral, 0, SUPPLIER, hex"");

        vm.prank(BORROWER_);
        snippets.leverageMe(leverageFactor, initAmountCollateral, marketParams);

        uint256 loanAmount = initAmountCollateral * (leverageFactor - 1);

        assertGt(morpho.borrowShares(marketParams.id(), BORROWER_), 0, "no borrow");
        assertEq(morpho.collateral(marketParams.id(), BORROWER_), finalAmountCollateral, "no collateral");
        assertEq(morpho.expectedBorrowAssets(marketParams, BORROWER_), loanAmount, "no collateral");
    }

    function testOnlyMorphoEnforcement() public {
        // Arrange: Deploy a malicious contract or use an EOA address different from Morpho's
        address maliciousUser = makeAddr("maliciousUser");

        // Act: Try calling a function protected by the onlyMorpho modifier
        vm.startPrank(maliciousUser);
        (bool success,) =
            address(snippets).call(abi.encodeWithSelector(snippets.onMorphoSupplyCollateral.selector, 0, ""));
        vm.stopPrank();

        // Assert: The call should fail if the onlyMorpho modifier is correctly implemented
        assertEq(success, false, "Function should not be callable by addresses other than Morpho");
    }

    function testDeLeverageMe(uint256 initAmountCollateral, uint256 leverageFactor) public {
        uint256 maxLeverageFactor = WAD / (WAD - marketParams.lltv);

        leverageFactor = bound(leverageFactor, 2, maxLeverageFactor);
        initAmountCollateral = bound(initAmountCollateral, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT / leverageFactor);
        uint256 finalAmountCollateral = initAmountCollateral * leverageFactor;

        oracle.setPrice(ORACLE_PRICE_SCALE);
        loanToken.setBalance(SUPPLIER, finalAmountCollateral);
        collateralToken.setBalance(BORROWER_, initAmountCollateral);

        vm.prank(SUPPLIER);
        morpho.supply(marketParams, finalAmountCollateral, 0, SUPPLIER, hex"");

        uint256 loanAmount = initAmountCollateral * (leverageFactor - 1);

        vm.prank(BORROWER_);
        snippets.leverageMe(leverageFactor, initAmountCollateral, marketParams);

        assertGt(morpho.borrowShares(marketParams.id(), BORROWER_), 0, "no borrow");
        assertEq(morpho.collateral(marketParams.id(), BORROWER_), finalAmountCollateral, "no collateral");
        assertEq(morpho.expectedBorrowAssets(marketParams, BORROWER_), loanAmount, "no collateral");

        /// end of testLeverageMe
        vm.prank(BORROWER_);
        uint256 amountRepaid = snippets.deLeverageMe(marketParams);

        assertEq(morpho.borrowShares(marketParams.id(), BORROWER_), 0, "no borrow");
        assertEq(amountRepaid, loanAmount, "no repaid");
        assertEq(
            ERC20(marketParams.collateralToken).balanceOf(BORROWER_),
            initAmountCollateral,
            "user didn't get back his assets"
        );
    }
}

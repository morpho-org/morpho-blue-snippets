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

    ISwap internal swapper;

    LeverageDeleverageSnippets public snippets;

    function setUp() public virtual override {
        super.setUp();

        swapper = ISwap(address(new SwapMock(address(collateralToken), address(loanToken), address(oracle))));
        snippets = new LeverageDeleverageSnippets(morpho, swapper);

        vm.startPrank(BORROWER);
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
        collateralToken.setBalance(BORROWER, initAmountCollateral);

        vm.prank(SUPPLIER);
        morpho.supply(marketParams, finalAmountCollateral, 0, SUPPLIER, hex"");

        vm.prank(BORROWER);
        snippets.leverageMe(leverageFactor, initAmountCollateral, marketParams);

        uint256 loanAmount = initAmountCollateral * (leverageFactor - 1);

        assertGt(morpho.borrowShares(marketParams.id(), BORROWER), 0, "no borrow");
        assertEq(morpho.collateral(marketParams.id(), BORROWER), finalAmountCollateral, "no collateral");
        assertEq(morpho.expectedBorrowAssets(marketParams, BORROWER), loanAmount, "no collateral");
    }

    function testOnlyMorphoEnforcementSupplyCollateral() public {
        address maliciousUser = makeAddr("maliciousUser");
        vm.prank(maliciousUser);
        vm.expectRevert(bytes("msg.sender should be Morpho Blue"));
        snippets.onMorphoSupplyCollateral(0, abi.encodeWithSelector(snippets.onMorphoSupplyCollateral.selector, 0, ""));
    }

    function testOnlyMorphoEnforcementRepay() public {
        address maliciousUser = makeAddr("maliciousUser");
        vm.prank(maliciousUser);
        vm.expectRevert(bytes("msg.sender should be Morpho Blue"));
        snippets.onMorphoRepay(0, abi.encodeWithSelector(snippets.onMorphoRepay.selector, 0, ""));
    }

    function testDeLeverageMe(uint256 initAmountCollateral, uint256 leverageFactor) public {
        uint256 maxLeverageFactor = WAD / (WAD - marketParams.lltv);

        leverageFactor = bound(leverageFactor, 2, maxLeverageFactor);
        initAmountCollateral = bound(initAmountCollateral, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT / leverageFactor);
        uint256 finalAmountCollateral = initAmountCollateral * leverageFactor;

        oracle.setPrice(ORACLE_PRICE_SCALE);
        loanToken.setBalance(SUPPLIER, finalAmountCollateral);
        collateralToken.setBalance(BORROWER, initAmountCollateral);

        vm.prank(SUPPLIER);
        morpho.supply(marketParams, finalAmountCollateral, 0, SUPPLIER, hex"");

        uint256 loanAmount = initAmountCollateral * (leverageFactor - 1);

        vm.prank(BORROWER);
        snippets.leverageMe(leverageFactor, initAmountCollateral, marketParams);

        assertGt(morpho.borrowShares(marketParams.id(), BORROWER), 0, "no borrow");
        assertEq(morpho.collateral(marketParams.id(), BORROWER), finalAmountCollateral, "no collateral");
        assertEq(morpho.expectedBorrowAssets(marketParams, BORROWER), loanAmount, "no collateral");

        vm.prank(BORROWER);
        uint256 amountRepaid = snippets.deLeverageMe(marketParams);

        assertEq(morpho.borrowShares(marketParams.id(), BORROWER), 0, "no borrow");
        assertEq(amountRepaid, loanAmount, "no repaid");
        assertEq(
            ERC20(marketParams.collateralToken).balanceOf(BORROWER),
            initAmountCollateral,
            "user didn't get back his assets"
        );
    }
}

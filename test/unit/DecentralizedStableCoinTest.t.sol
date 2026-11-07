// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin dsc;
    address owner = makeAddr("owner");
    address user = makeAddr("user");

    function setUp() public {
        dsc = new DecentralizedStableCoin(owner);
    }

    function testNameAndSymbol() public view {
        assertEq(dsc.name(), "DecentralizedStableCoin");
        assertEq(dsc.symbol(), "DSC");
    }

    function testOwnerCanMint() public {
        vm.prank(owner);
        bool ok = dsc.mint(user, 100e18);
        assertTrue(ok);
        assertEq(dsc.balanceOf(user), 100e18);
    }

    function testCannotMintToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__NotZeroAddress.selector);
        dsc.mint(address(0), 1e18);
    }

    function testCannotMintZero() public {
        vm.prank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.mint(user, 0);
    }

    function testNonOwnerCannotMint() public {
        vm.prank(user);
        vm.expectRevert();
        dsc.mint(user, 1e18);
    }

    function testOwnerCanBurn() public {
        vm.startPrank(owner);
        dsc.mint(owner, 50e18);
        dsc.burn(20e18);
        vm.stopPrank();
        assertEq(dsc.balanceOf(owner), 30e18);
    }

    function testCannotBurnZero() public {
        vm.prank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.burn(0);
    }

    function testCannotBurnMoreThanBalance() public {
        vm.startPrank(owner);
        dsc.mint(owner, 10e18);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(11e18);
        vm.stopPrank();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {StellaToken} from "../src/ERC20/StellaToken.sol";

// forge build + forge test -vv
contract StellaTokenTest is Test {
    StellaToken public token;

    address public owner;
    address public alice;
    address public bob;

    string constant NAME = "StellaToken";
    string constant SYMBOL = "STL";
    uint256 constant INITIAL_SUPPLY = 1_000_000; // 1 million tokens

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        token = new StellaToken(NAME, SYMBOL, INITIAL_SUPPLY);
    }

    // ============ Deployment Tests ============

    function test_Deployment() public view {
        assertEq(token.name(), NAME);
        assertEq(token.symbol(), SYMBOL);
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), INITIAL_SUPPLY * 10 ** 18);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY * 10 ** 18);
        assertEq(token.owner(), owner);
    }

    // ============ ERC20 Transfer Tests ============

    function test_Transfer() public {
        uint256 amount = 1000 * 10 ** 18;

        bool success = token.transfer(alice, amount);

        assertTrue(success);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY * 10 ** 18 - amount);
    }

    function test_TransferFuzz(uint256 amount) public {
        amount = bound(amount, 0, token.balanceOf(owner));

        bool success = token.transfer(alice, amount);

        assertTrue(success);
        assertEq(token.balanceOf(alice), amount);
    }

    function test_RevertWhen_TransferExceedsBalance() public {
        uint256 excessAmount = INITIAL_SUPPLY * 10 ** 18 + 1;

        vm.expectRevert();
        token.transfer(alice, excessAmount);
    }

    // ============ ERC20 Approve & TransferFrom Tests ============

    function test_Approve() public {
        uint256 amount = 500 * 10 ** 18;

        bool success = token.approve(alice, amount);

        assertTrue(success);
        assertEq(token.allowance(owner, alice), amount);
    }

    function test_TransferFrom() public {
        uint256 approveAmount = 500 * 10 ** 18;
        uint256 transferAmount = 200 * 10 ** 18;

        token.approve(alice, approveAmount);

        vm.prank(alice);
        bool success = token.transferFrom(owner, bob, transferAmount);

        assertTrue(success);
        assertEq(token.balanceOf(bob), transferAmount);
        assertEq(token.allowance(owner, alice), approveAmount - transferAmount);
    }

    function test_RevertWhen_TransferFromExceedsAllowance() public {
        uint256 approveAmount = 100 * 10 ** 18;
        uint256 transferAmount = 200 * 10 ** 18;

        token.approve(alice, approveAmount);

        vm.prank(alice);
        vm.expectRevert();
        token.transferFrom(owner, bob, transferAmount);
    }

    // ============ Mint Tests ============

    function test_Mint() public {
        uint256 mintAmount = 1000 * 10 ** 18;
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 totalSupplyBefore = token.totalSupply();

        token.mint(alice, mintAmount);

        assertEq(token.balanceOf(alice), aliceBalanceBefore + mintAmount);
        assertEq(token.totalSupply(), totalSupplyBefore + mintAmount);
    }

    function test_MintFuzz(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 0, type(uint256).max - token.totalSupply());

        uint256 balanceBefore = token.balanceOf(to);
        uint256 totalSupplyBefore = token.totalSupply();

        token.mint(to, amount);

        assertEq(token.balanceOf(to), balanceBefore + amount);
        assertEq(token.totalSupply(), totalSupplyBefore + amount);
    }

    function test_RevertWhen_MintByNonOwner() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, mintAmount);
    }

    // ============ Burn Tests ============

    function test_Burn() public {
        uint256 burnAmount = 1000 * 10 ** 18;
        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 totalSupplyBefore = token.totalSupply();

        token.burn(owner, burnAmount);

        assertEq(token.balanceOf(owner), ownerBalanceBefore - burnAmount);
        assertEq(token.totalSupply(), totalSupplyBefore - burnAmount);
    }

    function test_BurnFuzz(uint256 amount) public {
        amount = bound(amount, 0, token.balanceOf(owner));

        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 totalSupplyBefore = token.totalSupply();

        token.burn(owner, amount);

        assertEq(token.balanceOf(owner), ownerBalanceBefore - amount);
        assertEq(token.totalSupply(), totalSupplyBefore - amount);
    }

    function test_RevertWhen_BurnByNonOwner() public {
        uint256 burnAmount = 1000 * 10 ** 18;

        // Give alice some tokens first
        token.transfer(alice, burnAmount);

        vm.prank(alice);
        vm.expectRevert();
        token.burn(alice, burnAmount);
    }

    function test_RevertWhen_BurnExceedsBalance() public {
        uint256 burnAmount = INITIAL_SUPPLY * 10 ** 18 + 1;

        vm.expectRevert();
        token.burn(owner, burnAmount);
    }

    // ============ Ownership Tests ============

    function test_TransferOwnership() public {
        token.transferOwnership(alice);

        assertEq(token.owner(), alice);
    }

    function test_NewOwnerCanMint() public {
        token.transferOwnership(alice);

        uint256 mintAmount = 1000 * 10 ** 18;

        vm.prank(alice);
        token.mint(bob, mintAmount);

        assertEq(token.balanceOf(bob), mintAmount);
    }

    function test_RevertWhen_OldOwnerTriesToMintAfterTransfer() public {
        token.transferOwnership(alice);

        vm.expectRevert();
        token.mint(bob, 1000 * 10 ** 18);
    }

    function test_RenounceOwnership() public {
        token.renounceOwnership();

        assertEq(token.owner(), address(0));
    }

    function test_RevertWhen_MintAfterRenounceOwnership() public {
        token.renounceOwnership();

        vm.expectRevert();
        token.mint(alice, 1000 * 10 ** 18);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "src/LaunchToken.sol";

contract TokenSpendingForwarder {
    function pull(LaunchToken token, address owner, address to, uint256 amount) external {
        token.transferFrom(owner, to, amount);
    }
}

/// @dev Complements the existing deployment and ERC-20 tests with authorization and boundary properties.
/// forge-config: default.fuzz.runs = 1000
contract LaunchTokenAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    LaunchToken internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new LaunchToken();
        alice = makeAddr("adversarial alice");
        bob = makeAddr("adversarial bob");
        spender = makeAddr("adversarial spender");
    }

    function test_zeroTransferFromNeedsNoAllowanceAndEmitsTransfer() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_delegatedSelfTransferConsumesAllowanceWithoutMovingBalance() public {
        token.approve(spender, SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), address(this), 1);
    }

    function test_selfTransferCannotExceedBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ownerUsingTransferFromStillNeedsItsOwnApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_maxMinusOneAllowanceIsFinite() public {
        token.approve(spender, type(uint256).max - 1);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY - 1));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maxTransferWithInfiniteApprovalRevertsWithoutChangingState() public {
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteApprovalSurvivesEmptyBalanceAndRefill() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_txOriginCannotLendItsAllowanceToForwarder() public {
        TokenSpendingForwarder forwarder = new TokenSpendingForwarder();
        token.transfer(alice, SUPPLY);
        vm.prank(alice);
        token.approve(alice, SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(forwarder), 0, 1)
        );
        vm.prank(alice, alice);
        forwarder.pull(token, alice, bob, 1);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, alice), SUPPLY);
        assertEq(token.allowance(alice, address(forwarder)), 0);
    }

    function test_constructorRejectsEther() public {
        bytes memory creationCode = type(LaunchToken).creationCode;
        vm.deal(address(this), 1);
        address deployed;
        assembly ("memory-safe") {
            deployed := create(1, add(creationCode, 32), mload(creationCode))
        }
        assertEq(deployed, address(0), "constructor accepted ETH");
        assertEq(address(this).balance, 1);
    }

    function test_knownMutatorsRejectEtherWithoutChangingState() public {
        token.approve(address(this), 5);
        bytes[3] memory calls = [
            abi.encodeCall(token.transfer, (alice, 1)),
            abi.encodeCall(token.approve, (spender, 1)),
            abi.encodeCall(token.transferFrom, (address(this), alice, 1))
        ];
        vm.deal(address(this), 3);
        for (uint256 i; i < calls.length; ++i) {
            (bool success,) = address(token).call{value: 1}(calls[i]);
            assertFalse(success, "nonpayable mutator accepted ETH");
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.allowance(address(this), address(this)), 5);
            assertEq(token.allowance(address(this), spender), 0);
        }
        assertEq(address(token).balance, 0);
        assertEq(address(this).balance, 3);
    }

    function test_truncatedMutatorArgumentsRevertWithoutChangingState() public {
        token.approve(address(this), 5);
        bytes[3] memory calls = [
            abi.encodeWithSelector(token.transfer.selector, alice),
            abi.encodeWithSelector(token.approve.selector, spender),
            abi.encodeWithSelector(token.transferFrom.selector, address(this), alice)
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool success,) = address(token).call(calls[i]);
            assertFalse(success, "truncated arguments accepted");
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.allowance(address(this), address(this)), 5);
            assertEq(token.allowance(address(this), spender), 0);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_zeroSpenderRejectedAtApprovalBoundaries() public {
        uint256[3] memory amounts = [uint256(0), 1, type(uint256).max];
        for (uint256 i; i < amounts.length; ++i) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            token.approve(address(0), amounts[i]);
            assertEq(token.allowance(address(this), address(0)), 0);
            assertEq(token.balanceOf(address(this)), SUPPLY);
        }
    }

    function testFuzz_insufficientBalanceRollsBackAllowance(
        uint256 balance,
        uint256 amount,
        uint256 approval,
        bool infinite
    ) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max - 1);
        approval = infinite ? type(uint256).max : bound(approval, amount, type(uint256).max - 1);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, approval);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approval);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_allowancesAreScopedToOwnerAndSpender(uint256 approval, uint256 unrelated, uint256 amount) public {
        token.transfer(alice, SUPPLY / 2);
        token.transfer(bob, SUPPLY / 2);
        vm.startPrank(alice);
        token.approve(spender, approval);
        token.approve(bob, unrelated);
        vm.stopPrank();
        vm.prank(bob);
        token.approve(spender, unrelated);
        amount = bound(amount, 0, approval < SUPPLY / 2 ? approval : SUPPLY / 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), approval == type(uint256).max ? approval : approval - amount);
        assertEq(token.allowance(alice, bob), unrelated);
        assertEq(token.allowance(bob, spender), unrelated);
        assertEq(token.allowance(bob, alice), 0);
        assertEq(token.balanceOf(alice), SUPPLY / 2 - amount);
        assertEq(token.balanceOf(bob), SUPPLY / 2 + amount);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_loweredApprovalImmediatelyReplacesOldLimit(uint256 oldLimit, uint256 newLimit) public {
        newLimit = bound(newLimit, 0, SUPPLY - 1);
        oldLimit = bound(oldLimit, newLimit + 1, type(uint256).max);
        token.approve(spender, oldLimit);
        token.approve(spender, newLimit);
        uint256 amount = newLimit + 1;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, newLimit, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), newLimit);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_infiniteApprovalCanBeRevokedAfterSpend(uint256 amount) public {
        amount = bound(amount, 1, SUPPLY - 1);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splitDelegatedTransfersMatchSingleTransfer(uint256 total, uint256 first) public {
        LaunchToken singleTransferToken = new LaunchToken();
        total = bound(total, 0, SUPPLY);
        first = bound(first, 0, total);
        token.approve(spender, SUPPLY);
        singleTransferToken.approve(spender, SUPPLY);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertTrue(token.transferFrom(address(this), alice, total - first));
        assertTrue(singleTransferToken.transferFrom(address(this), alice, total));
        vm.stopPrank();
        assertEq(token.balanceOf(alice), singleTransferToken.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), singleTransferToken.balanceOf(address(this)));
        assertEq(token.allowance(address(this), spender), singleTransferToken.allowance(address(this), spender));
        assertEq(token.balanceOf(alice), total);
        assertEq(token.totalSupply(), SUPPLY);
    }
}

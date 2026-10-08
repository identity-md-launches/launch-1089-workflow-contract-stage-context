// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

/// @dev Bounded actors keep every token inside the accounting model.
contract TokenHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    LaunchToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(LaunchToken token_) {
        token = token_;
        actors = [makeAddr("holder 0"), makeAddr("holder 1"), makeAddr("holder 2"), makeAddr("holder 3")];
        expectedBalance[actors[0]] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        address to = actors[toSeed % 4];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, 0, allowed < balance ? allowed : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
    }

    /// @dev Explicitly reach revocation and the finite/infinite allowance boundary.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 mode) external {
        uint256[5] memory amounts = [uint256(0), 1, SUPPLY, type(uint256).max - 1, type(uint256).max];
        _approve(actors[ownerSeed % 4], actors[spenderSeed % 4], amounts[mode % 5]);
    }

    /// @dev Drain a funded actor and return the full balance. Neither fees nor dust may remain.
    function roundTripFullBalance(uint256 fromSeed, uint256 toSeed) external {
        address from = _fundedActor(fromSeed);
        address to = actors[toSeed % 4];
        if (to == from) to = actors[(toSeed % 4 + 1) % 4];
        uint256 amount = expectedBalance[from];
        uint256 recipientBefore = expectedBalance[to];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(to), recipientBefore + amount);
        assertEq(token.totalSupply(), SUPPLY);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        // Ghost state deliberately stays unchanged: this composite operation is an identity.
        assertEq(token.balanceOf(from), amount);
        assertEq(token.balanceOf(to), recipientBefore);
    }

    /// @dev Each invocation performs a positive delegated spend and a rejected replay.
    function spendThenRejectReplay(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = _fundedActor(ownerSeed);
        address spender = actors[spenderSeed % 4];
        address to = actors[toSeed % 4];
        amount = bound(amount, 1, expectedBalance[owner]);
        _approve(owner, spender, amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedAllowance[owner][spender] = 0;
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        _expectFailure(
            spender,
            abi.encodeCall(token.transferFrom, (owner, to, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, amount)
        );
    }

    function rejectExcessBalance(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 4];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        _expectFailure(
            from,
            abi.encodeCall(token.transfer, (actors[toSeed % 4], amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function rejectDelegatedExcessBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, balance + 1, type(uint256).max);
        _approve(owner, spender, amount);
        // Allowance validation succeeds before the balance failure; its debit must roll back.
        _expectFailure(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
        );
    }

    function rejectExcessAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = _fundedActor(ownerSeed);
        address spender = actors[spenderSeed % 4];
        amount = bound(amount, 1, expectedBalance[owner]);
        _approve(owner, spender, amount - 1);
        _expectFailure(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, amount - 1, amount)
        );
    }

    function rejectZeroReceiver(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        amount = bound(amount, 0, expectedBalance[owner]);
        bytes memory error = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        if (delegated) {
            _approve(owner, spender, amount);
            _expectFailure(spender, abi.encodeCall(token.transferFrom, (owner, address(0), amount)), error);
        } else {
            _expectFailure(owner, abi.encodeCall(token.transfer, (address(0), amount)), error);
        }
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _fundedActor(uint256 seed) internal view returns (address) {
        for (uint256 i; i < 4; ++i) {
            address actor = actors[(seed % 4 + i) % 4];
            if (expectedBalance[actor] > 0) return actor;
        }
        revert("model lost the fixed supply");
    }

    function _expectFailure(address caller, bytes memory data, bytes memory error) internal {
        vm.prank(caller);
        (bool success, bytes memory returned) = address(token).call(data);
        assertFalse(success, "invalid operation succeeded");
        assertEq(returned, error, "unexpected failure reason");
        // No ghost update: the invariant checks ALL balances and allowances after the rejection.
    }
}

contract LaunchTokenInvariantTest is Test {
    LaunchToken internal token;
    TokenHandler internal handler;

    function setUp() public {
        token = new LaunchToken();
        handler = new TokenHandler(token);
        token.transfer(handler.actors(0), token.totalSupply());
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.approveBoundary.selector;
        selectors[4] = TokenHandler.roundTripFullBalance.selector;
        selectors[5] = TokenHandler.spendThenRejectReplay.selector;
        selectors[6] = TokenHandler.rejectExcessBalance.selector;
        selectors[7] = TokenHandler.rejectDelegatedExcessBalance.selector;
        selectors[8] = TokenHandler.rejectExcessAllowance.selector;
        selectors[9] = TokenHandler.rejectZeroReceiver.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_supplyBalancesAndAllowancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            sum += balance;
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(actor, spender), handler.expectedAllowance(actor, spender));
            }
        }
        assertEq(sum, 1_000_000_000 ether);
        assertEq(token.totalSupply(), sum);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }
}

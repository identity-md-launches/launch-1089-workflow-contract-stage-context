# LaunchToken ABI

[`abi/LaunchToken.json`](abi/LaunchToken.json) is the complete compiler-generated
JSON ABI for `src/LaunchToken.sol:LaunchToken`, including errors and events.
Amounts and allowances are unsigned 256-bit integers in minor units; one Brain
equals `1000000000000000000` units.

| Entry point | Behavior |
| --- | --- |
| `constructor()` | Nonpayable; mints `10^27` units to the deploying caller. |
| `name() -> string` | Returns `Swarm brain`. |
| `symbol() -> string` | Returns `Brain`. |
| `decimals() -> uint8` | Returns `18`. |
| `totalSupply() -> uint256` | Always returns `10^27`. |
| `balanceOf(address) -> uint256` | Returns the address's current balance. |
| `allowance(address owner, address spender) -> uint256` | Returns the remaining authorization. |
| `transfer(address to, uint256 value) -> bool` | Moves exactly `value` from the caller. |
| `approve(address spender, uint256 value) -> bool` | Replaces the caller's allowance for `spender`. Zero revokes it. |
| `transferFrom(address from, address to, uint256 value) -> bool` | Moves exactly `value` using the caller's allowance from `from`. |

All three state-changing methods are nonpayable and return `true` on success.
There are no privileged methods, permit signatures, payable entry points, or
fallback handlers. Failed operations revert all balance and allowance changes.

## Events

- `Transfer(address indexed from, address indexed to, uint256 value)`: emitted
  for construction minting (`from` is zero) and every successful transfer,
  including zero-value transfers.
- `Approval(address indexed owner, address indexed spender, uint256 value)`:
  emitted for explicit approvals, replacements, and revocations. The inherited
  implementation does **not** emit it when `transferFrom` spends an allowance;
  indexers should query `allowance` for authoritative current state.

## Errors

- `ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed)`:
  the debit exceeds the sender's available balance.
- `ERC20InvalidSender(address sender)`: zero sender on a transfer.
- `ERC20InvalidReceiver(address receiver)`: zero destination on a transfer.
- `ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed)`:
  the caller lacks sufficient delegated authorization.
- `ERC20InvalidApprover(address approver)`: zero approving address.
- `ERC20InvalidSpender(address spender)`: zero spender on an approval.

`transferFrom` checks the allowance before transfer validation. When multiple
inputs are invalid, integrations should not assume the balance/recipient error
will take precedence. Maximum uint256 allowance is treated as unlimited and is
not decremented. Zero-value transfers still validate nonzero sender/recipient.

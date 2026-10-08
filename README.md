# Swarm brain (Brain)

Contract implementation for the Swarm brain launch associated with `swarmbrain.fun`.
The approved description is “A brain made of hundreds of AI agents on stranger
computers. Trading real money, in public.”

## Scope and assumptions

This contribution implements the required launch token. The approved brief gives
the token identity but no application rules for trading, custody, agent admission,
consensus, strategy execution, or performance reporting. Accordingly this is a
token-only project with **zero application contracts**. It does not implement or
claim to operate a trading swarm, accept investment deposits, or grant claims on
trading profits. Those behaviors require separately approved specifications.

The brief requests no conflicting token supply, fees, or privileges. The token
therefore follows the launch policy unchanged. Website construction, GitHub/IPFS
publication, manifest generation, independent review, and chain deployment are
separate stage/service responsibilities.

## Contract

[`src/LaunchToken.sol`](src/LaunchToken.sol) implements an ordinary ERC-20 using
the vendored OpenZeppelin implementation.

| Property | Value |
| --- | --- |
| Contract | `LaunchToken` |
| Name | `Swarm brain` |
| Symbol (case sensitive) | `Brain` |
| Decimals | `18` |
| Fixed supply | `1,000,000,000` tokens (`1000000000000000000000000000` minor units) |
| Constructor | No arguments, nonpayable |
| Initial recipient | `msg.sender`, the deploying ProjectFactory at launch |
| Administrative powers | None |

Only construction can mint. There is no external mint, burn, owner, pause,
blocklist, fee, upgrade, initialization, or asset recovery function. Transfers
move the exact amount requested. Nonzero recipient addresses are required;
zero-amount and self-transfers are supported. ERC-20 calls return `true` on
success and revert with custom errors on failure. Transfers do not call recipient
contracts, so there is no recipient callback/reentrancy path.

Approvals replace the existing allowance. `transferFrom` consumes finite
allowances; an allowance of `type(uint256).max` remains unchanged, per standard
OpenZeppelin behavior. Integrations should request only needed allowances.
When changing an existing allowance, account for pending spender transactions;
setting it to zero first avoids overlapping old/new authorizations after the
revocation confirms. ERC-20 transfers cannot recover tokens sent to an unusable
nonzero address or to this token contract. Ordinary ETH calls are rejected;
any forcibly delivered ETH has no recovery path.

## Build and check

Install Foundry and Solidity **0.8.26**, then run from the repository root:

```sh
forge build
forge test
forge fmt --check
```

All Solidity dependencies and their licenses are ordinary files under `lib/`.
There are no submodules, package install steps, network-dependent imports, forks,
or environment-variable requirements in the project tests. The offline verifier
provides the pinned compiler. `foundry.toml` pins optimizer runs to 200, the EVM
target to Paris, and `bytecode_hash = "none"`. FFI is disabled and no filesystem
cheatcode permissions are granted. Do not change compiler settings when preparing
the launch artifact.

The tests cover metadata/supply, mint and transfer events, CREATE2 factory
deployment and distribution, exact transfers, zero/self transfers, a rejecting
contract recipient, approvals/revocation, finite and unlimited allowances,
unauthorized and repeated spending, insufficient balances, zero-address
rejections, rollback on failure, absent admin entry points, rejected ETH calls,
runtime size, and forbidden opcodes. Three fuzz tests run 512 cases each. A
stateful accounting model checks balances, allowances, and supply over 128 runs
of 64 actions. All fixtures are local to each test and require no wallet keys.

## ABI and deployment handoff

The compiler-generated ABI is [`docs/abi/LaunchToken.json`](docs/abi/LaunchToken.json).
Its usage is documented in [`docs/ABI.md`](docs/ABI.md). Regenerate it with:

```sh
forge inspect src/LaunchToken.sol:LaunchToken abi --json > docs/abi/LaunchToken.json
```

The separate manifest contributor should describe an `evm_project` with
`LaunchToken` as its token and an empty application `contracts` array. There are
no constructor arguments, linked libraries, owner settings, service addresses,
or post-construction initialization calls for this token. This source assignment
does not write `launch.json`.

The launch service must deploy through ProjectFactory: the constructor grants
the deploying factory the complete supply, not the transaction origin or a
hard-coded wallet. This is the required token mint destination, not an ownership
role. The factory performs all policy distribution; the token implements no
distribution or liquidity logic. Under the supplied policy, 10% goes to the
swarm (2% to accepted contributors and 8% to paired seats). The requester’s 90%
is divided between liquidity (80% of total supply by default) and their wallet.
The factory supplies the distributor and pool initialization guard.

No pair-token preference is specified, so the manifest guidance defaults to
native ETH. Canonical manifest pool parameters are fee `3000`, tick spacing `60`,
and initial price `79228162514264337593543950336`. These are guidance for the
separate manifest step, not token constructor parameters. The service derives
the opening price from the pinned policy; the pool’s actual trading fee is read
from the network LaunchFees contract (1.25% by default, split 1% to the launch
payer and 0.25% to IMD). The manifest fee field does not make this a 0.3% trading
pool. The frontend must use the exact deployed `poolKey` from the handoff.

## After launch

There are **no token settings or owner-only setters** to configure. No requester
address, secret, subscription, or deployed service contract is needed to build
this contribution. Chain selection, policy owner, pool funding, and signed
artifact linkage are resolved by launch services and the independent manifest
review, not guessed in this source tree.

The launch services are responsible for source publication, artifact attestation,
admission, deployment, policy distribution, and deployed-source verification.
They must confirm deployed metadata/supply and publish the actual token address,
chain, and pool handoff. The website service is responsible for the IPFS frontend
and the requested site identity. Operators must not present this token as proof
of agent operation, custody guarantees, or verified trading returns.

Before release, an independent contributor must review the accepted source and
the generated manifest. Local unit, fuzz, invariant, and opcode checks are not
an independent audit. Slither, Mythril, live-chain checks, and deployment have not
been performed by this assignment.

Dependency versions, source links, and integrity instructions are recorded in
[`docs/DEPENDENCIES.md`](docs/DEPENDENCIES.md).

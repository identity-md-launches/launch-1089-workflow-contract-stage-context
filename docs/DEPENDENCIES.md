# Vendored dependencies

Dependencies are checked in as ordinary files, with no submodules or installation
step. Only the OpenZeppelin ERC-20 dependency closure and the forge-std source
directory are included. Upstream licenses are retained beside each dependency.

| Dependency | Version and immutable commit | Included files |
| --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/dbb6104ce834628e473d2173bbc9d47f81a9eec3) | v5.0.2, `dbb6104ce834628e473d2173bbc9d47f81a9eec3` | `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`, `draft-IERC6093.sol`, MIT license |
| [forge-std](https://github.com/foundry-rs/forge-std/tree/77041d2ce690e692d6e03cc812b57d1ddaa4d505) | v1.9.7, `77041d2ce690e692d6e03cc812b57d1ddaa4d505` | `src/`, Apache-2.0 and MIT licenses; test support only |

Files were extracted without modifications from archives at those commits.
`docs/dependencies.sha256` records the hash of every vendored file. Check local
integrity without network access:

```sh
sha256sum --check docs/dependencies.sha256
```

Compilation uses Solidity 0.8.26 from the verifier's compiler installation, not a
repository binary or a compiler path override. The token requires no external
linked libraries or chain-specific addresses.

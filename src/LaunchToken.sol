// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Swarm brain launch token
/// @notice Fixed supply of one billion Brain tokens with 18 decimals.
/// @dev The deploying ProjectFactory receives the entire supply for protocol distribution.
/// There are no privileged roles or external mint, burn, or upgrade entry points.
contract LaunchToken is ERC20 {
    constructor() ERC20("Swarm brain", "Brain") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}

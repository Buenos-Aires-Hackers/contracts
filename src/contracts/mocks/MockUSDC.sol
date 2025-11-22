// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDC
/// @notice Mock USDC token for testing and deployment
/// @dev Mintable ERC20 token with 6 decimals matching real USDC
contract MockUSDC is ERC20 {
    uint8 private constant _decimals = 6;

    constructor() ERC20("USD Coin", "USDC") {
        // No initial supply
    }

    /// @notice Mint tokens to an address
    /// @param to Address to mint tokens to
    /// @param amount Amount of tokens to mint (in token units, not wei)
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Burn tokens from an address
    /// @param from Address to burn tokens from
    /// @param amount Amount of tokens to burn (in token units, not wei)
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    /// @notice Returns the number of decimals for the token
    /// @return The number of decimals (6 for USDC)
    function decimals() public pure override returns (uint8) {
        return _decimals;
    }
}


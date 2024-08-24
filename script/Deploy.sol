// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {HubUp} from "contracts/HubUp.sol";
import "forge-std/console.sol";

contract USDC is ERC20 {
    constructor(uint256 initialSupply, address owner) ERC20("USDC", "USDC") {
        _mint(owner, initialSupply);
    }
}

contract Deploy is Script {
    // Define the initial supply for the USDC token (e.g., 1 million tokens with 18 decimals)
    uint256 constant initialSupply = 1_000_000 * 10 ** 18; // 1 million tokens with 18 decimals

    function run() public {
        vm.startBroadcast();

        // Step 1: Deploy the USDC token and mint all supply to the owner
        address owner = msg.sender;
        USDC token = new USDC(initialSupply, owner);

        // Step 2: Deploy the HubUp contract with the USDC token's address
        HubUp hubUp = new HubUp(address(token));

        vm.stopBroadcast();

        // Print the deployed addresses
        console.log("USDC Token Address:", address(token));
        console.log("HubUp Contract Address:", address(hubUp));
    }
}

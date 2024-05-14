// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VivacityLaunchPool} from "./VivacityMPool.sol";

contract VivacityLaunchPad {
    address[] launchPools;

    function createLaunchPool(
        string memory name,
        string memory symbol,
        uint256 maxSupply,
        uint256 creatorSupply,
        uint256 saleStartTime,
        uint256 saleDuration,
        address[] memory whitelists,
        uint256[] memory amounts,
        uint256[3] memory _ratios
    ) external {
        require(saleStartTime > block.timestamp, "start time cannot be in past!");
        require(
            saleDuration >= (86400 * 5) && saleDuration <= (86400 * 7), "sale duration has to be between 5 to 7 days"
        );
        require(maxSupply >= 100e18, "total supply should not be less than 100");

        require(creatorSupply >= ((10 * maxSupply) / 100), "creator supply should be minimum 10%");
        uint256 allocatedSupply = creatorSupply;
        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] <= ((20 * maxSupply) / 100), "supply of each whitelist should not be more than 20%");
            allocatedSupply += amounts[i];
        }
        require(
            allocatedSupply <= ((50 * maxSupply) / 100),
            "whitelist + creator supply should be less than or equal to 50%"
        );

        VivacityLaunchPool pool = new VivacityLaunchPool(
            name,
            symbol,
            maxSupply,
            creatorSupply,
            allocatedSupply,
            saleStartTime,
            saleDuration,
            msg.sender,
            whitelists,
            amounts,
            _ratios
        );
        launchPools.push(address(pool));
    }

    function getLaunchPoolAddress(uint256 index) public view returns (address) {
        return launchPools[index];
    }
}

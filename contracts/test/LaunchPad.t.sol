// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {LaunchPad} from "../src/LaunchPad.sol";
import {LaunchPool} from "../src/LaunchPool.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Comptroller} from "../lib/clm/src/Comptroller.sol";
import {CToken} from "../lib/clm/src/CToken.sol";

contract LaunchPadTest is Test {
    LaunchPad public launchpad;
    address whitelist1 = makeAddr("whitelist-1");
    address creator = makeAddr("creator");
    address buyer = makeAddr("buyer");
    address eth_token = 0xCa03230E7FB13456326a234443aAd111AC96410A;
    address atmo_token = 0x40E41DC5845619E7Ba73957449b31DFbfB9678b2;
    string name = "NoRug Token";
    string symbol = "NRT";
    uint256 maxSupply = 10000e18;
    uint256 creatorSupply = 1000e18;
    uint256 saleStartTime = block.timestamp + 1000;
    uint256 saleDuration = 86400 * 5;
    address[] whitelists = new address[](1);
    uint256[] amounts = new uint256[](1);
    uint256[2] ratios = [1, 1];

    function setUp() public {
        launchpad = new LaunchPad();
        whitelists[0] = whitelist1;
        amounts[0] = 100e18;
        vm.prank(creator);
        launchpad.createLaunchPool(
            name, symbol, maxSupply, creatorSupply, saleStartTime, saleDuration, whitelists, amounts, ratios
        );
    }

    function testCreateLaunchPool() public view {
        address poolAddress = launchpad.getLaunchPoolAddress(0);
        assertTrue(poolAddress != address(0));

        LaunchPool pool = LaunchPool(poolAddress);
        assertEq(pool.name(), name);
        assertEq(pool.symbol(), symbol);
        assertEq(pool.saleStartTime(), saleStartTime);
        assertEq(pool.saleDuration(), saleDuration);
        assertEq(pool.whitelist(0), whitelist1);
        assertEq(pool.amounts(0), 100e18);
    }

    function testComp() public view {
        Comptroller unitest = Comptroller(0xe49627059Dd2A0fba4A81528207231C508d276CB);
        CToken[] memory cTokens = unitest.getAllMarkets();
    }

    // function testBuy() public {
    //     address poolAddress = launchpad.getLaunchPoolAddress(0);
    //     LaunchPool pool = LaunchPool(poolAddress);
    //     console.log("LaunchPool address: ", poolAddress);

    //     console.log("Buying tokens with ETH");
    //     ERC20 eth_erc20 = ERC20(eth_token);
    //     deal(address(eth_token), buyer, 100e18);
    //     vm.warp(block.timestamp + 86410 * 3);
    //     vm.startPrank(buyer);
    //     eth_erc20.approve(poolAddress, 1000e18);
    //     uint256 allowed = eth_erc20.allowance(buyer, poolAddress);
    //     console.log(allowed);
    //     skip(100);
    //     pool.buy(0, 10e18);
    //     vm.stopPrank();
    //     vm.warp(block.timestamp + 86410 * 6);
    //     pool.airdrop();
    //     assertEq(pool.balanceOf(buyer), 10e18);
    // }
}

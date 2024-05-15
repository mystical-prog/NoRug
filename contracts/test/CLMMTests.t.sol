// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {CLMMLaunchPool} from "../src/CLMMainnet/CLMMPool.sol";
import {CLMMLaunchPad} from "../src/CLMMainnet/CLMMPad.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Comptroller} from "../lib/clm/src/Comptroller.sol";
import {CToken} from "../lib/clm/src/CToken.sol";

interface FBILLToken {
    function approve(address spender, uint256 value) external returns (bool);
    function addToWhitelist(address account) external;
}

contract LaunchPadTest is Test {
    CLMMLaunchPad public launchpad;
    address whitelist1 = makeAddr("whitelist-1");
    address creator = makeAddr("creator");
    address buyer = makeAddr("buyer");
    address usyc_token = 0xFb8255f0De21AcEBf490F1DF6F0BDd48CC1df03B;
    address fbill_token = 0x79ECCE8E2D17603877Ff15BC29804CbCB590EC08;
    address ifbill_token = 0x45bafad5a6a531Bc18Cf6CE5B02C58eA4D20589b;
    string name = "NoRug Token";
    string symbol = "NRT";
    uint256 maxSupply = 10000e18;
    uint256 creatorSupply = 1000e18;
    uint256 saleStartTime = block.timestamp + 1000;
    uint256 saleDuration = 5 days;
    address[] whitelists = new address[](1);
    uint256[] amounts = new uint256[](1);
    uint256[3] ratios = [1, 1, 1];

    function setUp() public {
        launchpad = new CLMMLaunchPad();
        whitelists[0] = whitelist1;
        amounts[0] = 100e18;
        vm.prank(creator);
        launchpad.createLaunchPool(
            name, symbol, maxSupply, creatorSupply, saleStartTime, saleDuration, whitelists, amounts, ratios
        );
    }

    // function testCreateLaunchPool() public view {
    //     address poolAddress = launchpad.getLaunchPoolAddress(0);
    //     assertTrue(poolAddress != address(0));

    //     CLMMLaunchPool pool = CLMMLaunchPool(poolAddress);
    //     assertEq(pool.name(), name);
    //     assertEq(pool.symbol(), symbol);
    //     assertEq(pool.saleStartTime(), saleStartTime);
    //     assertEq(pool.saleDuration(), saleDuration);
    //     assertEq(pool.whitelist(0), whitelist1);
    //     assertEq(pool.amounts(0), 100e18);
    // }

    // function testComp() public view {
    //     Comptroller unitest = Comptroller(0x5E23dC409Fc2F832f83CEc191E245A191a4bCc5C);
    //     CToken[] memory cTokens = unitest.getAllMarkets();
    //     unitest.markets(0xEe602429Ef7eCe0a13e4FfE8dBC16e101049504C);
    // }

    function testBuy() public {
        address poolAddress = launchpad.getLaunchPoolAddress(0);
        CLMMLaunchPool pool = CLMMLaunchPool(poolAddress);

        FBILLToken fbill_erc20 = FBILLToken(fbill_token);

        // whitelisting poolAddress for fBILL token
        vm.startPrank(0xdCbE775Adc0158661E326Bfc827212C9BCa8Cc00);
        fbill_erc20.addToWhitelist(poolAddress);
        fbill_erc20.addToWhitelist(buyer);
        vm.stopPrank();

        console.log("Buying tokens with fBILL");
        deal(address(fbill_token), buyer, 100e18);
        deal(poolAddress, 100e18);
        vm.warp(block.timestamp + 86410 * 3);
        vm.startPrank(buyer);
        fbill_erc20.approve(poolAddress, 1000e18);
        skip(100);
        pool.buy(1, 100e18);
        vm.stopPrank();
        vm.warp(block.timestamp + 86410 * 6);
        pool.airdrop();
        assertEq(pool.balanceOf(buyer), 100e18);
    }
}

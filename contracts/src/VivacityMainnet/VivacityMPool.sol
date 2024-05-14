// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CErc20} from "../../lib/clm/src/CErc20.sol";
import {CToken} from "../../lib/clm/src/CToken.sol";
import {console} from "forge-std/Test.sol";

interface Comptroller {
    function enterMarkets(CToken[] calldata cTokens) external returns (uint[] memory);
    function getAccountLiquidity(address account) external view returns (uint, uint, uint);
    function getAllMarkets() external view returns (CToken[] memory);
}

interface BaseV1Router01 {
    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

// This implementation is created based on Mainnet utilising Vivacity
contract VivacityLaunchPool is ERC20 {
    uint256 public maxSupply;
    uint256 public allocatedSupply;
    uint256 public reservedSupply;
    uint256 public creatorSupply;
    uint256 public saleStartTime;
    uint256 public saleDuration;
    address public creator;
    address[] public whitelist;

    address public constant unitroller = 0xe49627059Dd2A0fba4A81528207231C508d276CB;
    address public constant vcNOTE = 0x74c6dBA944702007e3a18C2caad9F6F274cF38dD;

    // [ETH, ATOM, WCANTO]
    address[3] public assets = [
        0x5FD55A1B9FC24967C4dB09C513C3BA0DFa7FF687,
        0xecEEEfCEE421D8062EF8d6b4D814efe4dc898265,
        0x826551890Dc65655a0Aceca109aB11AbDbD7a07B
    ];
    mapping(address => address) public cTokenMapping;
    uint256[] public amounts;

    // ratios denote how many tokens will a buyer get in exchange of existing token
    // for eg. ratios[0] = 10*10**18 meaning each user will get 10 tokens for each NOTE
    uint256[3] public ratios;

    bool public airdropped;
    bool public whitelistdropped;
    bool public creatordropped;

    address[] public buyers;
    mapping(address => bool) exists;
    mapping(address => uint256) buyerAmounts;

    constructor(
        string memory name,
        string memory symbol,
        uint256 _maxSupply,
        uint256 _creatorSupply,
        uint256 _allocatedSupply,
        uint256 _saleStartTime,
        uint256 _saleDuration,
        address _creator,
        address[] memory _whitelist,
        uint256[] memory _amounts,
        uint256[3] memory _ratios
    ) ERC20(name, symbol) {
        maxSupply = _maxSupply;
        creatorSupply = _creatorSupply;
        allocatedSupply = _allocatedSupply;
        reservedSupply = (_maxSupply - _allocatedSupply) / 2;
        saleStartTime = _saleStartTime;
        saleDuration = _saleDuration;
        creator = _creator;
        whitelist = _whitelist;
        amounts = _amounts;
        ratios = _ratios;
        // asset -> vcAsset
        cTokenMapping[0x5FD55A1B9FC24967C4dB09C513C3BA0DFa7FF687] = 0x83A7Aa3a9f5E777Fd4BF02d26Adc8Ea5DDC1C20D;
        cTokenMapping[0xecEEEfCEE421D8062EF8d6b4D814efe4dc898265] = 0xAB8674A498d4C1Ef4a75B4e88df0BC2BC5e4F6A0;
        cTokenMapping[0x826551890Dc65655a0Aceca109aB11AbDbD7a07B] = 0x2Cc8C9B72bF126553F6226688be8C40ce408FaC8;
        // setting all bools to false
        airdropped = false;
        whitelistdropped = false;
        creatordropped = false;
    }

    function buy(uint8 asset_index, uint256 amount) external {
        require(amount > 0, "Invalid amount!");
        uint256 ratio = ratios[asset_index];
        uint256 requiredAmount = amount * ratio;
        console.log("RequiredAmt: ", requiredAmount);
        require(allocatedSupply + amount <= maxSupply - reservedSupply, "token sale has maxed out");
        require(
            IERC20(assets[asset_index]).transferFrom(msg.sender, address(this), requiredAmount),
            "Failed to transfer asset tokens!"
        );
        if (block.timestamp >= saleStartTime && block.timestamp <= saleStartTime + saleDuration) {
            if (!exists[msg.sender]) {
                buyers.push(msg.sender);
                exists[msg.sender] = true;
                buyerAmounts[msg.sender] = amount;
                allocatedSupply += amount;
            } else {
                buyerAmounts[msg.sender] += amount;
                allocatedSupply += amount;
            }
        } else {
            revert("Token sale has ended!");
        }
    }

    function airdrop() external {
        require(airdropped == false, "airdrop already took place, check your wallet");
        require(block.timestamp > saleStartTime + saleDuration, "airdrop not available yet!");

        clm_and_dex_calls();

        for (uint256 i = 0; i < buyers.length; i++) {
            address buyer = buyers[i];
            uint256 amount = buyerAmounts[buyer];
            if (amount > 0) {
                mint(buyer, amount);
                delete buyerAmounts[buyer];
            }
        }
        airdropped = true;
    }

    function whitelistdrop() external {
        require(whitelistdropped == false, "whitelist drop already took place, check your wallet");
        require(block.timestamp > saleStartTime + saleDuration + (86400 * 90), "whitelist drop not available yet!");
        for (uint256 i = 0; i < whitelist.length; i++) {
            uint256 amount = amounts[i];
            mint(whitelist[i], amount);
        }
        whitelistdropped = true;
    }

    function creatordrop() external {
        require(creatordropped == false, "creator drop already took place");
        require(block.timestamp > saleStartTime + saleDuration + (86400 * 180), "creator drop not available yet!");
        mint(creator, creatorSupply);
        creatordropped = true;
    }

    function mint(address to, uint256 amount) internal {
        _mint(to, amount);
    }

    function clm_and_dex_calls() internal {

        Comptroller troll = Comptroller(unitroller);

        CToken[] memory inps = new CToken[](3);
        inps[0] = CErc20(0x83A7Aa3a9f5E777Fd4BF02d26Adc8Ea5DDC1C20D);
        inps[1] = CErc20(0xAB8674A498d4C1Ef4a75B4e88df0BC2BC5e4F6A0);
        inps[2] = CErc20(0x2Cc8C9B72bF126553F6226688be8C40ce408FaC8);

        troll.enterMarkets(inps);

        // Minting vcTokens = Supplying to Vivacity
        for (uint256 i = 0; i < assets.length; i++) {
            ERC20 underlying = ERC20(assets[i]);
            uint256 token_balance = underlying.balanceOf(address(this));
            if (token_balance > 0) {
                CErc20 cToken = CErc20(cTokenMapping[assets[i]]);
                underlying.approve(address(cToken), token_balance);
                assert(cToken.mint(token_balance) == 0);
            }
        }

        (uint256 error, uint256 liquidity, uint256 shortfall) = troll.getAccountLiquidity(address(this));

        console.log("Error: ", error);
        console.log("Liquidity: ", liquidity);
        console.log("Shortfall: ", shortfall);

        require(error == 0, "something went wrong");
        require(shortfall == 0, "negative liquidity balance");
        require(liquidity > 0, "there's not enough collateral");

        // Borrowing NOTE from the vcNOTE
        CErc20 cERCvcNOTE = CErc20(vcNOTE);
        uint256 amt_borrow = liquidity - 1;
        require(cERCvcNOTE.borrow(amt_borrow) == 0, "there is not enough collateral");

        // Creating new pair on DEX - Testnet address is being used for Router as well as for NOTE
        BaseV1Router01 mainnet_dex = BaseV1Router01(0xa252eEE9BDe830Ca4793F054B506587027825a8e);
        (uint256 amountA, uint256 amountB,) = mainnet_dex.addLiquidity(
            address(this),
            0x4e71A2E537B7f9D9413D3991D37958c0b5e1e503,
            false,
            reservedSupply,
            amt_borrow,
            reservedSupply,
            amt_borrow,
            address(0),
            16725205800
        );

        console.log("Amount A: ", amountA);
        console.log("Amount B: ", amountB);

        require(amountA == reservedSupply && amountB == amt_borrow, "couldn't add liquidity as required");
    }
}

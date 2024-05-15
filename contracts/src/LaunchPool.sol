// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CErc20} from "../lib/clm/src/CErc20.sol";
import {CToken} from "../lib/clm/src/CToken.sol";
import {console} from "forge-std/Test.sol";

interface Comptroller {
    function enterMarkets(CToken[] calldata cTokens) external returns (uint256[] memory);
    function getAccountLiquidity(address account) external view returns (uint256, uint256, uint256);
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

// This implementation is developed for Testnet only.
contract LaunchPool is ERC20 {
    uint256 public maxSupply;
    uint256 public allocatedSupply;
    uint256 public reservedSupply;
    uint256 public creatorSupply;
    uint256 public saleStartTime;
    uint256 public saleDuration;
    address public creator;
    address[] public whitelist;

    // this is for testnet only - [ETH, ATOM]
    address[2] public assets = [0xCa03230E7FB13456326a234443aAd111AC96410A, 0x40E41DC5845619E7Ba73957449b31DFbfB9678b2];
    mapping(address => address) public cTokenMapping;
    uint256[] public amounts;

    // ratios denote how many tokens will a buyer get in exchange of existing token
    // for eg. ratios[0] = 10*10**18 meaning each user will get 10 tokens for each NOTE
    uint256[2] public ratios;

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
        uint256[2] memory _ratios
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
        cTokenMapping[0xCa03230E7FB13456326a234443aAd111AC96410A] = 0x4c93f060aCe7EBdc1687F0c04f7b4601F4470E0f;
        cTokenMapping[0x40E41DC5845619E7Ba73957449b31DFbfB9678b2] = 0x8e818074EFeeA7fea2395331050376d311f96De1;
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
        // Minting cTokens = Supplying to CLM
        for (uint256 i = 0; i < assets.length; i++) {
            ERC20 underlying = ERC20(assets[i]);
            uint256 token_balance = underlying.balanceOf(address(this));
            if (token_balance > 0) {
                CErc20 cToken = CErc20(cTokenMapping[assets[i]]);
                underlying.approve(address(cToken), token_balance);
                assert(cToken.mint(token_balance) == 0);
            }
        }
        // Checking Liquidity - Testnet address is being used
        Comptroller troll = Comptroller(0xFf64a8Ab86b0B56c2487DB9EBF630B8863a66620);

        CToken[] memory inps = new CToken[](2);
        inps[0] = CErc20(0x260fCD909ab9dfF97B03591F83BEd5bBfc89A571);
        inps[1] = CErc20(0x8e818074EFeeA7fea2395331050376d311f96De1);

        uint256[] memory returned = troll.enterMarkets(inps);

        // CToken[] memory cTokens = troll.getAllMarkets();

        (uint256 error, uint256 liquidity, uint256 shortfall) = troll.getAccountLiquidity(address(this));

        console.log("Returned-1: ", returned[0]);
        console.log("Returned-1: ", returned[1]);
        console.log("Error: ", error);
        console.log("Liquidity: ", liquidity);
        console.log("Shortfall: ", shortfall);

        require(error == 0, "something went wrong");
        require(shortfall == 0, "negative liquidity balance");
        require(liquidity > 0, "there's not enough collateral");
        // Borrowing NOTE - Testnet cNOTE address is being used
        CErc20 cNOTE = CErc20(0x45D36aD3a67a29F36F06DbAB1418F2e8Fa916Eea);
        uint256 amt_borrow = liquidity - 1;
        require(cNOTE.borrow(amt_borrow) == 0, "there is not enough collateral");
        // Creating new pair on DEX - Testnet address is being used for Router as well as for NOTE
        BaseV1Router01 testnet_dex = BaseV1Router01(0x463e7d4DF8fE5fb42D024cb57c77b76e6e74417a);
        (uint256 amountA, uint256 amountB,) = testnet_dex.addLiquidity(
            address(this),
            0x03F734Bd9847575fDbE9bEaDDf9C166F880B5E5f,
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

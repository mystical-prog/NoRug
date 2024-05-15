// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CErc20} from "../../lib/clm/src/CErc20.sol";
import {CToken} from "../../lib/clm/src/CToken.sol";

interface Comptroller {
    function enterMarkets(CToken[] calldata cTokens) external returns (uint256[] memory);
    function getAccountLiquidity(address account) external view returns (uint256, uint256, uint256);
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

// This implementation is created based on Mainnet utilising CLM
contract CLMMLaunchPool is ERC20 {
    uint256 public maxSupply;
    uint256 public allocatedSupply;
    uint256 public reservedSupply;
    uint256 public creatorSupply;
    uint256 public saleStartTime;
    uint256 public saleDuration;
    address public creator;
    address[] public whitelist;

    address public constant UNITROLLER = 0x5E23dC409Fc2F832f83CEc191E245A191a4bCc5C;
    address public constant CNOTE = 0xEe602429Ef7eCe0a13e4FfE8dBC16e101049504C;
    address public constant DEXROUTER = 0xa252eEE9BDe830Ca4793F054B506587027825a8e;
    address public constant NOTE = 0x4e71A2E537B7f9D9413D3991D37958c0b5e1e503;

    // [USYC, fBILL, ifBILL]
    address[3] public assets = [
        0xFb8255f0De21AcEBf490F1DF6F0BDd48CC1df03B,
        0x79ECCE8E2D17603877Ff15BC29804CbCB590EC08,
        0x45bafad5a6a531Bc18Cf6CE5B02C58eA4D20589b
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
    mapping(address => bool) public exists;
    mapping(address => uint256) public buyerAmounts;

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
        // asset -> cAsset
        cTokenMapping[0xFb8255f0De21AcEBf490F1DF6F0BDd48CC1df03B] = 0x0355E393cF0cf5486D9CAefB64407b7B1033C2f1;
        cTokenMapping[0x79ECCE8E2D17603877Ff15BC29804CbCB590EC08] = 0xF1F89dF149bc5f2b6B29783915D1F9FE2d24459c;
        cTokenMapping[0x45bafad5a6a531Bc18Cf6CE5B02C58eA4D20589b] = 0x897709FC83ba7a4271d22Ed4C01278cc1Da8d6F8;
        // setting all bools to false
        airdropped = false;
        whitelistdropped = false;
        creatordropped = false;
    }

    function buy(uint8 asset_index, uint256 amount) external {
        require(amount > 0, "Invalid amount!");
        uint256 ratio = ratios[asset_index];
        uint256 requiredAmount = amount * ratio;
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
        Comptroller troll = Comptroller(UNITROLLER);

        CToken[] memory inps = new CToken[](3);
        inps[0] = CErc20(0x0355E393cF0cf5486D9CAefB64407b7B1033C2f1);
        inps[1] = CErc20(0xF1F89dF149bc5f2b6B29783915D1F9FE2d24459c);
        inps[2] = CErc20(0x897709FC83ba7a4271d22Ed4C01278cc1Da8d6F8);

        troll.enterMarkets(inps);

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

        (uint256 error, uint256 amt_borrow, uint256 shortfall) = troll.getAccountLiquidity(address(this));

        require(error == 0, "something went wrong");
        require(shortfall == 0, "negative liquidity balance");
        require(amt_borrow > 0, "there's not enough collateral");

        // Borrowing NOTE from the cNOTE
        CErc20 cERCcNOTE = CErc20(CNOTE);
        require(cERCcNOTE.borrow(amt_borrow) == 0, "there is not enough collateral");

        // Approving tokens to DEX
        ERC20(address(this)).approve(DEXROUTER, reservedSupply);
        mint(address(this), reservedSupply);
        ERC20(NOTE).approve(DEXROUTER, amt_borrow);

        // Creating new pair on DEX - Testnet address is being used for Router as well as for NOTE
        BaseV1Router01 mainnet_dex = BaseV1Router01(DEXROUTER);
        (uint256 amountA, uint256 amountB,) = mainnet_dex.addLiquidity(
            address(this), NOTE, false, reservedSupply, amt_borrow, reservedSupply, amt_borrow, address(0), 16725205800
        );

        require(amountA == reservedSupply && amountB == amt_borrow, "couldn't add liquidity as required");
    }
}

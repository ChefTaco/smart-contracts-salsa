/*

                   oooo                     
                   `888                     
 .oooo.o  .oooo.    888   .oooo.o  .oooo.   
d88(  "8 `P  )88b   888  d88(  "8 `P  )88b  
`"Y88b.   .oP"888   888  `"Y88b.   .oP"888  PRESALE TOKEN
o.  )88b d8(  888   888  o.  )88b d8(  888  
8""888P' `Y888""8o o888o 8""888P' `Y888""8o

Website     https://salsa.tacoparty.finance

*/
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/* PreSalsaToken Presale
 After Presale you'll be able to swap this token for Salsa. Ratio 1:0.993
*/
contract PreSalsaToken is ERC20('PreSalsaToken', 'PRESALSA'), ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    address  constant presaleAddress = 0xCf7Db495dFb74302870fFE4aC8D8d19550d97fA8;
    
    IERC20 public USDC = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    
    IERC20 preSalsaToken = IERC20(address(this));

    uint256 public salePrice = 400;  // sale price in cents

    uint256 public constant presalsaMaximumSupply = 30000 * (10 ** 18); //30k

    uint256 public constant presalsaAdditionalMint = 5000 * (10 ** 18); //5k for mktg

    uint256 public presalsaRemaining = presalsaMaximumSupply;
    
    uint256 public maxHardCap = 150000 * (10 ** 6); // 150k usdc

    uint256 public constant maxPreSalsaPurchase = 500 * (10 ** 18); // 500 presalsa

    uint256 public startBlock;
    
    uint256 public endBlock;

    uint256 public constant presaleDuration = 179800; // 5 days aprox

    mapping(address => uint256) public userPreSalsaTotally;

    event StartBlockChanged(uint256 newStartBlock, uint256 newEndBlock);
    event presalsaPurchased(address sender, uint256 usdcSpent, uint256 presalsaReceived);

    constructor(uint256 _startBlock) {
        startBlock  = _startBlock;
        endBlock    = _startBlock + presaleDuration;
        _mint(address(this), presalsaMaximumSupply);
        _mint(address(presaleAddress), presalsaAdditionalMint);
    }

    function buyPreSalsa(uint256 _usdcSpent) external nonReentrant {
        require(block.number >= startBlock, "presale hasn't started yet, good things come to those that wait");
        require(block.number < endBlock, "presale has ended, come back next time!");
        require(presalsaRemaining > 0, "No more PreSalsa remains!");
        require(preSalsaToken.balanceOf(address(this)) > 0, "No more PreSalsa left!");
        require(_usdcSpent > 0, "not enough usdc provided");
        require(_usdcSpent <= maxHardCap, "PreSalsa Presale hardcap reached");
        require(userPreSalsaTotally[msg.sender] < maxPreSalsaPurchase, "user has already purchased too much presalsa");

        uint256 presalsaPurchaseAmount = (_usdcSpent * 100000000000000) / salePrice;

        // if we dont have enough left, error on the rest.
        require(presalsaRemaining >= presalsaPurchaseAmount, 'Not enough remaining.');

        require(presalsaPurchaseAmount > 0, "user cannot purchase 0 presalsa");

        // shouldn't be possible to fail these asserts.
        assert(presalsaPurchaseAmount <= presalsaRemaining);
        assert(presalsaPurchaseAmount <= preSalsaToken.balanceOf(address(this)));
        
        //send presalsa to user
        preSalsaToken.safeTransfer(msg.sender, presalsaPurchaseAmount);
        // send usdc to presale address
    	USDC.safeTransferFrom(msg.sender, address(presaleAddress), _usdcSpent);

        presalsaRemaining = presalsaRemaining - presalsaPurchaseAmount;
        userPreSalsaTotally[msg.sender] = userPreSalsaTotally[msg.sender] + presalsaPurchaseAmount;

        emit presalsaPurchased(msg.sender, _usdcSpent, presalsaPurchaseAmount);

    }

    function setStartBlock(uint256 _newStartBlock) external onlyOwner {
        require(block.number < startBlock, "cannot change start block if sale has already started");
        require(block.number < _newStartBlock, "cannot set start block in the past");
        startBlock = _newStartBlock;
        endBlock   = _newStartBlock + presaleDuration;

        emit StartBlockChanged(_newStartBlock, endBlock);
    }

}
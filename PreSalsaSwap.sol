/*

                   oooo                     
                   `888                     
 .oooo.o  .oooo.    888   .oooo.o  .oooo.   
d88(  "8 `P  )88b   888  d88(  "8 `P  )88b  
`"Y88b.   .oP"888   888  `"Y88b.   .oP"888  PRESALE TOKEN SWAPPER
o.  )88b d8(  888   888  o.  )88b d8(  888  
8""888P' `Y888""8o o888o 8""888P' `Y888""8o

Website     https://salsa.tacoparty.finance

Swap contract for the presale PreSalsa!

*/

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;


import "./PreSalsa.sol";

contract PreSalsaSwap is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Burn address
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    PreSalsaToken immutable public preSalsaToken;

    IERC20 immutable public salsaToken;

    address  salsaAddress;

    bool  hasBurnedUnsoldPresale;

    bool  redeemState;

    uint256 public startBlock;

    event PreSalsaToSalsa(address sender, uint256 amount);
    event burnUnclaimedSalsa(uint256 amount);
    event startBlockChanged(uint256 newStartBlock);

    constructor(uint256 _startBlock, address _presalsaAddress, address _salsaAddress) {
        require(_presalsaAddress != _salsaAddress, "presalsa cannot be equal to salsa");
        startBlock = _startBlock;
        preSalsaToken = PreSalsaToken(_presalsaAddress);
        salsaToken = IERC20(_salsaAddress);
    }

    function swapPreSalsaForSalsa() external nonReentrant {
        require(block.number >= startBlock, "presalsa still awake.");

        uint256 swapAmount = preSalsaToken.balanceOf(msg.sender);
        require(salsaToken.balanceOf(address(this)) >= swapAmount, "Not Enough tokens in contract for swap");
        require(preSalsaToken.transferFrom(msg.sender, BURN_ADDRESS, swapAmount), "failed sending presalsa" );
        salsaToken.safeTransfer(msg.sender, swapAmount);

        emit PreSalsaToSalsa(msg.sender, swapAmount);
    }

    function sendUnclaimedSalsaToDeadAddress() external onlyOwner {
        require(block.number > preSalsaToken.endBlock(), "can only send excess presalsa to dead address after presale has ended");
        require(!hasBurnedUnsoldPresale, "can only burn unsold presale once!");

        require(preSalsaToken.presalsaRemaining() <= salsaToken.balanceOf(address(this)),
            "burning too much salsa, check again please");

        if (preSalsaToken.presalsaRemaining() > 0)
            salsaToken.safeTransfer(BURN_ADDRESS, preSalsaToken.presalsaRemaining());
        hasBurnedUnsoldPresale = true;

        emit burnUnclaimedSalsa(preSalsaToken.presalsaRemaining());
    }

    function setStartBlock(uint256 _newStartBlock) external onlyOwner {
        require(block.number < startBlock, "cannot change start block if presale has already commenced");
        require(block.number < _newStartBlock, "cannot set start block in the past");
        startBlock = _newStartBlock;

        emit startBlockChanged(_newStartBlock);
    }

}
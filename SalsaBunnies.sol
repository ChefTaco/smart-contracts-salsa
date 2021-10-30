// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

pragma solidity ^0.8.4;

/**
 * https://github.com/maticnetwork/pos-portal/blob/master/contracts/common/ContextMixin.sol
 */
abstract contract ContextMixin {
    function msgSender()
        internal
        view
        returns (address payable sender)
    {
        if (msg.sender == address(this)) {
            bytes memory array = msg.data;
            uint256 index = msg.data.length;
            assembly {
                // Load the 32 bytes word from memory with the address on the lower 20 bytes, and mask those.
                sender := and(
                    mload(add(array, index)),
                    0xffffffffffffffffffffffffffffffffffffffff
                )
            }
        } else {
            sender = payable(msg.sender);
        }
        return sender;
    }
}

contract SalsaBunnies is ERC721URIStorage, ContextMixin, Ownable {
    using Counters for Counters.Counter;

    // Map the number of tokens per bunnyId
    mapping(uint8 => uint256) public bunnyCount;

    // Map the number of tokens burnt per bunnyId
    mapping(uint8 => uint256) public bunnyBurnCount;

    // Used for generating the tokenId of new NFT minted
    Counters.Counter private _tokenIds;

    // Map the bunnyId for each tokenId
    mapping(uint256 => uint8) private bunnyIds;

    // Map the bunnyName for a tokenId
    mapping(uint8 => string) private bunnyNames;

    constructor() ERC721("Taco Party Salsa Edition", "SPNFT") {
    }

    /**
     * @dev Get bunnyId for a specific tokenId.
     */
    function getBunnyId(uint256 _tokenId) external view returns (uint8) {
        return bunnyIds[_tokenId];
    }

    /**
     * @dev Get the associated bunnyName for a specific bunnyId.
     */
    function getBunnyName(uint8 _bunnyId)
        external
        view
        returns (string memory)
    {
        return bunnyNames[_bunnyId];
    }

    /**
     * @dev Get the associated bunnyName for a unique tokenId.
     */
    function getBunnyNameOfTokenId(uint256 _tokenId)
        external
        view
        returns (string memory)
    {
        uint8 bunnyId = bunnyIds[_tokenId];
        return bunnyNames[bunnyId];
    }

    /**
     * @dev Mint NFTs. Only the owner can call it.
     */
    function mint(
        address _to,
        string calldata _tokenURI,
        uint8 _bunnyId
    ) external onlyOwner returns (uint256) {
        uint256 newId = _tokenIds.current();
        _tokenIds.increment();
        bunnyIds[newId] = _bunnyId;
        bunnyCount[_bunnyId] += 1;
        _mint(_to, newId);
        _setTokenURI(newId, _tokenURI);
        return newId;
    }

    /**
     * @dev Set a unique name for each bunnyId. It is supposed to be called once.
     */
    function setBunnyName(uint8 _bunnyId, string calldata _name)
        external
        onlyOwner
    {
        bunnyNames[_bunnyId] = _name;
    }

    /**
     * @dev Burn a NFT token. Callable by owner only.
     */
    function burn(uint256 _tokenId) external onlyOwner {
        uint8 bunnyIdBurnt = bunnyIds[_tokenId];
        bunnyCount[bunnyIdBurnt] += 1;
        bunnyBurnCount[bunnyIdBurnt] += 1;
        _burn(_tokenId);
    }

    /** 
    * @dev Return the contract storefront URI for the token
     */
    function contractURI() public pure returns (string memory) {
        return "https://tacoparty.finance/nft/salsa/storefront.json";
    }

    /**
    * @dev Return the base directory of the NFT
     */
    function baseTokenURI() public pure returns (string memory) {
    return "https://tacoparty.finance/nft/salsa/";
    }

    /**
   * Override isApprovedForAll to auto-approve OS's proxy contract
   * (Added for OpenSea compatibility)
   */
    function isApprovedForAll(
        address _owner,
        address _operator
    ) public override view returns (bool isOperator) {
      // if OpenSea's ERC721 Proxy Address is detected, auto-return true
        if (_operator == address(0x58807baD0B376efc12F5AD86aAc70E78ed67deaE)) {
            return true;
        }
        
        // otherwise, use the default ERC721.isApprovedForAll()
        return ERC721.isApprovedForAll(_owner, _operator);
    }

    /**
     * This is used instead of msg.sender as transactions won't be sent by the original token owner, but by OpenSea.
     * (Added for OpenSea support)
     */
    function _msgSender()
        internal
        override
        view
        returns (address sender)
    {
        return ContextMixin.msgSender();
    }
}
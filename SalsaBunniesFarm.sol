// SPDX-License-Identifier: MIT

// Happy NFT Farming!

pragma solidity ^0.8.4;

import "contracts/SalsaBunnies.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SalsaBunniesFarm is Ownable {

    using SafeERC20 for IERC20;

    SalsaBunnies public salsaBunnies;
    IERC20 public salsaToken;

    // Map if address can claim a NFT
    mapping(address => bool) public canClaim;

    // Map if address has already claimed a NFT
    mapping(address => bool) public hasClaimed;

    // starting block
    uint256 public startBlockNumber;

    // end block number to claim SALSAs by burning NFT
    uint256 public endBlockNumber;

    // number of total bunnies burnt
    uint256 public countBunniesBurnt;

    // Number of SALSAs a user can collect by burning her NFT
    uint256 public salsaPerBurn;

    // current distributed number of NFTs
    uint256 public currentDistributedSupply;

    // number of total NFTs distributed
    uint256 public totalSupplyDistributed;

    // Map the token number to URI
    mapping(uint8 => string) private bunnyIdURIs;

    // number of initial series (i.e. different visuals)
    uint8 private numberOfBunnyIds;

    // Event to notify when NFT is successfully minted
    event SalsaBunnyMint(
        address indexed to,
        uint256 indexed tokenId,
        uint8 indexed bunnyId
    );

    // Event to notify when NFT is successfully minted
    event SalsaBunnyBurn(address indexed from, uint256 indexed tokenId);

    /**
     * @dev A maximum number of NFT tokens that is distributed by this contract
     * is defined as totalSupplyDistributed.
     */
    constructor(
        IERC20 _salsaToken,
        uint256 _totalSupplyDistributed,
        uint256 _salsaPerBurn,
        uint256 _endBlockNumber
    ) {
        salsaBunnies = new SalsaBunnies();
        salsaToken = _salsaToken;
        totalSupplyDistributed = _totalSupplyDistributed;
        salsaPerBurn = _salsaPerBurn;
        endBlockNumber = _endBlockNumber;

        // Other parameters initialized
        numberOfBunnyIds = 3;

        // Assign tokenURI to look for each bunnyId in the mint function
        bunnyIdURIs[0] = string(abi.encodePacked("https://tacoparty.finance/nft/salsa/rhythmofpassion.json"));
        bunnyIdURIs[1] = string(abi.encodePacked("https://tacoparty.finance/nft/salsa/buysalsa.json"));
        bunnyIdURIs[2] = string(abi.encodePacked("https://tacoparty.finance/nft/salsa/salsagoodness.json"));

        // Set token names for each bunnyId
        salsaBunnies.setBunnyName(0, "Rhythm of Passion");
        salsaBunnies.setBunnyName(1, "Buy Salsa");
        salsaBunnies.setBunnyName(2, "Salsa Goodness");
    }

    /**
     * @dev Mint NFTs from the SalsaBunnies contract.
     * Users can specify what bunnyId they want to mint. Users can claim once.
     * There is a limit on how many are distributed. It requires SALSA balance to be >0.
     */
    function mintNFT(uint8 _bunnyId) external {
        // Check msg.sender can claim
        require(canClaim[msg.sender], "Cannot claim");
        // Check msg.sender has not claimed
        require(hasClaimed[msg.sender] == false, "Has claimed");
        // Check whether it is still possible to mint
        require(
            currentDistributedSupply < totalSupplyDistributed,
            "Nothing left"
        );
        // Check whether user owns any SALSA
        require(salsaToken.balanceOf(msg.sender) > 0, "Must own SALSA");
        // Check that the _bunnyId is within boundary:
        require(_bunnyId < numberOfBunnyIds, "bunnyId unavailable");
        // Update that msg.sender has claimed
        hasClaimed[msg.sender] = true;

        // Update the currentDistributedSupply by 1
        currentDistributedSupply += 1;

        string memory tokenURI = bunnyIdURIs[_bunnyId];

        uint256 tokenId = salsaBunnies.mint(
            address(msg.sender),
            tokenURI,
            _bunnyId
        );

        emit SalsaBunnyMint(msg.sender, tokenId, _bunnyId);
    }

    /**
     * @dev Burn NFT from the SalsaBunnies contract.
     * Users can burn their NFT to get a set number of SALSA.
     * There is a cap on how many can be distributed for free.
     */
    function burnNFT(uint256 _tokenId) external {
        require(
            salsaBunnies.ownerOf(_tokenId) == msg.sender,
            "Not the owner"
        );
        require(block.number < endBlockNumber, "too late");

        salsaBunnies.burn(_tokenId);
        countBunniesBurnt += 1;
        salsaToken.safeTransfer(address(msg.sender), salsaPerBurn);
        emit SalsaBunnyBurn(msg.sender, _tokenId);
    }

    /**
     * @dev Allow to set up the start number
     * Only the owner can set it.
     */
    function setStartBlockNumber() external onlyOwner {
        startBlockNumber = block.number;
    }

    /**
     * @dev Allow the contract owner to whitelist addresses.
     * Only these addresses can claim.
     */
    function whitelistAddresses(address[] calldata users) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            canClaim[users[i]] = true;
        }
    }

    /**
     * @dev It transfers the SALSA tokens back to the chef address.
     * Only callable by the owner.
     */
    function withdrawSalsa(uint256 _amount) external onlyOwner {
        require(block.number >= endBlockNumber, "too early");
        salsaToken.safeTransfer(address(msg.sender), _amount);
    }

    /**
     * @dev It transfers the ownership of the NFT contract
     * to a new address.
     */
    function changeOwnershipNFTContract(address _newOwner) external onlyOwner {
        salsaBunnies.transferOwnership(_newOwner);
    }
}
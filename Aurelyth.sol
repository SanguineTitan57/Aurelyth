// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24 ;

import 'erc721a/contracts/ERC721A.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/Pausable.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/common/ERC2981.sol';
import '@openzeppelin/contracts/utils/Strings.sol';
import '@openzeppelin/contracts/utils/Address.sol';


contract Aurelyth is ERC721A, Ownable, Pausable, ReentrancyGuard, ERC2981 {

    string private _baseTokenURI;
    uint256 public auctionStartTime;
    uint256 public ownerMintStartTime;
    uint256 public immutable maxOwnerBatchSize;
    uint256 public immutable collectionSize;
    uint256 public immutable maxMintPerAddress;


    //Auction parameters
    uint256 public constant AUCTION_START_PRICE = 1.20 ether;
    uint256 public constant AUCTION_END_PRICE = 0.15 ether;
    uint256 public constant AUCTION_PRICE_CURVE_LENGTH = 400 minutes;
    uint256 public constant AUCTION_DROP_INTERVAL = 20 minutes;
    uint256 public constant AUCTION_DROP_PER_STEP =
        (AUCTION_START_PRICE - AUCTION_END_PRICE) / 
            (AUCTION_PRICE_CURVE_LENGTH / AUCTION_DROP_INTERVAL);


    //So when deploying to the contract, hardcode the values needed in the order seen in the constructor argumets
    constructor(
        address initialOwner, 
        uint256 collectionSize_, 
        uint256 maxOwnerMint_, 
        uint256 maxBatchPerAddress_, 
        address royaltyReceiver, 
        uint96 royaltyFeeEnumerator // Set the basis points (Percentage), 1% = 100 points
        ) 
    ERC721A("Aurelyth", "AURL") 
    Ownable(initialOwner) {
        collectionSize = collectionSize_;
        maxOwnerBatchSize = maxOwnerMint_;
        maxMintPerAddress = maxBatchPerAddress_;
        
        _setDefaultRoyalty(royaltyReceiver, royaltyFeeEnumerator);
        }

    //Pause minting
    function pause() external onlyOwner {
        _pause();
    }

    //Unpause minting
    function unpause() external onlyOwner {
        _unpause();
    }

    //OwnerMint
    function OwnerMint(uint256 quantity) public payable onlyOwner {
        require(ownerMintStartTime != 0 && auctionStartTime > ownerMintStartTime &&  block.timestamp >= ownerMintStartTime, "Owner Mint has not yet begun");

        require(_numberMinted(msg.sender) <= maxOwnerBatchSize, "Owner cannot mint this many");

        require(totalSupply() + quantity <= collectionSize, "Tokens sold out");

        _mint(msg.sender, quantity);
    }

    //Auction price calculation based on time
    function getAuctionPrice() public view returns (uint256) {
        if (block.timestamp < auctionStartTime) {
            return AUCTION_START_PRICE;
        }

        //Calculate the number of intervals passed since the start of the auction
        uint256 timeSinceStart = block.timestamp - auctionStartTime;
        if (timeSinceStart >= AUCTION_PRICE_CURVE_LENGTH) {
            return AUCTION_END_PRICE;
        }

        //Calculate the price drop according to intervals passed
        uint256 dropSteps = timeSinceStart / AUCTION_DROP_INTERVAL;
        uint256 auctionPrice = AUCTION_START_PRICE - (dropSteps * AUCTION_DROP_PER_STEP);
        return auctionPrice;
    }

    //AuctionMint
    function AuctionMint(uint256 quantity) public payable whenNotPaused {
        require(ownerMintStartTime < auctionStartTime && auctionStartTime != 0 && block.timestamp >= auctionStartTime, "Mint has not yet started");

        require(_numberMinted(msg.sender) + quantity <= maxMintPerAddress, "You can't mint more than this");

        require(totalSupply() + quantity <= collectionSize, "Tokens sold out");

        //Get the current price and total cost
        uint256 currentPrice = getAuctionPrice();
        uint256 totalCost = currentPrice * quantity;

        require(msg.value >= totalCost, "Insufficient Ether sent");

        _mint(msg.sender, quantity);

        //Refund excess ETH
        if (msg.value > totalCost) {
            uint256 excessAmount = msg.value - totalCost;
            Address.sendValue(payable(msg.sender), excessAmount);
        }
    }

    //withdraw Funds
    function withdrawFunds() external onlyOwner nonReentrant { 
        uint256 balance = address(this).balance;
        Address.sendValue(payable(msg.sender), balance);
        //For the multi sig wallet
        // (bool os,) = payable(msg.sender).call{value:balance}(""); 
    }

    //metadata URL
    function setBaseURI(string calldata baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function numberMinted(address owner) public view returns (uint256) {
        return _numberMinted(owner);
    }

    //Set auction start time
    function startAuction(uint256 startTime) external onlyOwner {
        auctionStartTime = startTime;
    }

    //Set owner mint start time
    function startOwnerMint(uint256 ownerStartTime) external onlyOwner {
        ownerMintStartTime = ownerStartTime;
    }

    //Overrides to support royalties
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721A, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTMarketplace is ReentrancyGuard, Ownable {
    struct Listing {
        uint256 listingId;
        address seller;
        address payable nftContract;
        uint256 tokenId;
        uint256 price;
        bool active;
    }

    uint256 public listingCount;
    mapping(uint256 => Listing) public listings;
    uint256[] private listingIds; // Track all listing IDs
    mapping(address => bool) public approvedNFTContracts;
    mapping(address => mapping(uint256 => bool)) public isTokenListed; // tracks whether a token from a specific nft contract is already listed

    event Listed(
        uint256 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 price
    );
    event Sale(
        uint256 indexed listingId,
        address indexed seller,
        address indexed buyer,
        uint256 price
    );
    event ListingUpdated(uint256 indexed listingId, uint256 newPrice);
    event ListingCanceled(uint256 indexed listingId);
    event NFTContractApproved(address indexed nftContract);
    event NFTContractRevoked(address indexed nftContract);

    constructor() Ownable(msg.sender) {}

    function approveNFTContract(address _nftContract) public onlyOwner {
        approvedNFTContracts[_nftContract] = true;
        emit NFTContractApproved(_nftContract);
    }

    function revokeNFTContract(address _nftContract) public onlyOwner {
        approvedNFTContracts[_nftContract] = false;
        emit NFTContractRevoked(_nftContract);
    }

    function listNFT(
        address payable _nftContract,
        uint256 _tokenId,
        uint256 _price
    ) public {
        require(
            approvedNFTContracts[_nftContract],
            "NFT contract not approved"
        );
        IERC721 nft = IERC721(_nftContract);
        require(
            nft.ownerOf(_tokenId) == msg.sender,
            "Caller is not NFT owner."
        );
        require(
            nft.getApproved(_tokenId) == address(this) ||
                nft.isApprovedForAll(msg.sender, address(this)),
            "Marketplace not approved."
        );
        require(
            !isTokenListed[_nftContract][_tokenId],
            "Token is already listed."
        );

        isTokenListed[_nftContract][_tokenId] = true;

        listings[listingCount] = Listing(
            listingCount,
            msg.sender,
            _nftContract,
            _tokenId,
            _price,
            true
        );
        listingIds.push(listingCount);
        emit Listed(listingCount, msg.sender, _nftContract, _tokenId, _price);
        listingCount++;
    }

    function isNFTListed(
        address nftContract,
        uint256 tokenId
    ) public view returns (bool) {
        return isTokenListed[nftContract][tokenId];
    }

    function updateListingPrice(uint256 listingId, uint256 newPrice) public {
        Listing storage listing = listings[listingId];
        require(
            listing.seller == msg.sender,
            "Only the seller can update the listing."
        );
        require(listing.active, "Listing is not active.");

        listing.price = newPrice;
        emit ListingUpdated(listingId, newPrice);
    }

    function buyNFT(uint256 listingId) external payable nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing is not active.");
        require(msg.value >= listing.price, "Insufficient payment.");

        uint256 feeAmount = (msg.value * 5) / 100;
        uint256 sellerAmount = msg.value - feeAmount;

        listing.active = false;
        IERC721(listing.nftContract).transferFrom(
            listing.seller,
            msg.sender,
            listing.tokenId
        );

        (bool sent, ) = listing.nftContract.call{value: feeAmount}("");
        require(sent, "Failed to send Ether to NFT contract.");

        payable(listing.seller).transfer(sellerAmount);
        isTokenListed[listing.nftContract][listing.tokenId] = false;
        emit Sale(listingId, listing.seller, msg.sender, listing.price);
    }

    function getListingsBySeller(
        address seller
    ) public view returns (Listing[] memory) {
        uint256 totalListings = 0;
        for (uint256 i = 0; i < listingIds.length; i++) {
            if (
                listings[listingIds[i]].seller == seller &&
                listings[listingIds[i]].active
            ) {
                totalListings++;
            }
        }

        Listing[] memory sellerListings = new Listing[](totalListings);
        uint256 sellerListingIndex = 0;
        for (uint256 i = 0; i < listingIds.length; i++) {
            if (
                listings[listingIds[i]].seller == seller &&
                listings[listingIds[i]].active
            ) {
                sellerListings[sellerListingIndex] = listings[listingIds[i]];
                sellerListingIndex++;
            }
        }

        return sellerListings;
    }

    function cancelListing(uint256 listingId) public {
        Listing storage listing = listings[listingId];
        require(
            listing.seller == msg.sender,
            "Only the seller can cancel the listing."
        );
        require(listing.active, "Listing is not active or already canceled.");

        listing.active = false;
        isTokenListed[listing.nftContract][listing.tokenId] = false;
        emit ListingCanceled(listingId);
    }

    // Function to return all active listings
    function getAllActiveListings()
        public
        view
        returns (
            uint256[] memory,
            address[] memory,
            address[] memory,
            uint256[] memory,
            uint256[] memory,
            bool[] memory
        )
    {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < listingIds.length; i++) {
            if (listings[listingIds[i]].active) {
                activeCount++;
            }
        }

        uint256[] memory ids = new uint256[](activeCount);
        address[] memory sellers = new address[](activeCount);
        address[] memory contracts = new address[](activeCount);
        uint256[] memory tokenIds = new uint256[](activeCount);
        uint256[] memory prices = new uint256[](activeCount);
        bool[] memory actives = new bool[](activeCount);

        uint256 index = 0;
        for (uint256 i = 0; i < listingIds.length; i++) {
            if (listings[listingIds[i]].active) {
                Listing storage listing = listings[listingIds[i]];
                ids[index] = listing.listingId;
                sellers[index] = listing.seller;
                contracts[index] = listing.nftContract;
                tokenIds[index] = listing.tokenId;
                prices[index] = listing.price;
                actives[index] = listing.active;
                index++;
            }
        }

        return (ids, sellers, contracts, tokenIds, prices, actives);
    }
    receive() external payable {}
}

// Discovered that solidity does not allow for returning of custom STRUCTURES and hence cannot be read on the frontend
// so the above getAllActiveListings() creates parallel arrays instead and a Listing object can be reconstructured by the index on the frontend

// function getAllActiveListings() public view returns (Listing[] memory) {
//     uint256 activeCount = 0;
//     // First, count active listings to allocate memory efficiently
//     for (uint256 i = 0; i < listingIds.length; i++) {
//         if (listings[listingIds[i]].active) {
//             activeCount++;
//         }
//     }

//     // Allocate array of active listings
//     Listing[] memory activeListings = new Listing[](activeCount);
//     uint256 currentIndex = 0;
//     for (uint256 i = 0; i < listingIds.length; i++) {
//         if (listings[listingIds[i]].active) {
//             activeListings[currentIndex] = listings[listingIds[i]];
//             currentIndex++;
//         }
//     }

//     return activeListings;
// }

// Ensure the contract can receive ETH by implementing a receive function.

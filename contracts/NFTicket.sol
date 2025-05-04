// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTicket is ERC721Enumerable, ERC721URIStorage, Ownable {
    uint256[4] public categorySupplies; // store the supplies of each category of tickets
    uint256[4] public categoryPrices; // store the prices for the different category of tickets (calculated in SUN not TRX)
    uint256 public saleStartTime; // store the start time for ticket sales
    uint256 public mintLimitPerAddress;

    uint256[4] private categoryStartIds; // Starting tokenId for each category
    uint256[4] private mintedPerCategory; // Tracks the number of tokens minted in each category

    string[4] public categoryURIs;

    bool public eventCanceled = false; // Indicates if the event has been canceled
    mapping(uint256 => bool) public ticketInsurance; // Tracks which tickets have insurance
    mapping(uint256 => uint256) private insuranceCostPaid; // Tracks the insurance cost paid for each ticket
    mapping(uint256 => uint256) private ticketPricePaid; // Tracks the price paid for each ticket for insurance purposes

    mapping(uint256 => bool) private _redeemedTickets; // store the redeemed tickets so that they cannot be redeemed again
    mapping(address => uint256) public mintCountPerAddress;

    event TicketRedeemed(uint256 indexed tokenId);
    event TicketMinted(
        uint256 indexed categoryId,
        uint256 indexed tokenId,
        address indexed minter
    );
    event EventStatusChanged(bool canceled);
    event InsurancePurchased(uint256 indexed tokenId, uint256 cost);
    event RefundIssued(uint256 indexed tokenId, uint256 amount);

    // in this constructor i am strictly limiting the number of catergories of tickets to ONLY 4
    constructor(
        string memory name,
        string memory symbol,
        uint256[4] memory _categorySupplies,
        uint256[4] memory _categoryPrices,
        string[4] memory _categoryURIs,
        uint256 _saleStartTime,
        uint256 _mintLimitPerAddress
    ) ERC721(name, symbol) Ownable(msg.sender) {
        require(
            _saleStartTime > block.timestamp,
            "Sale start time must be in the future."
        );
        categorySupplies = _categorySupplies;
        categoryPrices = _categoryPrices;
        categoryURIs = _categoryURIs;
        saleStartTime = _saleStartTime;
        mintLimitPerAddress = _mintLimitPerAddress;

        // Initialize categoryStartIds based on the supplied categorySupplies
        uint256 currentStartId = 1;
        for (uint256 i = 0; i < _categorySupplies.length; i++) {
            categoryStartIds[i] = currentStartId;
            currentStartId += _categorySupplies[i];
        }
    }

    receive() external payable {}

    fallback() external payable {}

    function mintTicket(
        uint256 categoryId,
        uint256 ticketCount
    ) public payable {
        require(
            categoryId >= 0 && categoryId < categorySupplies.length,
            "Invalid category"
        );
        require(ticketCount > 0, "Must mint at least one ticket");
        require(block.timestamp >= saleStartTime, "Sale has not started yet.");
        require(!eventCanceled, "Event is already canceled.");
        require(
            mintCountPerAddress[msg.sender] + ticketCount <=
                mintLimitPerAddress,
            "Minting limit exceeded for this address."
        );
        require(
            mintedPerCategory[categoryId] + ticketCount <=
                categorySupplies[categoryId],
            "Category supply exceeded."
        );
        require(
            msg.value == categoryPrices[categoryId] * ticketCount,
            "Incorrect price."
        );

        for (uint256 i = 0; i < ticketCount; i++) {
            uint256 tokenId = categoryStartIds[categoryId] +
                mintedPerCategory[categoryId];
            mintedPerCategory[categoryId]++;
            mintCountPerAddress[msg.sender]++;
            _mint(msg.sender, tokenId);

            string memory selectedURI = categoryURIs[categoryId];
            _setTokenURI(tokenId, selectedURI);

            ticketPricePaid[tokenId] = categoryPrices[categoryId];
            emit TicketMinted(categoryId, tokenId, msg.sender);
        }
    }

    function redeemTicket(uint256 tokenId) public {
        require(!eventCanceled, "Event is already canceled.");
        require(ownerOf(tokenId) == msg.sender, "Caller is not the owner.");
        require(!_redeemedTickets[tokenId], "Ticket already redeemed.");
        _redeemedTickets[tokenId] = true;
        emit TicketRedeemed(tokenId);
    }

    function isTicketRedeemed(uint256 tokenId) public view returns (bool) {
        uint256 upperBound = categoryStartIds[categoryStartIds.length - 1] +
            categorySupplies[categorySupplies.length - 1] -
            1;
        require(
            tokenId > 0 && tokenId <= upperBound,
            "Query for nonexistent token."
        );
        return _redeemedTickets[tokenId];
    }

    function cancelEvent() public onlyOwner {
        require(!eventCanceled, "Event is already canceled.");
        eventCanceled = true;
        emit EventStatusChanged(true);
    }

    function buyInsurance(uint256 tokenId) public payable {
        require(
            msg.sender == ownerOf(tokenId),
            "Caller is not the owner of the token."
        );
        require(!eventCanceled, "Event is already canceled.");
        require(
            !ticketInsurance[tokenId],
            "Insurance already purchased for this ticket."
        );

        uint256 categoryId = determineCategoryId(tokenId);
        uint256 ticketPrice = categoryPrices[categoryId];
        uint256 expectedInsuranceCost = (ticketPrice * 20) / 100; // Insurance cost is 20% of the ticket price

        require(
            msg.value == expectedInsuranceCost,
            "Incorrect value for insurance."
        );

        ticketInsurance[tokenId] = true;
        insuranceCostPaid[tokenId] = msg.value; // Store the insurance cost paid
        emit InsurancePurchased(tokenId, msg.value);
    }

    function claimRefund(uint256 tokenId) public {
        require(eventCanceled, "Event is not canceled.");
        require(
            ownerOf(tokenId) == msg.sender,
            "Caller is not the owner of the ticket."
        );
        require(ticketInsurance[tokenId], "Ticket is not insured.");

        uint256 totalRefundAmount = ticketPricePaid[tokenId] +
            insuranceCostPaid[tokenId];

        // Reset the insurance and price paid mappings for the tokenId
        ticketInsurance[tokenId] = false;
        insuranceCostPaid[tokenId] = 0;
        ticketPricePaid[tokenId] = 0;

        // Transfer the total refund amount to the owner
        payable(msg.sender).transfer(totalRefundAmount);
        emit RefundIssued(tokenId, totalRefundAmount);
    }

    // Function to retrieve insured token IDs owned by a specific address
    function getInsuredTokenIds(
        address _owner
    ) public view returns (uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(_owner); // Total tokens owned by the address
        uint256[] memory tempTokenIds = new uint256[](ownerTokenCount); // Temporary array to store all insured token IDs
        uint256 insuredCount = 0; // Counter for insured tokens

        for (uint256 i = 0; i < ownerTokenCount; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(_owner, i); // Get token ID at index i
            if (ticketInsurance[tokenId]) {
                // Check if the token ID has insurance
                tempTokenIds[insuredCount] = tokenId; // Store insured token ID
                insuredCount++; // Increment the count of insured tokens
            }
        }

        uint256[] memory insuredTokenIds = new uint256[](insuredCount); // Final array with the correct size for insured tokens
        for (uint256 j = 0; j < insuredCount; j++) {
            insuredTokenIds[j] = tempTokenIds[j]; // Copy insured token IDs to the final array
        }
        return insuredTokenIds; // Return the array of insured token IDs
    }

    function determineCategoryId(
        uint256 tokenId
    ) public view returns (uint256) {
        for (uint256 i = 0; i < categoryStartIds.length; i++) {
            uint256 startId = categoryStartIds[i];
            uint256 endId = i < categoryStartIds.length - 1
                ? categoryStartIds[i + 1] - 1
                : startId + categorySupplies[i] - 1;
            if (tokenId >= startId && tokenId <= endId) {
                return i;
            }
        }
        revert("tokenId does not belong to any category");
    }

    function getOwnedTokenIds(
        address _owner
    ) public view returns (uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);

        for (uint256 i = 0; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }

        return tokenIds;
    }

    function getAllMintedTokens() public view returns (uint256[] memory) {
        uint256 totalTokens = totalSupply(); // Get the total number of tokens minted
        uint256[] memory tokens = new uint256[](totalTokens);

        for (uint256 i = 0; i < totalTokens; i++) {
            tokens[i] = tokenByIndex(i);
        }

        return tokens;
    }

    function getAllUnmintedTokens() public view returns (uint256[] memory) {
        uint256 totalTokensPossible = 0;
        for (uint256 i = 0; i < categorySupplies.length; i++) {
            totalTokensPossible += categorySupplies[i];
        }

        uint256[] memory mintedTokens = getAllMintedTokens();
        bool[] memory isMinted = new bool[](totalTokensPossible + 1); // Assuming token IDs start at 1
        for (uint256 i = 0; i < mintedTokens.length; i++) {
            if (mintedTokens[i] <= totalTokensPossible) {
                // Sanity check
                isMinted[mintedTokens[i]] = true;
            }
        }

        uint256 unmintedCount = totalTokensPossible - mintedTokens.length;
        uint256[] memory unmintedTokens = new uint256[](unmintedCount);
        uint256 counter = 0;
        for (uint256 i = 1; i <= totalTokensPossible; i++) {
            if (!isMinted[i]) {
                unmintedTokens[counter++] = i;
                if (counter == unmintedCount) break; // Found all unminted, exit early
            }
        }

        return unmintedTokens;
    }

    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds available for withdrawal.");

        // Transfer the entire contract balance to the owner's address.
        (bool success, ) = owner().call{value: balance}("");
        require(success, "Withdrawal failed.");
    }

    // Override functions that exist in both ERC721Enumerable and ERC721URIStorage (multiple inheritance)

    function _increaseBalance(
        address account,
        uint128 value
    ) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC721Enumerable, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    // // Override tokenURI to return a different metadata if the event is canceled
    // function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
    //     if (eventCanceled) {
    //         return "ipfs://<canceled_event_metadata_uri>"; // Return an empty string or a URI indicating the event is canceled
    //     }
    //     return super.tokenURI(tokenId);
    // }
}

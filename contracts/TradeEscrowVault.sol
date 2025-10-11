// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IAccessControlModule {
    function isAdmin(address account) external view returns (bool);
}

contract TradeEscrowVault {
   
    event OfferCancelled(bytes32 indexed ref);
    event OfferMarkedPaid(bytes32 indexed ref);
    event OfferReleased(bytes32 indexed ref);
    event AppealCreated(bytes32 indexed ref, address indexed caller);
    event AppealResolved(bytes32 indexed ref, bool released);
    event Paused();
    event Unpaused();
    event Whitelisted(address indexed user, bool status);
    event Blacklisted(address indexed user, bool status);
    event OfferCreated(
        bytes32 indexed ref,
        address indexed creator,
        address indexed counterparty,
        uint256 tokenAmount,
        address token,
        bool isBuy,
        uint32 expiry,
        bytes3 fiatSymbol,
        uint64 fiatAmount,
        uint64 fiatToTokenRate
    );


    // ====== Config ======
    IAccessControlModule public immutable accessControl;
    bool public paused;
    uint256 private _locked;
    uint256 constant DECIMALS = 1e18;

    constructor(address _accessControl) {
        require(_accessControl != address(0), "Invalid access control");
        accessControl = IAccessControlModule(_accessControl);
        _locked = 1;
    }

    // ====== Reentrancy Guard ======
    modifier nonReentrant() {
        require(_locked == 1, "ReentrancyGuard: reentrant call");
        _locked = 2;
        _;
        _locked = 1;
    }

    // ====== Structs ======
    struct Offer {
        address creator;
        address counterparty;
        address token;
        bool isBuy;
        bool paid;
        bool released;
        uint32 expiry;       // fits in 4 bytes instead of 32
        uint64 fiatAmount;   // 8 bytes, adjust max as needed
        uint64 fiatToTokenRate; // 8 bytes, scaled by 1e18
        bytes3 fiatSymbol;   // store as 3 bytes like "USD", "NGN"
        bool appealed;
    }


    mapping(bytes32 => Offer) public offers;
    mapping(address => bool) public whitelist;
    mapping(address => bool) public blacklist;

    // ====== Modifiers ======
    modifier onlyAdmin() {
        require(accessControl.isAdmin(msg.sender), "Only admin");
        _;
    }

    modifier onlyWhitelisted(address user) {
        require(whitelist[user], "User not whitelisted");
        _;
    }

    modifier notBlacklisted(address user) {
        require(!blacklist[user], "User is blacklisted");
        _;
    }

    modifier offerExists(bytes32 ref) {
        require(offers[ref].creator != address(0), "Offer does not exist");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract paused");
        _;
    }

    // ====== Admin: Whitelist / Blacklist ======
    function setWhitelist(address user, bool status) external onlyAdmin {
        whitelist[user] = status;
        emit Whitelisted(user, status);
    }

    function setBlacklist(address user, bool status) external onlyAdmin {
        blacklist[user] = status;
        emit Blacklisted(user, status);
    }

    // ====== Admin: Pause / Unpause ======
    function pause() external onlyAdmin {
        paused = true;
        emit Paused();
    }

    function unpause() external onlyAdmin {
        paused = false;
        emit Unpaused();
    }

    // ====== Internal: Safe ERC20 transfer ======
    function _safeTransfer(IERC20 token, address to, uint256 amount) internal {
        require(token.transfer(to, amount), "ERC20 transfer failed");
    }

    function _safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        require(token.transferFrom(from, to, amount), "ERC20 transferFrom failed");
    }

    // ====== Offer Management ======
    function createOffer(
        bytes32 ref,
        address counterparty,
        address token,
        bool isBuy,
        uint32 expiry,
        string calldata fiatSymbol,
        uint64 fiatAmount,
        uint64 fiatToTokenRate
    ) external whenNotPaused notBlacklisted(msg.sender) notBlacklisted(counterparty) onlyWhitelisted(msg.sender) {
        require(ref != bytes32(0), "Invalid ref");
        require(offers[ref].creator == address(0), "Offer exists");
        require(counterparty != address(0), "Invalid counterparty");
        require(expiry > block.timestamp, "Expiry must be future");
        require(fiatToTokenRate > 0, "Invalid rate");
        require(bytes(fiatSymbol).length == 3, "Fiat symbol must be 3 chars");

        // Compute tokenAmount using fixed-point arithmetic (DECIMALS = 1e18)
        uint256 tokenAmount = (uint256(fiatAmount) * uint256(fiatToTokenRate)) / DECIMALS;

        // Convert fiatSymbol string (3 chars) to bytes3
        bytes3 symbol;
        assembly {
            // calldata layout: fiatSymbol is a dynamic calldata item; fiatSymbol.offset points to its location
            // load 32 bytes from the string location then truncate to bytes3
            symbol := calldataload(fiatSymbol.offset)
        }

        // Delegate storage writes, transfer and event emission to an internal function
        _saveOfferAndTransfer(
            ref,
            msg.sender,
            counterparty,
            token,
            isBuy,
            expiry,
            symbol,
            fiatAmount,
            fiatToTokenRate,
            tokenAmount
        );
    }

    function _saveOfferAndTransfer(
        bytes32 ref,
        address creator,
        address counterparty,
        address token,
        bool isBuy,
        uint32 expiry,
        bytes3 fiatSymbol,
        uint64 fiatAmount,
        uint64 fiatToTokenRate,
        uint256 tokenAmount
    ) internal {
        // Write into storage (single storage pointer usage)
        Offer storage o = offers[ref];
        o.creator = creator;
        o.counterparty = counterparty;
        o.token = token;
        o.isBuy = isBuy;
        o.expiry = expiry;
        o.fiatSymbol = fiatSymbol;
        o.fiatAmount = fiatAmount;
        o.fiatToTokenRate = fiatToTokenRate;
        o.appealed = false;
        o.paid = false;
        o.released = false;

        // Transfer tokens to escrow for seller offers (do this after storage write)
        if (!isBuy && tokenAmount > 0) {
            _safeTransferFrom(IERC20(token), creator, address(this), tokenAmount);
        }

        // Emit event
        emit OfferCreated(
            ref,
            creator,
            counterparty,
            tokenAmount,
            token,
            isBuy,
            expiry,
            fiatSymbol,
            fiatAmount,
            fiatToTokenRate
        );
    }

    function cancelOffer(bytes32 ref) external offerExists(ref) whenNotPaused nonReentrant notBlacklisted(msg.sender) onlyWhitelisted(msg.sender) {
        Offer storage o = offers[ref];
        require(msg.sender == o.creator, "Only creator");
        require(!o.released && !o.paid, "Cannot cancel");

        uint256 tokenAmount = (o.fiatAmount * o.fiatToTokenRate) / DECIMALS;

        if (!o.isBuy && tokenAmount > 0) {
            _safeTransfer(IERC20(o.token), o.creator, tokenAmount);
        }

        delete offers[ref];
        emit OfferCancelled(ref);
    }

    function markPaid(bytes32 ref) external offerExists(ref) whenNotPaused notBlacklisted(msg.sender) onlyWhitelisted(msg.sender) {
        Offer storage o = offers[ref];
        require(msg.sender == o.counterparty, "Only counterparty");
        require(!o.paid, "Already marked paid");
        o.paid = true;
        emit OfferMarkedPaid(ref);
    }

    function releaseOffer(bytes32 ref) external offerExists(ref) onlyAdmin whenNotPaused nonReentrant {
        Offer storage o = offers[ref];
        require(o.paid, "Not marked paid");
        require(!o.released, "Already released");
        require(whitelist[o.creator] && whitelist[o.counterparty], "Both must be whitelisted");
        require(!blacklist[o.creator] && !blacklist[o.counterparty], "Cannot release to blacklisted user");

        uint256 tokenAmount = (o.fiatAmount * o.fiatToTokenRate) / DECIMALS;
        if (!o.isBuy && tokenAmount > 0) {
            _safeTransfer(IERC20(o.token), o.counterparty, tokenAmount);
        }

        o.released = true;
        emit OfferReleased(ref);
    }

    // ====== Appeals ======
    function createAppeal(bytes32 ref) external offerExists(ref) whenNotPaused notBlacklisted(msg.sender) onlyWhitelisted(msg.sender) {
        Offer storage o = offers[ref];
        require(msg.sender == o.creator || msg.sender == o.counterparty, "Only parties");
        require(!o.appealed, "Already appealed");
        o.appealed = true;
        emit AppealCreated(ref, msg.sender);
    }

    function resolveAppeal(bytes32 ref, bool release) external onlyAdmin offerExists(ref) whenNotPaused nonReentrant {
        Offer storage o = offers[ref];
        require(o.appealed, "No appeal");
        o.appealed = false;

        if (release && !o.released) {
            require(whitelist[o.creator] && whitelist[o.counterparty], "Both must be whitelisted");
            require(!blacklist[o.creator] && !blacklist[o.counterparty], "Cannot release to blacklisted user");
            uint256 tokenAmount = (o.fiatAmount * o.fiatToTokenRate) / DECIMALS;
            if (!o.isBuy && tokenAmount > 0) {
                _safeTransfer(IERC20(o.token), o.counterparty, tokenAmount);
            }
            o.released = true;
        }

        emit AppealResolved(ref, release);
    }

    // Dedicated getter for offers
        function getOffer(bytes32 ref) external view returns (
            address creator,
            address counterparty,
            address token,
            bool isBuy,
            uint32 expiry,
            bytes3 fiatSymbol,
            uint64 fiatAmount,
            uint64 fiatToTokenRate,
            bool appealed,
            bool paid,
            bool released,
            uint256 tokenAmount
        ) {
            Offer storage o = offers[ref];
            uint256 tokenAmount1 = (o.fiatAmount * o.fiatToTokenRate) / DECIMALS;
            return (
                o.creator,
                o.counterparty,
                o.token,
                o.isBuy,
                o.expiry,
                o.fiatSymbol,
                o.fiatAmount,
                o.fiatToTokenRate,
                o.appealed,
                o.paid,
                o.released,
                tokenAmount1 );
        }
}
// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";

/**
 * @title CruratedConsumableToken
 * @author Your Name
 * @notice Implementation of a consumable ERC1155 token with role-based access and status tracking
 * @dev Extends ERC1155 with consumable functionality, status history and role-based access control
 * @custom:security-contact security@crurated.com
 */
contract CruratedConsumableToken is 
    ERC1155Upgradeable, 
    AccessControlUpgradeable, 
    UUPSUpgradeable 
{
    using CountersUpgradeable for CountersUpgradeable.Counter;

    /*//////////////////////////////////////////////////////////////
                                 ROLES
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant STATUS_UPDATER_ROLE = keccak256("STATUS_UPDATER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Struct for status updates
    struct StatusUpdate {
        string status;     // Status description
        uint40 timestamp;  // Timestamp of update
    }

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Counter for token IDs
    CountersUpgradeable.Counter private _tokenIds;

    /// @dev Mapping from token ID to consumable flag
    mapping(uint256 => bool) private _consumableTokens;

    /// @dev Mapping from token ID to token URI
    mapping(uint256 => string) private _tokenURIs;

    /// @dev Mapping from token ID and index to status updates
    mapping(uint256 => mapping(uint256 => StatusUpdate)) private _statusUpdates;

    /// @dev Mapping from token ID to number of status updates
    mapping(uint256 => uint256) private _updateCounts;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error TokenNotConsumable(uint256 tokenId);
    error TokenAlreadyConsumed(uint256 tokenId);
    error InvalidBatchInput();
    error ZeroMintAmount();
    error EmptyStatus();
    error TokenNotExists(uint256 tokenId);
    error NoStatusHistory(uint256 tokenId);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event TokenMinted(
        uint256 indexed tokenId, 
        address indexed to,
        uint256 amount, 
        bool consumable
    );
    
    event TokensBatchMinted(
        uint256[] tokenIds,
        address indexed to, 
        uint256[] amounts, 
        bool[] consumable
    );
    
    event TokenConsumed(
        uint256 indexed tokenId,
        address indexed from, 
        uint256 amount
    );
    
    event StatusUpdated(
        uint256 indexed tokenId, 
        string status, 
        uint40 timestamp
    );
    
    event TokenMetadataUpdated(
        uint256 indexed tokenId, 
        string newUri
    );

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract
     * @param uri_ Base URI for token metadata
     * @param admin Address that will have admin role
     */
    function initialize(
        string memory uri_,
        address admin
    ) external initializer {
        __ERC1155_init(uri_);
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setupRole(MINTER_ROLE, admin);
        _setupRole(BURNER_ROLE, admin);
        _setupRole(STATUS_UPDATER_ROLE, admin);
        _setupRole(UPGRADER_ROLE, admin);
    }

    /*//////////////////////////////////////////////////////////////
                              TOKEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mints a new token
     * @param to Address to mint to
     * @param amount Amount of tokens to mint
     * @param uri_ Token URI for metadata
     * @param isConsumable Flag indicating if token can be consumed
     * @return uint256 ID of the newly minted token
     */
    function mint(
        address to,
        uint256 amount,
        string calldata uri_,
        bool isConsumable
    ) external onlyRole(MINTER_ROLE) returns (uint256) {
        if (amount == 0) revert ZeroMintAmount();
        
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        
        _mint(to, newTokenId, amount, "");
        _consumableTokens[newTokenId] = isConsumable;
        _tokenURIs[newTokenId] = uri_;
        
        emit TokenMinted(newTokenId, to, amount, isConsumable);
        return newTokenId;
    }

    /**
     * @notice Batch mints multiple tokens
     * @param to Address to mint to
     * @param amounts Array of token amounts
     * @param uris Array of token URIs
     * @param isConsumable Array of consumable flags
     * @return uint256[] Array of newly minted token IDs
     */
    function batchMint(
        address to,
        uint256[] calldata amounts,
        string[] calldata uris,
        bool[] calldata isConsumable
    ) external onlyRole(MINTER_ROLE) returns (uint256[] memory) {
        if (amounts.length != uris.length || amounts.length != isConsumable.length) 
            revert InvalidBatchInput();

        uint256[] memory newTokenIds = new uint256[](amounts.length);

        for (uint256 i = 0; i < amounts.length; i++) {
            if (amounts[i] == 0) revert ZeroMintAmount();
            
            _tokenIds.increment();
            uint256 newTokenId = _tokenIds.current();
            newTokenIds[i] = newTokenId;

            _mint(to, newTokenId, amounts[i], "");
            _consumableTokens[newTokenId] = isConsumable[i];
            _tokenURIs[newTokenId] = uris[i];
        }

        emit TokensBatchMinted(newTokenIds, to, amounts, isConsumable);
        return newTokenIds;
    }

    /**
     * @notice Consumes (burns) a token
     * @param from Address to burn from
     * @param tokenId ID of token to consume
     * @param amount Amount to consume
     */
    function consume(
        address from,
        uint256 tokenId, 
        uint256 amount
    ) external onlyRole(BURNER_ROLE) {
        if (!_consumableTokens[tokenId]) revert TokenNotConsumable(tokenId);
        _burn(from, tokenId, amount);
        emit TokenConsumed(tokenId, from, amount);
    }

    /*//////////////////////////////////////////////////////////////
                              STATUS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates token status
     * @param tokenId Token ID to update
     * @param status New status string
     */
    function updateStatus(
        uint256 tokenId,
        string calldata status
    ) external onlyRole(STATUS_UPDATER_ROLE) {
        if (bytes(status).length == 0) revert EmptyStatus();
        if (!_exists(tokenId)) revert TokenNotExists(tokenId);
        
        uint256 currentCount = _updateCounts[tokenId];
        _statusUpdates[tokenId][currentCount] = StatusUpdate({
            status: status,
            timestamp: uint40(block.timestamp)
        });
        _updateCounts[tokenId] = currentCount + 1;
        
        emit StatusUpdated(tokenId, status, uint40(block.timestamp));
    }

    /**
     * @notice Gets current status of a token
     * @param tokenId Token ID to query
     * @return StatusUpdate Current status and timestamp
     */
    function getCurrentStatus(uint256 tokenId) 
        external 
        view 
        returns (StatusUpdate memory) 
    {
        uint256 count = _updateCounts[tokenId];
        if (count == 0) revert NoStatusHistory(tokenId);
        return _statusUpdates[tokenId][count - 1];
    }

    /**
     * @notice Gets complete status history of a token
     * @param tokenId Token ID to query
     * @return StatusUpdate[] Array of all status updates
     */
    function getStatusHistory(uint256 tokenId) 
        external 
        view 
        returns (StatusUpdate[] memory) 
    {
        uint256 count = _updateCounts[tokenId];
        if (count == 0) revert NoStatusHistory(tokenId);
        
        StatusUpdate[] memory history = new StatusUpdate[](count);
        for (uint256 i = 0; i < count; i++) {
            history[i] = _statusUpdates[tokenId][i];
        }
        return history;
    }

    /*//////////////////////////////////////////////////////////////
                            METADATA LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates token URI
     * @param tokenId Token ID to update
     * @param newUri New URI for token metadata
     */
    function setTokenURI(
        uint256 tokenId, 
        string calldata newUri
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_exists(tokenId)) revert TokenNotExists(tokenId);
        _tokenURIs[tokenId] = newUri;
        emit TokenMetadataUpdated(tokenId, newUri);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if a token exists
     * @param tokenId Token ID to check
     * @return bool Whether the token exists
     */
    function _exists(uint256 tokenId) internal view returns (bool) {
        return tokenId > 0 && tokenId <= _tokenIds.current();
    }

    /**
     * @notice Gets token URI
     * @param tokenId Token ID to query
     * @return string Token URI
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) revert TokenNotExists(tokenId);
        return _tokenURIs[tokenId];
    }

    /**
     * @notice Checks if a token is consumable
     * @param tokenId Token ID to check
     * @return bool Whether the token is consumable
     */
    function isConsumable(uint256 tokenId) external view returns (bool) {
        return _consumableTokens[tokenId];
    }

    /*//////////////////////////////////////////////////////////////
                            UPGRADEABILITY
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {}

    /**
     * @dev Required override for AccessControl
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC1155Upgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
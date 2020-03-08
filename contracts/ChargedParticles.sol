// ChargedParticles.sol -- Interest-bearing NFTs
// MIT License
// Copyright (c) 2019, 2020 Rob Secord <robsecord.eth>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// Reduce deployment gas costs by limiting the size of text used in error messages
// ERROR CODES:
//  300:        ERC1155
//      301         Invalid Recipient
//      302         Invalid on-received message
//      303         Invalid arrays length
//      304         Invalid type
//      305         Invalid owner/operator
//      306         Insufficient balance
//      307         Invalid URI for Type
//  400:        ChargedParticles
//      401         Invalid Method
//      402         Unregistered Type
//      403         Particle has no Charge
//      404         Insufficient ETH Balance
//      405         Insufficient DAI Balance
//      406         Invalid value for "requiredDai" parameter
//      407         No access to Mint (Private Type)
//      408         Transfer Failed
//      409         Particle has insufficient charge
//      410         Particle must be non-fungible to hold a charge
//      411         Unregistered Asset Pairing
//      412         Invalid Pairing Token Address
//      413         Creator Mint Fee is too high
//      414         Asset-Pair ID does not exist
//      415         Asset-Pair not enabled in Escrow
//      416         ION Token already created
//      417         Contract paused

pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/introspection/IERC165.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "../node_modules/multi-token-standard/contracts/interfaces/IERC1155.sol";
import "../node_modules/multi-token-standard/contracts/interfaces/IERC1155TokenReceiver.sol";
import "./IChargedParticlesEscrow.sol";
import "./assets/INucleus.sol";

/**
 * @dev Implementation of ERC1155 Multi-Token Standard contract
 * @dev see node_modules/multi-token-standard/contracts/tokens/ERC1155/ERC1155.sol
 */
contract ERC1155 is Initializable, IERC165 {
    using Address for address;
    using SafeMath for uint256;

    uint256 constant internal TYPE_MASK = uint256(uint128(~0)) << 128;
    uint256 constant internal NF_INDEX_MASK = uint128(~0);
    uint256 constant internal TYPE_NF_BIT = 1 << 255;
    bytes32 constant internal ACCOUNT_HASH = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
    bytes4 constant internal INTERFACE_SIGNATURE_ERC165 = 0x01ffc9a7;
    bytes4 constant internal INTERFACE_SIGNATURE_ERC1155 = 0xd9b67a26;
    bytes4 constant internal ERC1155_RECEIVED_VALUE = 0xf23a6e61;
    bytes4 constant internal ERC1155_BATCH_RECEIVED_VALUE = 0xbc197c81;

    uint256 internal nonce;
    mapping (address => mapping(uint256 => uint256)) internal balances;
    mapping (address => mapping(address => bool)) internal operators;
    mapping (uint256 => address) internal nfOwners;
    mapping (uint256 => uint256) internal maxIndex;
    mapping (uint256 => string) internal tokenUri;

    event TransferSingle(address indexed _operator, address indexed _from, address indexed _to, uint256 _id, uint256 _amount);
    event TransferBatch(address indexed _operator, address indexed _from, address indexed _to, uint256[] _ids, uint256[] _amounts);
    event ApprovalForAll(address indexed _owner, address indexed _operator, bool _approved);
    event URI(uint256 indexed _id, string _uri); // ID = Type or Token ID

    function initialize() public initializer {
    }

    function uri(uint256 _id) public view returns (string memory) {
        return tokenUri[_id];
    }

    function supportsInterface(bytes4 _interfaceID) external view returns (bool) {
        if (_interfaceID == INTERFACE_SIGNATURE_ERC165 ||
        _interfaceID == INTERFACE_SIGNATURE_ERC1155) {
            return true;
        }
        return false;
    }

    function ownerOf(uint256 _tokenId) public view returns (address) {
        require(_tokenId & TYPE_NF_BIT == TYPE_NF_BIT, "E304");
        return nfOwners[_tokenId];
    }

    function balanceOf(address _tokenOwner, uint256 _tokenId) public view returns (uint256) {
        if ((_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) && (_tokenId & NF_INDEX_MASK != 0)) {  // Non-Fungible Item
            return nfOwners[_tokenId] == _tokenOwner ? 1 : 0;
        }
        return balances[_tokenOwner][_tokenId];
    }

    function balanceOfBatch(address[] memory _owners, uint256[] memory _tokenIds) public view returns (uint256[] memory) {
        require(_owners.length == _tokenIds.length, "E303");

        uint256[] memory _balances = new uint256[](_owners.length);
        for (uint256 i = 0; i < _owners.length; ++i) {
            uint256 id = _tokenIds[i];
            if ((id & TYPE_NF_BIT == TYPE_NF_BIT) && (id & NF_INDEX_MASK != 0)) { // Non-Fungible Item
                _balances[i] = nfOwners[id] == _owners[i] ? 1 : 0;
            } else {
                _balances[i] = balances[_owners[i]][id];
            }
        }

        return _balances;
    }

    function setApprovalForAll(address _operator, bool _approved) external {
        operators[msg.sender][_operator] = _approved;
        emit ApprovalForAll(msg.sender, _operator, _approved);
    }

    function isApprovedForAll(address _tokenOwner, address _operator) public view returns (bool isOperator) {
        return operators[_tokenOwner][_operator];
    }

    function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _amount, bytes memory _data) public {
        require((msg.sender == _from) || isApprovedForAll(_from, msg.sender), "E305");
        require(_to != address(0),"E301");

        _safeTransferFrom(_from, _to, _id, _amount);
        _callonERC1155Received(_from, _to, _id, _amount, _data);
    }

    function safeBatchTransferFrom(address _from, address _to, uint256[] memory _ids, uint256[] memory _amounts, bytes memory _data) public {
        require((msg.sender == _from) || isApprovedForAll(_from, msg.sender), "E305");
        require(_to != address(0),"E301");

        _safeBatchTransferFrom(_from, _to, _ids, _amounts);
        _callonERC1155BatchReceived(_from, _to, _ids, _amounts, _data);
    }

    function _safeTransferFrom(address _from, address _to, uint256 _id, uint256 _amount) internal {
        // Non-Fungible
        if (_id & TYPE_NF_BIT == TYPE_NF_BIT) {
            require(nfOwners[_id] == _from);
            nfOwners[_id] = _to;
            _amount = 1;
        }
        // Fungible
        else {
            require(_amount <= balances[_from][_id]);
            balances[_from][_id] = balances[_from][_id].sub(_amount); // Subtract amount
            balances[_to][_id] = balances[_to][_id].add(_amount);     // Add amount
        }

        // Emit event
        emit TransferSingle(msg.sender, _from, _to, _id, _amount);
    }

    function _safeBatchTransferFrom(address _from, address _to, uint256[] memory _ids, uint256[] memory _amounts) internal {
        require(_ids.length == _amounts.length, "E303");

        uint256 id;
        uint256 amount;
        uint256 nTransfer = _ids.length;
        for (uint256 i = 0; i < nTransfer; ++i) {
            id = _ids[i];
            amount = _amounts[i];

            if (id & TYPE_NF_BIT == TYPE_NF_BIT) { // Non-Fungible
                require(nfOwners[id] == _from);
                nfOwners[id] = _to;
            } else {
                require(amount <= balances[_from][id]);
                balances[_from][id] = balances[_from][id].sub(amount);
                balances[_to][id] = balances[_to][id].add(amount);
            }
        }

        emit TransferBatch(msg.sender, _from, _to, _ids, _amounts);
    }

    function _callonERC1155Received(address _from, address _to, uint256 _id, uint256 _amount, bytes memory _data) internal {
        // Check if recipient is contract
        if (_to.isContract()) {
            bytes4 retval = IERC1155TokenReceiver(_to).onERC1155Received(msg.sender, _from, _id, _amount, _data);
            require(retval == ERC1155_RECEIVED_VALUE, "E302");
        }
    }

    function _callonERC1155BatchReceived(address _from, address _to, uint256[] memory _ids, uint256[] memory _amounts, bytes memory _data) internal {
        // Pass data if recipient is contract
        if (_to.isContract()) {
            bytes4 retval = IERC1155TokenReceiver(_to).onERC1155BatchReceived(msg.sender, _from, _ids, _amounts, _data);
            require(retval == ERC1155_BATCH_RECEIVED_VALUE, "E302");
        }
    }

    function _createType(string memory _uri, bool _isNF) internal returns (uint256 _type) {
        require(bytes(_uri).length > 0, "E307");

        _type = (++nonce << 128);
        if (_isNF) {
            _type = _type | TYPE_NF_BIT;
        }
        tokenUri[_type] = _uri;

        // emit a Transfer event with Create semantic to help with discovery.
        emit TransferSingle(msg.sender, address(0x0), address(0x0), _type, 0);
        emit URI(_type, _uri);
    }

    function _mint(address _to, uint256 _type, uint256 _amount, string memory _URI, bytes memory _data) internal returns (uint256) {
        uint256 _tokenId;

        // Non-fungible
        if (_type & TYPE_NF_BIT == TYPE_NF_BIT) {
            uint256 index = maxIndex[_type].add(1);
            maxIndex[_type] = index;

            _tokenId  = _type | index;
            nfOwners[_tokenId] = _to;
            tokenUri[_tokenId] = _URI;
            _amount = 1;
        }

        // Fungible
        else {
            _tokenId = _type;
            maxIndex[_type] = maxIndex[_type].add(_amount);
            balances[_to][_type] = balances[_to][_type].add(_amount);
        }

        emit TransferSingle(msg.sender, address(0x0), _to, _tokenId, _amount);
        _callonERC1155Received(address(0x0), _to, _tokenId, _amount, _data);

        return _tokenId;
    }

    function _mintBatch(address _to, uint256[] memory _types, uint256[] memory _amounts, string[] memory _URIs, bytes memory _data) internal returns (uint256[] memory) {
        require(_types.length == _amounts.length, "E303");
        uint256 _type;
        uint256 _amount;
        uint256 _index;
        uint256 _tokenId;
        uint256 _count = _types.length;

        uint256[] memory _tokenIds = new uint256[](_count);

        for (uint256 i = 0; i < _count; i++) {
            _type = _types[i];
            _amount = _amounts[i];

            // Non-fungible
            if (_type & TYPE_NF_BIT == TYPE_NF_BIT) {
                _index = maxIndex[_type].add(1);
                maxIndex[_type] = _index;

                _tokenId  = _type | _index;
                nfOwners[_tokenId] = _to;
                _tokenIds[i] = _tokenId;
                tokenUri[_tokenId] = _URIs[i];
                _amounts[i] = 1;
            }

            // Fungible
            else {
                _tokenIds[i] = _type;
                maxIndex[_type] = maxIndex[_type].add(_amount);
                balances[_to][_type] = balances[_to][_type].add(_amount);
            }
        }

        emit TransferBatch(msg.sender, address(0x0), _to, _tokenIds, _amounts);
        _callonERC1155BatchReceived(address(0x0), _to, _tokenIds, _amounts, _data);

        return _tokenIds;
    }

    function _burn(address _from, uint256 _tokenId, uint256 _amount) internal {
        // Non-fungible
        if (_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) {
            address _tokenOwner = ownerOf(_tokenId);
            require(_tokenOwner == _from || isApprovedForAll(_tokenOwner, _from), "E305");
            nfOwners[_tokenId] = address(0x0);
            tokenUri[_tokenId] = "";
            _amount = 1;
        }

        // Fungible
        else {
            require(balanceOf(_from, _tokenId) >= _amount, "E306");
//            maxIndex[_tokenId] = maxIndex[_tokenId].sub(_amount);
            balances[_from][_tokenId] = balances[_from][_tokenId].sub(_amount);
        }

        emit TransferSingle(msg.sender, _from, address(0x0), _tokenId, _amount);
    }

    function _burnBatch(address _from, uint256[] memory _tokenIds, uint256[] memory _amounts) internal {
        require(_tokenIds.length == _amounts.length, "E303");

        uint256 _amount;
        uint256 _tokenId;
        address _tokenOwner;
        uint256 _count = _tokenIds.length;
        for (uint256 i = 0; i < _count; i++) {
            _tokenId = _tokenIds[i];
            _amount = _amounts[i];

            // Non-fungible
            if (_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) {
                _tokenOwner = ownerOf(_tokenId);
                require(_tokenOwner == _from || isApprovedForAll(_tokenOwner, _from), "E305");
                nfOwners[_tokenId] = address(0x0);
                tokenUri[_tokenId] = "";
                _amounts[i] = 1;
            }

            // Fungible
            else {
                require(balanceOf(_from, _tokenId) >= _amount, "E306");
//                maxIndex[_tokenId] = maxIndex[_tokenId].sub(_amount);
                balances[_from][_tokenId] = balances[_from][_tokenId].sub(_amount);
            }
        }

        emit TransferBatch(msg.sender, _from, address(0x0), _tokenIds, _amounts);
    }

    //    function isNonFungible(uint256 _id) public pure returns(bool) {
    //        return _id & TYPE_NF_BIT == TYPE_NF_BIT;
    //    }
    //    function isFungible(uint256 _id) public pure returns(bool) {
    //        return _id & TYPE_NF_BIT == 0;
    //    }
    //    function getNonFungibleIndex(uint256 _id) public pure returns(uint256) {
    //        return _id & NF_INDEX_MASK;
    //    }
    //    function getNonFungibleBaseType(uint256 _id) public pure returns(uint256) {
    //        return _id & TYPE_MASK;
    //    }
    //    function isNonFungibleBaseType(uint256 _id) public pure returns(bool) {
    //        // A base type has the NF bit but does not have an index.
    //        return (_id & TYPE_NF_BIT == TYPE_NF_BIT) && (_id & NF_INDEX_MASK == 0);
    //    }
    //    function isNonFungibleItem(uint256 _id) public pure returns(bool) {
    //        return (_id & TYPE_NF_BIT == TYPE_NF_BIT) && (_id & NF_INDEX_MASK != 0);
    //    }
}


/**
 * @notice Charged Particles Contract - Interest-Bearing NFTs
 */
contract ChargedParticles is Initializable, Ownable, ReentrancyGuard, ERC1155 {
    using SafeMath for uint256;
    using Address for address payable;

    /***********************************|
    |        Variables and Events       |
    |__________________________________*/

    uint256 constant internal DEPOSIT_FEE_MODIFIER = 1e4;   // 10000  (100%)
    uint256 constant internal MAX_CUSTOM_DEPOSIT_FEE = 2e3; // 2000   (20%)

    IChargedParticlesEscrow escrow;

    // Particles come in many "Types" created by Public Users.
    //   Each "Type" of Particle has a "Creator", who can set certain parameters
    //   for the Particle upon Creation.
    //   Fungible Tokens (ERC20) are called "Plasma" and all tokens are the same in value.
    //     - These tokens CAN NOT hold a charge, and do not require an underlying asset when minting.
    //   Non-Fungible Tokens (ERC721) are called "Particles" and all tokens are unique in value.
    //     - These particles CAN hold a charge, and require a deposit of the underlying asset when minting.
    //   Particle Creators can also set restrictions on who can "mint" their particles, the max supply and
    //     how much of the underlying asset is required to mint a particle (1 DAI maybe?).
    //   These values are all optional, and can be left at 0 (zero) to specify no-limits.
    // Non-Fungible Tokens can be either a Series or a Collection.
    //   A series is a Single, Unique Item with Multiple Copies. NFTs that minted of this type are numbered
    //     in series, and use the same metadata as the Original Item.
    //   A collection is a group of Unique Items with only one copy of each.  NFTs that are minted of this type
    //     are Unique and require their own metadata for each.

    //        TypeID => Access Type (BITS: 1=Public, 2=Private, 4=Series, 8=Collection)
    mapping (uint256 => uint8) internal registeredTypes;

    //        TypeID => Type Creator
    mapping (uint256 => address) internal typeCreator;

    //        TypeID => Max Supply
    mapping (uint256 => uint256) internal typeSupply;

    //        TypeID => Eth-to-Token Price of Plasma set by Type Creator
    mapping (uint256 => uint256) internal plasmaPrice;

    //        TypeID => Specific Asset-Pair to be used for this Type
    mapping (uint256 => bytes16) internal typeAssetPairId;

    // Allowed Asset-Pairs
    mapping (bytes16 => bool) internal assetPairEnabled;

    // Owner/Creator => ETH Fees earned by Creator
    mapping (address => uint256) internal collectedFees;

    // To Create "Types" (Fungible or Non-Fungible) there is a Fee.
    //  The Fee can be paid in ETH or in IONs.
    //  IONs are a custom ERC20 token minted within this contract.
    //  ETH paid upon minting is stored in contract, withdrawn by contract owner.
    //  IONs paid upon minting are burned.
    //  These values are completely optional and can be set to 0 to specify No Fee.
    uint256 internal createFeeEth;
    uint256 internal createFeeIon;

    // Internal ERC20 Token used for Creating Types;
    // needs to be created as a private ERC20 type within this contract
    uint256 internal ionTokenId;

    // Contract Version
    bytes16 public version;

    // Contract State
    bool isPaused;

    //
    // Modifiers
    //

    modifier whenNotPaused() {
        require(!isPaused, "E417");
        _;
    }

    //
    // Events
    //

    event ParticleTypeUpdated(uint256 indexed _particleTypeId, string indexed _symbol, bool indexed _isPrivate, bool _isSeries, string _assetPairId, uint256 _creatorFee, string _uri); // find latest in logs for full record
    event PlasmaTypeUpdated(uint256 indexed _plasmaTypeId, string indexed _symbol, bool indexed _isPrivate, uint256 _ethPerToken, uint256 _initialMint, string _uri);
    event ParticleMinted(address indexed _sender, address indexed _receiver, uint256 indexed _tokenId, string _uri);
    event ParticleBurned(address indexed _from, uint256 indexed _tokenId);
    event PlasmaMinted(address indexed _sender, address indexed _receiver, uint256 indexed _typeId, uint256 _amount);
    event PlasmaBurned(address indexed _from, uint256 indexed _typeId, uint256 _amount);
    event CreatorFeesWithdrawn(address indexed _sender, address indexed _receiver, uint256 _amount);
    event ContractFeesWithdrawn(address indexed _sender, address indexed _receiver, uint256 _amount);

    /***********************************|
    |          Initialization           |
    |__________________________________*/

    function initialize(address sender) public initializer {
        Ownable.initialize(sender);
        ReentrancyGuard.initialize();
        ERC1155.initialize();
        version = "v0.2.2";
    }

    /***********************************|
    |            Public Read            |
    |__________________________________*/

    /**
     * @notice Gets the Creator of a Token Type
     * @param _type     The Type ID of the Token
     * @return  The Creator Address
     */
    function getTypeCreator(uint256 _type) public view returns (address) {
        return typeCreator[_type];
    }

    /**
     * @notice Checks if a user is allowed to mint a Token by Type ID
     * @param _type     The Type ID of the Token
     * @param _amount   The amount of tokens to mint
     * @return  True if the user can mint the token type
     */
    function canMint(uint256 _type, uint256 _amount) public view returns (bool) {
        // Public
        if (registeredTypes[_type] & 1 == 1) {
            // Has Max
            if (typeSupply[_type] > 0) {
                return maxIndex[_type].add(_amount) <= typeSupply[_type];
            }
            // No Max
            return true;
        }
        // Private
        if (typeCreator[_type] != msg.sender) {
            return false;
        }
        // Has Max
        if (typeSupply[_type] > 0) {
            return maxIndex[_type].add(_amount) <= typeSupply[_type];
        }
        // No Max
        return true;
    }

    /**
     * @notice Gets the ETH price to create a Token Type
     * @param _isNF     True if the Type of Token to Create is a Non-Fungible Token
     * @return  The ETH price to create a type
     */
    function getCreationPrice(bool _isNF) public view returns (uint256 eth, uint256 ion) {
        eth = _isNF ? (createFeeEth.mul(2)) : createFeeEth;
        ion = _isNF ? (createFeeIon.mul(2)) : createFeeIon;
    }

    /**
     * @notice Gets the Number of this Particle in the Series/Collection
     */
    function getSeriesNumber(uint256 _tokenId) public pure returns (uint256) {
        return _tokenId & NF_INDEX_MASK;
    }

    /***********************************|
    |         Particle Physics          |
    |__________________________________*/

    /**
     * @notice Gets the Amount of Base DAI held in the Token (amount token was minted with)
     */
    function baseParticleMass(uint256 _tokenId) public view returns (uint256) {
        uint256 _type = _tokenId & TYPE_MASK;
        bytes16 _assetPairId = typeAssetPairId[_type];
        return escrow.baseParticleMass(address(this), _tokenId, _assetPairId);
    }

    /**
     * @notice Gets the amount of Charge the Particle has generated (it's accumulated interest)
     */
    function currentParticleCharge(uint256 _tokenId) public returns (uint256) {
        uint256 _type = _tokenId & TYPE_MASK;
        require(registeredTypes[_type] > 0, "E402");
        require(_tokenId & TYPE_NF_BIT == TYPE_NF_BIT, "E402");

        bytes16 _assetPairId = typeAssetPairId[_type];
        return escrow.currentParticleCharge(address(this), _tokenId, _assetPairId);
    }

    /***********************************|
    |        Public Create Types        |
    |__________________________________*/

    /**
     * @notice Creates a new Particle Type (NFT/ERC721) which can later be minted/burned
     *         NOTE: Requires payment in ETH or IONs
     @ @dev see _createParticle()
     */
    function createParticle(
        string memory _uri,
        string memory _symbol,
        bool _isPrivate,
        bool _isSeries,
        string memory _assetPairId,
        uint256 _maxSupply,
        uint256 _creatorFee,
        bool _payWithIons
    )
        public
        payable
        whenNotPaused
        returns (uint256 _particleTypeId)
    {
        address _self = address(this);
        (uint256 ethPrice, uint256 ionPrice) = getCreationPrice(true);

        if (_payWithIons) {
            _collectIons(msg.sender, ionPrice);
        } else {
            require(msg.value >= ethPrice, "E404");
        }

        // Create Particle Type
        _particleTypeId = _createParticle(
            msg.sender,     // Token Creator
            _uri,           // Token Metadata URI
            _symbol,        // Token Symbol
            _isPrivate,     // is Private?
            _isSeries,      // is Series?
            _assetPairId,   // Asset Pair for Type
            _maxSupply,     // Max Supply
            _creatorFee     // Deposit Fee for Creator
        );

        // Refund over-payment
        if (!_payWithIons) {
            collectedFees[_self] = ethPrice.add(collectedFees[_self]);
            uint256 overage = msg.value.sub(ethPrice);
            if (overage > 0) {
                msg.sender.sendValue(overage);
            }
        }
    }

    /**
     * @notice Creates a new Plasma Type (FT/ERC20) which can later be minted/burned
     *         NOTE: Requires payment in ETH or IONs
     @ @dev see _createPlasma()
     */
    function createPlasma(
        address _creator,
        string memory _uri,
        string memory _symbol,
        bool _isPrivate,
        uint256 _maxSupply,
        uint256 _ethPerToken,
        uint256 _initialMint,
        bool _payWithIons
    )
        public
        payable
        whenNotPaused
        returns (uint256 _plasmaTypeId)
    {
        address contractOwner = owner();
        (uint256 ethPrice, uint256 ionPrice) = getCreationPrice(false);

        if (_payWithIons) {
            _collectIons(msg.sender, ionPrice);
        } else {
            require(msg.value >= ethPrice, "E404");
        }

        // Create Plasma Type
        _plasmaTypeId = _createPlasma(
            _creator,       // Token Creator
            _uri,           // Token Metadata URI
            _symbol,        // Token Symbol
            _isPrivate,     // is Private?
            _maxSupply,     // Max Supply
            _ethPerToken,   // Initial Price per Token in ETH
            _initialMint    // Initial Amount to Mint
        );

        // Refund over-payment
        if (!_payWithIons) {
            collectedFees[contractOwner] = ethPrice.add(collectedFees[contractOwner]);
            uint256 overage = msg.value.sub(ethPrice);
            if (overage > 0) {
                msg.sender.sendValue(overage);
            }
        }
    }

    /***********************************|
    |            Public Mint            |
    |__________________________________*/

    /**
     * @notice Mints a new Particle of the specified Type
     *          Note: Requires Asset-Token to mint
     * @param _to           The owner address to assign the new token to
     * @param _type         The Type ID of the new token to mint
     * @param _assetAmount  The amount of Asset-Tokens to deposit
     * @param _uri          The Unique URI to the Token Metadata
     * @param _data         Custom data used for transferring tokens into contracts
     * @return  The ID of the newly minted token
     *
     * NOTE: Must approve THIS contract to TRANSFER your Asset-Token on your behalf
     */
    function mintParticle(
        address _to,
        uint256 _type,
        uint256 _assetAmount,
        string memory _uri,
        bytes memory _data
    )
        public
        whenNotPaused
        returns (uint256)
    {
        require((_type & TYPE_NF_BIT == TYPE_NF_BIT) && (_type & NF_INDEX_MASK == 0), "E304");
        require(canMint(_type, 1), "E407");

        // Series-Particles use the Metadata of their Type
        if (registeredTypes[_type] & 4 == 4) {
            _uri = tokenUri[_type];
        }

        // Mint Token
        uint256 _tokenId = _mint(_to, _type, 1, _uri, _data);
        typeCreator[_tokenId] = msg.sender;

        // Energize NFT Particles
        energizeParticle(_tokenId, _assetAmount);

        emit ParticleMinted(msg.sender, _to, _tokenId, _uri);
        return _tokenId;
    }

    /**
     * @notice Mints new Plasma of the specified Type
     * @param _to      The owner address to assign the new tokens to
     * @param _type    The Type ID of the tokens to mint
     * @param _amount  The amount of tokens to mint
     * @param _data    Custom data used for transferring tokens into contracts
     */
    function mintPlasma(
        address _to,
        uint256 _type,
        uint256 _amount,
        bytes memory _data
    )
        public
        whenNotPaused
        payable
    {
        require(_type & TYPE_NF_BIT == 0, "E304");
        require(canMint(_type, _amount), "E407");

        address creator = (_type == ionTokenId) ? owner() : typeCreator[_type];
        uint256 totalEth;
        uint256 ethPerToken;

        // Check Token Price
        if (msg.sender != creator) {
            ethPerToken = plasmaPrice[_type];
            totalEth = _amount.mul(ethPerToken);
            require(msg.value >= totalEth, "E404");
        }

        // Mint Token
        _mint(_to, _type, _amount, "", _data);
        emit PlasmaMinted(msg.sender, _to, _type, _amount);

        if (msg.sender != creator) {
            // Track Collected Fees
            collectedFees[creator] = totalEth.add(collectedFees[creator]);

            // Refund overpayment
            uint256 overage = msg.value.sub(totalEth);
            if (overage > 0) {
                msg.sender.sendValue(overage);
            }
        }
    }

    /***********************************|
    |            Public Burn            |
    |__________________________________*/

    /**
     * @notice Destroys a Particle and releases the underlying Asset + Interest (Mass + Charge)
     * @param _tokenId  The ID of the token to burn
     */
    function burnParticle(uint256 _tokenId) public {
        address _self = address(this);
        address _tokenOwner;
        bytes16 _assetPairId;

        // Verify Token
        require((_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) && (_tokenId & NF_INDEX_MASK == 0), "E304");
        uint256 _type = _tokenId & TYPE_MASK;
        require(registeredTypes[_type] > 0, "E402");

        // Prepare Particle Release
        _tokenOwner = ownerOf(_tokenId);
        _assetPairId = typeAssetPairId[_type];
        escrow.releaseParticle(_tokenOwner, _self, _tokenId, _assetPairId);

        // Burn Token
        _burn(msg.sender, _tokenId, 1);

        // Release Particle (Payout Asset + Interest)
        escrow.finalizeRelease(_tokenOwner, _self, _tokenId, _assetPairId);

        emit ParticleBurned(msg.sender, _tokenId);
    }

    /**
     * @notice Destroys Plasma
     * @param _typeId   The type of token to burn
     * @param _amount   The amount of tokens to burn
     */
    function burnPlasma(uint256 _typeId, uint256 _amount) public {
        // Verify Token
        require(_typeId & TYPE_NF_BIT == 0, "E304");
        require(registeredTypes[_typeId] > 0, "E402");

        // Burn Token
        _burn(msg.sender, _typeId, _amount);

        emit PlasmaBurned(msg.sender, _typeId, _amount);
    }

    /***********************************|
    |        Energize Particle          |
    |__________________________________*/

    /**
     * @notice Allows the owner/operator of the Particle to add additional Asset Tokens
     */
    function energizeParticle(uint256 _tokenId, uint256 _assetAmount)
        public
        whenNotPaused
        returns (uint256)
    {
        uint256 _type = _tokenId & TYPE_MASK;
        bytes16 _assetPairId = typeAssetPairId[_type];
        require((_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) && (_tokenId & NF_INDEX_MASK == 0), "E304");

        // Transfer Asset Token from User to Contract
        _collectAssetToken(msg.sender, _assetPairId, _assetAmount);

        // Energize Particle
        return escrow.energizeParticle(address(this), _tokenId, _assetPairId, _assetAmount);
    }

    /***********************************|
    |        Discharge Particle         |
    |__________________________________*/

    /**
     * @notice Allows the owner/operator of the Particle to collect/transfer the interest generated
     *  from the token without removing the underlying Asset that is held in the token
     */
    function dischargeParticle(address _receiver, uint256 _tokenId) public returns (uint256, uint256) {
        uint256 _type = _tokenId & TYPE_MASK;
        bytes16 _assetPairId = typeAssetPairId[_type];
        return escrow.dischargeParticle(_receiver, address(this), _tokenId, _assetPairId);
    }

    /**
     * @notice Allows the owner/operator of the Particle to collect/transfer a specific amount of
     *  the interest generated from the token without removing the underlying Asset that is held in the token
     */
    function dischargeParticle(address _receiver, uint256 _tokenId, uint256 _assetAmount) public returns (uint256, uint256) {
        uint256 _type = _tokenId & TYPE_MASK;
        bytes16 _assetPairId = typeAssetPairId[_type];
        return escrow.dischargeParticle(_receiver, address(this), _tokenId, _assetPairId, _assetAmount);
    }


    /***********************************|
    |           Type Creator            |
    |__________________________________*/

    /**
     * @dev Allows contract owner to withdraw any fees earned
     */
    function withdrawCreatorFees(address payable _receiver, uint256 _typeId) public {
        address creator = typeCreator[_typeId];
        require(msg.sender == creator, "E305");

        // Withdraw Particle Deposit Fees from Escrow
        escrow.withdrawCreatorFees(creator, _typeId);

        // Withdraw Plasma Minting Fees (ETH)
        uint256 _amount = collectedFees[creator];
        if (_amount > 0) {
            _receiver.sendValue(_amount);
        }
        emit CreatorFeesWithdrawn(msg.sender, _receiver, _amount);
    }

    /***********************************|
    |            Only Owner             |
    |__________________________________*/

    /**
     * @dev Setup the Creation/Minting Fees
     */
    function setupFees(uint256 _createFeeEth, uint256 _createFeeIon) public onlyOwner {
        createFeeEth = _createFeeEth;
        createFeeIon = _createFeeIon;
    }

    /**
     * @dev Toggle the "Paused" state of the contract
     */
    function setPausedState(bool _paused) public onlyOwner {
        isPaused = _paused;
    }

    /**
     * @dev Register the address of the escrow contract
     */
    function registerEscrow(address _escrowAddress) public onlyOwner {
        require(_escrowAddress != address(0x0), "E412");
        escrow = IChargedParticlesEscrow(_escrowAddress);
    }

    /**
     * @dev Register valid asset pairs (needs to mirror escrow)
     */
    function registerAssetPair(string memory _assetPairId) public onlyOwner {
        bytes16 _assetPair = _toBytes16(_assetPairId);
        require(escrow.isAssetPairEnabled(_assetPair), "E415");

        // Allow Escrow to Transfer Assets from this Contract
        address _assetTokenAddress = escrow.getAssetTokenAddress(_assetPair);
        IERC20(_assetTokenAddress).approve(address(escrow), uint(-1));
        assetPairEnabled[_assetPair] = true;
    }

    /**
     * @dev Toggle an Asset Pair
     */
    function disableAssetPair(string memory _assetPairId) public onlyOwner {
        bytes16 _assetPair = _toBytes16(_assetPairId);
        assetPairEnabled[_assetPair] = false;
    }

    /**
     * @dev Setup internal ION Token
     */
    function mintIons(string memory _uri, uint256 _maxSupply, uint256 _amount, uint256 _ethPerToken) public onlyOwner returns (uint256) {
        address contractOwner = owner();
        require(ionTokenId == 0, "E416");

        // Create ION Token Type;
        //  ERC20, Private, Limited
        ionTokenId = _createPlasma(
            contractOwner,  // Contract Owner
            _uri,           // Token Metadata URI
            "IONs",         // Token Symbol
            false,          // is Private?
            _maxSupply,     // Max Supply
            _ethPerToken,   // Initial Price per Token (~ $0.10)
            _amount         // Initial amount to mint
        );

        return ionTokenId;
    }

    /**
     * @dev Allows contract owner to withdraw any ETH fees earned
     *      Interest-token Fees are collected in Escrow, withdraw from there
     */
    function withdrawFees(address payable _receiver) public onlyOwner {
        require(_receiver != address(0x0), "E412");

        address contractOwner = owner();
        uint256 _amount = collectedFees[contractOwner];
        if (_amount > 0) {
            _receiver.sendValue(_amount);
        }
        emit ContractFeesWithdrawn(msg.sender, _receiver, _amount);
    }

    /***********************************|
    |         Private Functions         |
    |__________________________________*/

    /**
     * @notice Creates a new Particle Type (NFT) which can later be minted/burned
     * @param _creator          The address of the Creator of this Type
     * @param _uri              A unique URI for the Token Type which will serve the JSON metadata
     * @param _isPrivate        True if the Type is Private and can only be minted by the creator; otherwise anyone can mint
     * @param _assetPairId      The ID of the Asset-Pair that the Particle will use for the Underlying Assets
     * @param _maxSupply        The Max Supply of Tokens that can be minted
     *                          Provide a value of 0 for no limit
     * @param _creatorFee       The Fee that is collected for each Particle and paid to the Particle Type Creator
     *                          Collected when the Particle is Minted or Energized
     * @return The ID of the newly created Particle Type
     *         Use this ID when Minting Particles of this Type
     */
    function _createParticle(
        address _creator,
        string memory _uri,
        string memory _symbol,
        bool _isPrivate,
        bool _isSeries,
        string memory _assetPairId,
        uint256 _maxSupply,
        uint256 _creatorFee
    )
        internal
        returns (uint256 _particleTypeId)
    {
        bytes16 _assetPair = _toBytes16(_assetPairId);
        require(_creatorFee <= MAX_CUSTOM_DEPOSIT_FEE, "E413");
        require(assetPairEnabled[_assetPair], "E414");

        // Create Type
        _particleTypeId = _createType(_uri, true); // ERC-1155 Non-Fungible

        // Type Access (Public or Private, Series or Collection)
        registeredTypes[_particleTypeId] = (_isPrivate ? 2 : 1) & (_isSeries ? 4 : 8);

        // Max Supply of Token; 0 = No Max
        typeSupply[_particleTypeId] = _maxSupply;

        // Creator of Type
        typeCreator[_particleTypeId] = _creator;
        escrow.registerCreatorSetting_FeeCollector(_particleTypeId, _creator);

        // Type Asset-Pair
        typeAssetPairId[_particleTypeId] = _assetPair;
        escrow.registerCreatorSetting_AssetPair(_particleTypeId, _assetPair);

        // The Deposit Fee for Creators
        escrow.registerCreatorSetting_DepositFee(_particleTypeId, _assetPair, _creatorFee);

        emit ParticleTypeUpdated(_particleTypeId, _symbol, _isPrivate, _isSeries, _assetPairId, _creatorFee, _uri);
    }

    /**
     * @notice Creates a new Plasma Type (FT) which can later be minted/burned
     * @param _creator          The address of the Creator of this Type
     * @param _uri              A unique URI for the Token Type which will serve the JSON metadata
     * @param _isPrivate        True if the Type is Private and can only be minted by the creator; otherwise anyone can mint
     * @param _maxSupply        The Max Supply of Tokens that can be minted
     *                          Provide a value of 0 for no limit
     * @param _ethPerToken      The ETH Price of each Token when sold to public
     * @param _initialMint      The amount of tokens to initially mint
     * @return The ID of the newly created Plasma Type
     *         Use this ID when Minting Plasma of this Type
     */
    function _createPlasma(
        address _creator,
        string memory _uri,
        string memory _symbol,
        bool _isPrivate,
        uint256 _maxSupply,
        uint256 _ethPerToken,
        uint256 _initialMint
    )
        internal
        returns (uint256 _plasmaTypeId)
    {
        // Create Type
        _plasmaTypeId = _createType(_uri, false); // ERC-1155 Fungible

        // Type Access (Public or Private minting)
        registeredTypes[_plasmaTypeId] = _isPrivate ? 2 : 1;

        // Creator of Type
        typeCreator[_plasmaTypeId] = _creator;

        // Max Supply of Token; 0 = No Max
        typeSupply[_plasmaTypeId] = _maxSupply;

        // The Eth-per-Token Fee for Minting
        plasmaPrice[_plasmaTypeId] = _ethPerToken;

        // Mint Initial Tokens
        if (_initialMint > 0) {
            _mint(_creator, _plasmaTypeId, _initialMint, "", "");
        }

        emit PlasmaTypeUpdated(_plasmaTypeId, _symbol, _isPrivate, _ethPerToken, _initialMint, _uri);
    }

    /**
     * @dev Collects the Required IONs from the users wallet during Type Creation and Burns them
     * @param _from  The owner address to collect the IONs from
     * @param _ions  The amount of IONs to collect from the user
     */
    function _collectIons(address _from, uint256 _ions) internal {
        // Burn IONs from User
        _burn(_from, ionTokenId, _ions);
    }

    /**
     * @dev Collects the Required Asset Token from the users wallet
     */
    function _collectAssetToken(address _from, bytes16 _assetPairId, uint256 _assetAmount) internal {
        address _assetTokenAddress = escrow.getAssetTokenAddress(_assetPairId);
        IERC20 _assetToken = IERC20(_assetTokenAddress);

        uint256 _userAssetBalance = _assetToken.balanceOf(_from);
        require(_assetAmount <= _userAssetBalance, "Insufficient Asset Token funds");
        require(_assetToken.transferFrom(_from, address(this), _assetAmount), "Failed to transfer Asset Token"); // Be sure to Approve this Contract to transfer your Asset Token
    }

    /**
     * @dev Convert a string to Bytes16
     */
    function _toBytes16(string memory source) private pure returns (bytes16 result) {
        bytes memory tmp = bytes(source);
        if (tmp.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 16))
        }
    }
}

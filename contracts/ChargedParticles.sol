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
//  100:        ADDRESS, OWNER, OPERATOR
//      101         Invalid Address
//      102         Sender is not owner
//      103         Sender is not owner or operator
//      104         Insufficient balance
//      105         Unable to send value, recipient may have reverted
//  200:        MATH
//      201         Addition Overflow
//      202         Subtraction Overflow
//      203         Multiplication overflow
//      204         Division by zero
//      205         Modulo by zero
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
    event URI(string _uri, uint256 indexed _type);

    function initialize() public initializer {
    }

    function uri(uint256 _tokenId) public view returns (string memory) {
        return tokenUri[_tokenId];
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
        emit URI(_uri, _type);
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
            maxIndex[_tokenId] = maxIndex[_tokenId].sub(_amount);
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
                maxIndex[_tokenId] = maxIndex[_tokenId].sub(_amount);
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

    function _uint2str(uint256 _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }

        uint256 j = _i;
        uint256 ii = _i;
        uint256 len;

        // Get number of bytes
        while (j != 0) {
            len++;
            j /= 10;
        }

        bytes memory bstr = new bytes(len);
        uint256 k = len - 1;

        // Get each individual ASCII
        while (ii != 0) {
            bstr[k--] = byte(uint8(48 + ii % 10));
            ii /= 10;
        }

        // Convert to string
        return string(bstr);
    }
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
    //   Particles can be Fungible (ERC20) where all tokens are the same in value.
    //     - These particles CAN NOT hold a charge, and do not require an underlying asset when minting.
    //   Particles can also be Non-Fungible (ERC721) where all tokens are unique in value.
    //     - These particles CAN hold a charge, and require a deposit of the underlying asset when minting.
    //   Particle Creators can also set restrictions on who can "mint" their particles, the max supply and
    //     how much of the underlying asset is required to mint a particle (1 DAI maybe?).
    //   These values are all optional, and can be left at 0 (zero) to specify no-limits.

    //        TypeID => Access Type (1=Public / 2=Private)
    mapping (uint256 => uint8) internal registeredTypes;

    //        TypeID => Type Creator
    mapping (uint256 => address) internal typeCreator;

    //        TypeID => Max Supply
    mapping (uint256 => uint256) internal typeCreatorSupply;

    //        TypeID => Deposit Fee required by Type Creator
    mapping (uint256 => uint16) internal typeCreatorDepositFee;

    //        TypeID => Specific Asset-Pair to be used for this Type
    mapping (uint256 => bytes16) internal typeCreatorAssetPairId;

    // Allowed Asset-Pairs
    mapping (bytes16 => bool) internal assetPairEnabled;

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

    //
    // Events
    //

    event ParticleTypeUpdated(uint256 indexed _typeId, string _uri, bool _isNF, bool _isPrivate, string _assetPairId, uint256 _maxSupply, uint16 _creatorFee); // find latest in logs for full record
    event ParticleMinted(uint256 indexed _tokenId, uint256 _amount, string _uri);
    event ParticleBurned(uint256 indexed _tokenId, uint256 _amount);

    /***********************************|
    |          Initialization           |
    |__________________________________*/

    function initialize(address sender) public initializer {
        Ownable.initialize(sender);
        ReentrancyGuard.initialize();
        ERC1155.initialize();
        version = "v0.1.5";
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
     * @return  True if the user can mint the token type
     */
    function canMint(uint256 _type, uint256 _amount) public view returns (bool) {
        // Public
        if (registeredTypes[_type] == 1) {
            // Has Max
            if (typeCreatorSupply[_type] > 0) {
                return maxIndex[_type] <= typeCreatorSupply[_type].add(_amount);
            }
            // No Max
            return true;
        }
        // Private
        if (typeCreator[_type] != msg.sender) {
            return false;
        }
        // Has Max
        if (typeCreatorSupply[_type] > 0) {
            return maxIndex[_type] <= typeCreatorSupply[_type].add(_amount);
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

    /***********************************|
    |         Particle Physics          |
    |__________________________________*/

    /**
     * @notice Gets the Amount of Base DAI held in the Token (amount token was minted with)
     */
    function baseParticleMass(uint256 _tokenId) public view returns (uint256) {
        uint256 _type = _tokenId & TYPE_MASK;
        bytes16 _assetPairId = typeCreatorAssetPairId[_type];
        return escrow.baseParticleMass(address(this), _tokenId, _assetPairId);
    }

    /**
     * @notice Gets the amount of Charge the Particle has generated (it's accumulated interest)
     */
    function currentParticleCharge(uint256 _tokenId) public returns (uint256) {
        uint256 _type = _tokenId & TYPE_MASK;
        require(registeredTypes[_type] > 0, "E402");
        require(_tokenId & TYPE_NF_BIT == TYPE_NF_BIT, "E402");

        bytes16 _assetPairId = typeCreatorAssetPairId[_type];
        return escrow.currentParticleCharge(address(this), _tokenId, _assetPairId);
    }

    /***********************************|
    |   Public Create Particle Types    |
    |__________________________________*/

    /**
     * @notice Creates a new Particle Type which can later be minted/burned
     *         NOTE: Requires payment in ETH
     @ @dev see _createParticle()
     */
    function createParticleWithEther(
        string memory _uri,
        bool _isNF,
        bool _isPrivate,
        string memory _assetPairId,
        uint256 _maxSupply,
        uint16 _creatorFee
    )
        public
        payable
        returns (uint256 _particleTypeId)
    {
        (uint256 ethPrice, ) = getCreationPrice(_isNF);
        require(msg.value >= ethPrice, "E404");

        // Create Particle Type
        _particleTypeId = _createParticle(
            msg.sender,
            _uri,
            _isNF,
            _isPrivate,
            _assetPairId,
            _maxSupply,
            _creatorFee
        );

        // Refund over-payment
        uint256 overage = msg.value.sub(ethPrice);
        if (overage > 0) {
            msg.sender.sendValue(overage);
        }
    }

    /**
     * @notice Creates a new Particle Type which can later be minted/burned
     *         NOTE: Requires payment in ION Tokens
     @ @dev see _createParticle()
     *
     * NOTE: Must approve THIS contract to TRANSFER your IONs on your behalf
     */
    function createParticleWithIons(
        string memory _uri,
        bool _isNF,
        bool _isPrivate,
        string memory _assetPairId,
        uint256 _maxSupply,
        uint16 _creatorFee
    )
        public
        returns (uint256 _particleTypeId)
    {
        ( , uint256 ionPrice) = getCreationPrice(_isNF);

        // Collect Ions as Payment
        _collectIons(msg.sender, ionPrice);

        // Create Particle Type
        _particleTypeId = _createParticle(
            msg.sender,
            _uri,
            _isNF,
            _isPrivate,
            _assetPairId,
            _maxSupply,
            _creatorFee
        );
    }

    /***********************************|
    |    Public Mint (ERC20 & ERC721)   |
    |__________________________________*/

    /**
     * @notice Mints a new Particle of the specified Type (can be Fungible or Non-Fungible)
     *          Note: Requires Asset-Token to mint Non-Fungible Tokens
     * @param _to           The owner address to assign the new token to
     * @param _type         The Type ID of the new token to mint
     * @param _amount       The amount of tokens to mint (always 1 for Non-Fungibles)
     * @param _assetAmount  The amount of Asset-Tokens to deposit for non-fungibles
     * @param _data         Custom data used for transferring tokens into contracts
     * @return  The ID of the newly minted token
     *
     * NOTE: Must approve THIS contract to TRANSFER your DAI on your behalf
     */
    function mintParticle(
        address _to,
        uint256 _type,
        uint256 _amount,
        uint256 _assetAmount,
        string memory _uri,
        bytes memory _data
    )
        public
        returns (uint256)
    {
        require(canMint(_type, _amount), "E407");

        // Mint Token
        uint256 _tokenId = _mint(_to, _type, _amount, _uri, _data);
        emit ParticleMinted(_tokenId, _amount, _uri);

        // Energize NFT Particles
        if (_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) {
            energizeParticle(_tokenId, _assetAmount);
        }

        return _tokenId;
    }

    /***********************************|
    |    Public Burn (ERC20 & ERC721)   |
    |__________________________________*/

    /**
     * @notice Destroys a Particle and releases the underlying Asset + Interest (Mass + Charge)
     * @param _tokenId  The ID of the token to burn
     * @param _amount   The amount of tokens to burn (always 1 for Non-Fungibles)
     */
    function burnParticle(uint256 _tokenId, uint256 _amount) public {
        address _self = address(this);
        address _tokenOwner;
        bytes16 _assetPairId;

        // Verify Token
        uint256 _type = _tokenId & TYPE_MASK;
        require(registeredTypes[_type] > 0, "E402");

        // NFTs Only
        if (_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) {
            // Prepare Particle Release
            _tokenOwner = ownerOf(_tokenId);
            _assetPairId = typeCreatorAssetPairId[_type];
            escrow.releaseParticle(_tokenOwner, _self, _tokenId, _assetPairId);
        }

        // Burn Token
        _burn(msg.sender, _tokenId, _amount);

        // NFTs Only
        if (_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) {
            // Release Particle (Payout Asset + Interest)
            escrow.finalizeRelease(_tokenOwner, _self, _tokenId, _assetPairId);
        }

        emit ParticleBurned(_tokenId, _amount);
    }

    /***********************************|
    |        Energize Particle          |
    |__________________________________*/

    /**
     * @notice Allows the owner/operator of the Particle to add additional Asset Tokens
     */
    function energizeParticle(uint256 _tokenId, uint256 _assetAmount) public returns (uint256) {
        uint256 _type = _tokenId & TYPE_MASK;
        bytes16 _assetPairId = typeCreatorAssetPairId[_type];
        address _reserveAddress = typeCreator[_type];
        uint256 _reserveFee = typeCreatorDepositFee[_type];

        // Transfer Asset Token from User to Contract
        _collectAssetToken(msg.sender, _assetPairId, _assetAmount);

        // Energize Particle
        return escrow.energizeParticle(address(this), _tokenId, _assetPairId, _assetAmount, _reserveAddress, _reserveFee);
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
        bytes16 _assetPairId = typeCreatorAssetPairId[_type];
        return escrow.dischargeParticle(_receiver, address(this), _tokenId, _assetPairId);
    }

    /**
     * @notice Allows the owner/operator of the Particle to collect/transfer a specific amount of
     *  the interest generated from the token without removing the underlying Asset that is held in the token
     */
    function dischargeParticle(address _receiver, uint256 _tokenId, uint256 _assetAmount) public returns (uint256, uint256) {
        uint256 _type = _tokenId & TYPE_MASK;
        bytes16 _assetPairId = typeCreatorAssetPairId[_type];
        return escrow.dischargeParticle(_receiver, address(this), _tokenId, _assetPairId, _assetAmount);
    }


    /***********************************|
    |        Type Creator Fees          |
    |__________________________________*/

    /**
     * @dev Allows contract owner to withdraw any fees earned
     */
    function withdrawCreatorFees() public {
        escrow.withdrawReserveFees(msg.sender);
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

    function registerEscrow(address _escrowAddress) public onlyOwner {
        require(_escrowAddress != address(0x0), "E412");

        // Register Escrow with this contract
        escrow = IChargedParticlesEscrow(_escrowAddress);

//        // Register this contract with the Escrow and set Rules
//        address _self = address(this);
//        escrow.registerParticleType(_self);
//        escrow.registerParticleSettingReleaseBurn(_self, true);
    }

    function registerAssetPair(string memory _assetPairId) public onlyOwner {
        bytes16 _assetPair = _toBytes16(_assetPairId);
        require(escrow.isAssetPairEnabled(_assetPair), "Asset-Pair not enabled in Escrow");

        // Allow Escrow to Transfer Assets from this Contract
        address _assetTokenAddress = escrow.getAssetTokenAddress(_assetPair);
        IERC20(_assetTokenAddress).approve(address(escrow), uint(-1));
        assetPairEnabled[_assetPair] = true;
    }

    function disableAssetPair(string memory _assetPairId) public onlyOwner {
        bytes16 _assetPair = _toBytes16(_assetPairId);
        assetPairEnabled[_assetPair] = false;
    }

    /**
     * @dev Setup internal ION Token
     */
    function mintIons(string memory _uri, uint256 _amount) public onlyOwner returns (uint256) {
        address contractOwner = owner();

        // Create ION Token Type;
        //  ERC20, Private, Limited
        ionTokenId = _createParticle(
            contractOwner,  // Contract Owner
            _uri,           // Token Metadata URI
            false,          // is Non-fungible?
            true,           // is Private?
            "",             // Asset-Pair-ID
            _amount,        // Max Supply
            0               // Creator Deposit Fee
        );

        // Mint ION Tokens to Contract Owner
        _mint(contractOwner, ionTokenId, _amount, "", "");

        // Remove owner of ION token to prevent further minting
        typeCreator[ionTokenId] = address(0x0);

        return ionTokenId;
    }

    /**
     * @dev Allows contract owner to withdraw any ETH fees earned
     *      Interest-token Fees are collected in Escrow, withdraw from there
     */
    function withdrawFees() public onlyOwner {
        uint256 _balance = address(this).balance;
        if (_balance > 0) {
            msg.sender.sendValue(_balance);
        }
    }

    /***********************************|
    |         Private Functions         |
    |__________________________________*/

    /**
     * @notice Creates a new Particle Type which can later be minted/burned
     * @param _creator          The address of the Creator of this Type
     * @param _uri              A unique URI for the Token Type which will serve the JSON metadata
     * @param _isNF             True if the Type is a Non-Fungible (only Non-Fungible Tokens can hold Asset Tokens and generate Interest)
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
        bool _isNF,
        bool _isPrivate,
        string memory _assetPairId,
        uint256 _maxSupply,
        uint16 _creatorFee
    )
        internal
        returns (uint256 _particleTypeId)
    {
        bytes16 _assetPair = _toBytes16(_assetPairId);
        require(_creatorFee <= MAX_CUSTOM_DEPOSIT_FEE, "E413");
        if (_isNF) {
            require(assetPairEnabled[_assetPair], "E414");
        }

        // Create Type
        _particleTypeId = _createType(_uri, _isNF);

        // Type Access (Public or Private minting)
        registeredTypes[_particleTypeId] = _isPrivate ? 2 : 1;

        // Creator of Type
        typeCreator[_particleTypeId] = _creator;

        // Type Asset-Pair
        typeCreatorAssetPairId[_particleTypeId] = _assetPair;

        // Max Supply of Token; 0 = No Max
        typeCreatorSupply[_particleTypeId] = _maxSupply;

        // The Deposit Fee for Creators
        typeCreatorDepositFee[_particleTypeId] = _creatorFee;

        emit ParticleTypeUpdated(_particleTypeId, _uri, _isNF, _isPrivate, _assetPairId, _maxSupply, _creatorFee);
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

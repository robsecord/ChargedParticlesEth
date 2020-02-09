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
        uint256 _type = _tokenId & TYPE_MASK;
        return string(abi.encodePacked(tokenUri[_type], _uint2str(_tokenId), ".json"));
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

    function _mint(address _to, uint256 _type, uint256 _amount, bytes memory _data) internal returns (uint256) {
        uint256 _tokenId;

        // Non-fungible
        if (_type & TYPE_NF_BIT == TYPE_NF_BIT) {
            uint256 index = maxIndex[_type].add(1);
            maxIndex[_type] = index;

            _tokenId  = _type | index;
            nfOwners[_tokenId] = _to;
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

    function _mintBatch(address _to, uint256[] memory _types, uint256[] memory _amounts, bytes memory _data) internal returns (uint256[] memory) {
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
            require(ownerOf(_tokenId) == _from, "E305");
            nfOwners[_tokenId] = address(0x0);
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
        uint256 _count = _tokenIds.length;
        for (uint256 i = 0; i < _count; i++) {
            _tokenId = _tokenIds[i];
            _amount = _amounts[i];

            // Non-fungible
            if (_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) {
                require(ownerOf(_tokenId) == _from, "E305");
                nfOwners[_tokenId] = address(0x0);
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

    /***********************************|
    |        Variables and Events       |
    |__________________________________*/

    uint256 constant internal DEPOSIT_FEE_MODIFIER = 1e4;   // 10000  (100%)
    uint256 constant internal MAX_CUSTOM_DEPOSIT_FEE = 2e3; // 2000   (20%)
    uint256 constant internal MIN_DEPOSIT_FEE = 1e6;        // 1000000 (0.000000000001 ETH  or  1000000 WEI)

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

    //        TypeID => Deposit Fees earned for Type Creator
    mapping (uint256 => uint256) internal typeCreatorCollectedFees;

    //        TypeID => Specific Asset-Pair to be used for this Type
    mapping (uint256 => bytes16) internal typeCreatorAssetPairId;

    //        TypeID => Allowed Limit of Asset Token [min, max]
    mapping (uint256 => uint256) internal typeCreatorAssetDepositMin;
    mapping (uint256 => uint256) internal typeCreatorAssetDepositMax;

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

    event TransferCharge(address indexed _ownerOrOperator, uint256 indexed _fromTokenId, uint256 indexed _toTokenId, uint256 _amount, bytes16 _assetPairId);

    /***********************************|
    |          Initialization           |
    |__________________________________*/

    function initialize(address sender) public initializer {
//         createFeeEth = 35 szabo;     //  ERC20  = 0.000035 ETH  (~ USD $0.005)
//                                      //  ERC721 = 0.000070 ETH  (~ USD $0.01)
//         createFeeIon = 10 ether;     //  ERC20  = 1 ION
//                                      //  ERC721 = 2 IONs
//         baseMintFee = 50;            //  0.5% of Interest-bearing Token from deposited Asset token

        Ownable.initialize(sender);
        ReentrancyGuard.initialize();
        ERC1155.initialize();
        version = "v0.1.3";
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

    /**
     * @dev Calculates the amount of Fees to be paid during Mint/Energize
     * @param _type                 The ID of the token to get totals for
     * @param _interestTokenAmount  The total amount of Interest-bearing Tokens received upon minting
     * @return  The amount of base fees and the amount of creator fees
     */
    function getDepositFees(uint256 _type, uint256 _interestTokenAmount) public view returns (uint256, uint256) {
        bytes16 _assetPairId = typeCreatorAssetPairId[_type];
        (uint256 _depositFee, uint256 _customFee) = escrow.getFeeForDeposit(address(this), _interestTokenAmount, _assetPairId);
        uint256 _creatorFee;
        if (typeCreatorDepositFee[_type] > 0) {
            _creatorFee = _interestTokenAmount.mul(typeCreatorDepositFee[_type]).div(DEPOSIT_FEE_MODIFIER);
        }
        return (_depositFee.add(_customFee), _creatorFee);
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
    function currentParticleCharge(uint256 _tokenId) public view returns (uint256) {
        uint256 _type = _tokenId & TYPE_MASK;
        require(registeredTypes[_type] > 0, "E402");
        require(_tokenId & TYPE_NF_BIT == TYPE_NF_BIT, "E402");

        bytes16 _assetPairId = typeCreatorAssetPairId[_type];
        return escrow.baseParticleMass(address(this), _tokenId, _assetPairId);
    }

    /**
     * @notice Allows the owner of the Token to collect the interest generated form the token
     *  without removing the underlying DAI that is held in the token
     */
    function dischargeParticle(address _receiver, uint256 _tokenId) public returns (uint256, uint256) {
        address _tokenOwner = ownerOf(_tokenId);
        require((_tokenOwner == msg.sender) || isApprovedForAll(_tokenOwner, msg.sender), "E103");

        uint256 _type = _tokenId & TYPE_MASK;
        bytes16 _assetPairId = typeCreatorAssetPairId[_type];
        return escrow.dischargeParticle(_receiver, address(this), _tokenId, _assetPairId);
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
        bytes16 _assetPairId,
        uint256 _assetMin,
        uint256 _assetMax,
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
            _assetMin,
            _assetMax,
            _maxSupply,
            _creatorFee
        );

        // Refund over-payment
        uint256 overage = msg.value.sub(ethPrice);
        if (overage > 0) {
            msg.sender.transfer(overage);
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
        bytes16 _assetPairId,
        uint256 _assetMin,
        uint256 _assetMax,
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
            _assetMin,
            _assetMax,
            _maxSupply,
            _creatorFee
        );
    }

    /***********************************|
    |    Public Mint (ERC20 & ERC721)   |
    |__________________________________*/

    /**
     * @notice Mints a new Particle of the specified Type (can be Fungible or Non-Fungible)
     *          Note: Requires DAI to mint Non-Fungible Tokens
     * @param _to       The owner address to assign the new token to
     * @param _type     The Type ID of the new token to mint
     * @param _amount   The amount of tokens to mint (always 1 for Non-Fungibles)
     * @param _data     Custom data used for transferring tokens into contracts
     * @return  The ID of the newly minted token
     *
     * NOTE: Must approve THIS contract to TRANSFER your DAI on your behalf
     */
//    function mintParticle(
//        address _to,
//        uint256 _type,
//        uint256 _amount,
//        uint256 _assetAmount,
//        bytes memory _data
//    )
//        public
//        returns (uint256)
//    {
//        require(canMint(_type, _amount), "E407");
//        address _self = address(this);
//
//        // Mint Token
//        uint256 _tokenId = _mint(_to, _type, _amount, _data);
//
//        if (_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) {
//            // Transfer DAI from User to Contract
//            uint256 _requiredAssets = typeAssetLimits[_type];
//            _collectRequiredDai(msg.sender, _requiredDai);
//
//            // Tokenize Interest
//            uint256 _preBalance = chai.balanceOf(_self);
//            chai.join(_self, _requiredDai);
//            uint256 _postBalance = chai.balanceOf(_self);
//
//            // Track Mass of each Particle
//            interestTokenBalance[_tokenId] = _getInitialMass(_tokenId, _postBalance.sub(_preBalance));
//        }
//
//        return _tokenId;
//    }

    /**
     * @notice Mints multiple new Particles of the specified Types (can be Fungible and/or Non-Fungible)
     *          Note: Requires DAI to mint Non-Fungible Tokens
     * @param _to       The owner address to assign the new tokens to
     * @param _types    The Type IDs of the new tokens to mint
     * @param _amounts  The amount of tokens to mint (always 1 for Non-Fungibles)
     * @param _data     Custom data used for transferring tokens into contracts
     * @return  The IDs of the newly minted tokens
     *
     * NOTE: Must approve THIS contract to TRANSFER your DAI on your behalf
     */
//    function mintParticles(address _to, uint256[] memory _types, uint256[] memory _amounts, bytes memory _data) public returns (uint256[] memory) {
//        address _self = address(this);
//        uint256 i;
//        uint256 _type;
//        uint256 _amount;
//        uint256 _tokenId;
//        uint256 _totalDai;
//        uint256 _requiredDai;
//        uint256 _count = _types.length;
//
//        for (i = 0; i < _count; ++i) {
//            _type = _types[i];
//            _amount = _amounts[i];
//            require(canMint(_type, _amount), "E407");
//            _requiredDai = typeAssetLimits[_type];
//            _totalDai = _requiredDai.add(_totalDai);
//        }
//
//        // Mint Tokens
//        uint256[] memory _tokenIds = _mintBatch(_to, _types, _amounts, _data);
//
//        if (_totalDai > 0) {
//            // Transfer DAI from User to Contract
//            _collectRequiredDai(msg.sender, _totalDai);
//
//            uint256 _balance = chai.balanceOf(_self);
//            for (i = 0; i < _count; ++i) {
//                _tokenId = _tokenIds[i];
//                _type = _tokenId & TYPE_MASK;
//                _requiredDai = typeAssetLimits[_type];
//
//                if (_requiredDai > 0) {
//                    // Tokenize Interest
//                    chai.join(_self, _requiredDai);
//
//                    // Track Mass of each Particle
//                    interestTokenBalance[_tokenId] = _getInitialMass(_tokenId, chai.balanceOf(_self).sub(_balance));
//                    _balance = chai.balanceOf(_self);
//                }
//            }
//        }
//        return _tokenIds;
//    }

    /***********************************|
    |    Public Burn (ERC20 & ERC721)   |
    |__________________________________*/

    /**
     * @notice Destroys a Particle and releases the underlying DAI + Interest (Mass + Charge)
     * @param _tokenId  The ID of the token to burn
     * @param _amount   The amount of tokens to burn (always 1 for Non-Fungibles)
     */
//    function burnParticle(uint256 _tokenId, uint256 _amount) public {
//        // Verify Token
//        uint256 _type = _tokenId & TYPE_MASK;
//        require(registeredTypes[_type] > 0, "E402");
//
//        // Burn Token
//        _burn(msg.sender, _tokenId, _amount);
//
//        // Payout Dai + Interest
//        if (_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) {
//            uint256 _tokenChai = interestTokenBalance[_tokenId];
//            interestTokenBalance[_tokenId] = 0;
//            _payoutFundedDai(msg.sender, _tokenChai);
//        }
//    }

    /**
     * @notice Destroys multiple Particles and releases the underlying DAI + Interest (Mass + Charge)
     * @param _tokenIds     The IDs of the tokens to burn
     * @param _amounts      The amounts of the tokens to burn (always 1 for Non-Fungibles)
     */
//    function burnParticles(uint256[] memory _tokenIds, uint256[] memory _amounts) public {
//        // Verify Token
//        uint256 _tokenId;
//        uint256 _totalChai;
//        uint256 _count = _tokenIds.length;
//        for (uint256 i = 0; i < _count; ++i) {
//            _tokenId = _tokenIds[i];
//            require(registeredTypes[_tokenId & TYPE_MASK] > 0, "E402");
//
//            if (_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) {
//                _totalChai = interestTokenBalance[_tokenId].add(_totalChai);
//                interestTokenBalance[_tokenId] = 0;
//            }
//        }
//
//        // Burn Tokens
//        _burnBatch(msg.sender, _tokenIds, _amounts);
//
//        // Payout Dai + Interest
//        if (_totalChai > 0) {
//            _payoutFundedDai(msg.sender, _totalChai);
//        }
//    }

    /***********************************|
    |         Transfer Charge           |
    |__________________________________*/

    /**
     * @notice Transfers a tokens full-charge from one particle to another
     * @param _from         The owner address to transfer the Charge from
     * @param _fromTokenId  The Token ID to transfer the Charge from
     * @param _toTokenId    The Token ID to transfer the Charge to
     */
//    function transferCharge(address _from, uint256 _fromTokenId, uint256 _toTokenId) public {
//        require((msg.sender == _from) || isApprovedForAll(_from, msg.sender), "E305");
//
//        // Transfer Full Amount of Charge
//        uint256 currentCharge = currentParticleCharge(_fromTokenId); // In Funding Token
//        _transferCharge(_from, _fromTokenId, _toTokenId, currentCharge);
//    }

    /**
     * @notice Transfers some of a tokens charge from one particle to another
     * @param _from         The owner address to transfer the Charge from
     * @param _fromTokenId  The Token ID to transfer the Charge from
     * @param _toTokenId    The Token ID to transfer the Charge to
     * @param _amount       The Amount of Charge to be transferred - must be <= particle charge
     */
//    function transferCharge(address _from, uint256 _fromTokenId, uint256 _toTokenId, uint256 _amount) public {
//        require((msg.sender == _from) || isApprovedForAll(_from, msg.sender), "E305");
//
//        _transferCharge(_from, _fromTokenId, _toTokenId, _amount);
//    }

    /***********************************|
    |        Type Creator Fees          |
    |__________________________________*/

    /**
     * @dev Allows contract owner to withdraw any fees earned
     */
//    function withdrawCreatorFees(uint256 _type) public {
//
//    }

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
        escrow = IChargedParticlesEscrow(_escrowAddress);
    }

    function registerAssetPair(bytes16 _assetPairId) public onlyOwner {
        require(escrow.isAssetPairEnabled(_assetPairId), "Asset-Pair not enabled in Escrow");

        // Allow Escrow to Transfer Assets from this Contract
        address _assetTokenAddress = escrow.getAssetTokenAddress(_assetPairId);
        IERC20(_assetTokenAddress).approve(address(escrow), uint(-1));
        assetPairEnabled[_assetPairId] = true;
    }

    function disableAssetPair(bytes16 _assetPairId) public onlyOwner {
        assetPairEnabled[_assetPairId] = false;
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
            0,              // Min Asset Amount
            0,              // Max Asset Amount
            _amount,        // Max Supply
            0               // Creator Deposit Fee
        );

        // Mint ION Tokens to Contract Owner
        _mint(contractOwner, ionTokenId, _amount, "");

        // Remove owner of ION token to prevent further minting
        typeCreator[ionTokenId] = address(0x0);

        return ionTokenId;
    }

    /**
     * @dev Allows contract owner to withdraw any fees earned
     */
    function withdrawFees() public onlyOwner {
//        uint256 _balance = address(this).balance;
//        if (_balance > 0) {
//            msg.sender.transfer(_balance);
//        }
//        if (collectedMintFees > 0) {
//            _payoutFundedDai(msg.sender, collectedMintFees);
//            collectedMintFees = 0;
//        }
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
     * @param _assetMin         The Min amount of Asset Tokens (in WEI) that a Particle is allowed to hold (the Particle Mass)
     * @param _assetMax         The Max amount of Asset Tokens (in WEI) that a Particle is allowed to hold (the Particle Mass)
     *                          Min must be greater than 1000000 (in WEI)
     *                          Max of 0 = no maximum
     *                          Min == Max = Fixed, Required # of Asset Tokens to mint
     *                          NOTE: This will be ignored for Fungible Tokens (ERC20), [0,0]
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
        bytes16 _assetPairId,
        uint256 _assetMin,
        uint256 _assetMax,
        uint256 _maxSupply,
        uint16 _creatorFee
    ) internal returns (uint256 _particleTypeId) {

        require(_creatorFee <= MAX_CUSTOM_DEPOSIT_FEE, "E413");
        if (_isNF) {
            require(assetPairEnabled[_assetPairId], "E414");
            require(_assetMin >= MIN_DEPOSIT_FEE, "E406");
        }

        // Create Type
        _particleTypeId = _createType(_uri, _isNF);

        // Type Access (Public or Private minting)
        registeredTypes[_particleTypeId] = _isPrivate ? 2 : 1;

        // Creator of Type
        typeCreator[_particleTypeId] = _creator;

        // Type Asset-Pair
        typeCreatorAssetPairId[_particleTypeId] = _assetPairId;

        // Max Supply of Token; 0 = No Max
        typeCreatorSupply[_particleTypeId] = _maxSupply;

        // Min/Max Funding for NFTs
        typeCreatorAssetDepositMin[_particleTypeId] = _isNF ? _assetMin : 0;
        typeCreatorAssetDepositMax[_particleTypeId] = _isNF ? _assetMax : 0;

        // The Deposit Fee for Creators
        typeCreatorDepositFee[_particleTypeId] = _creatorFee;
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
     * @dev Collects the Required DAI from the users wallet during Minting
     * @param _from         The owner address to collect the DAI from
     * @param _requiredDai  The amount of DAI to collect from the user
     */
//    function _collectRequiredDai(address _from, uint256 _requiredDai) internal {
//        // Transfer DAI from User to Contract
//        uint256 _userDaiBalance = dai.balanceOf(_from);
//        require(_requiredDai <= _userDaiBalance, "E405");
//        require(dai.transferFrom(_from, address(this), _requiredDai), "E408");
//    }

    /**
     * @dev Pays out a specified amount of CHAI
     * @param _to           The owner address to pay out to
     * @param _totalChai    The total amount of CHAI to pay out
     */
//    function _payoutFundedDai(address _to, uint256 _totalChai) internal {
//        address _self = address(this);
//
//        // Exit Chai and collect Dai + Interest
//        chai.exit(_self, _totalChai);
//
//        // Transfer Dai + Interest
//        uint256 _receivedDai = dai.balanceOf(_self);
//        require(dai.transferFrom(_self, _to, _receivedDai), "E408");
//    }

    /**
     * @dev Pays out a specified amount of DAI
     * @param _to           The owner address to pay out to
     * @param _totalDai     The total amount of DAI to pay out
     */
//    function _payoutCharge(address _to, uint256 _totalDai) internal returns (uint256) {
//        address _self = address(this);
//
//        // Collect Interest
//        //  contract receives DAI,
//        //  function call returns amount of CHAI exchanged
//        uint256 _chai = 0; // chai.draw(_self, _totalDai);
//
//        // Transfer Interest
////        uint256 _receivedDai = dai.balanceOf(_self);
////        require(dai.transferFrom(_self, _to, _receivedDai), "E408");
//        return _chai;
//    }

    /**
     * @dev Transfers a tokens charge from one particle to another
     * @param _from         The owner address to transfer the Charge from
     * @param _fromTokenId  The Token ID to transfer the Charge from
     * @param _toTokenId    The Token ID to transfer the Charge to
     * @param _amount       The Amount of Charge to be transferred - must be <= particle charge
     */
//    function _transferCharge(address _from, uint256 _fromTokenId, uint256 _toTokenId, uint256 _amount) internal {
//        uint256 currentCharge = currentParticleCharge(_fromTokenId); // In Funding Token
//        require(currentCharge > 0, "E403");
//        require(currentCharge >= _amount, "E409");
//
//        // Verify Tokens are NFTs
//        require(_fromTokenId & TYPE_NF_BIT == TYPE_NF_BIT, "E410");
//        require(_toTokenId & TYPE_NF_BIT == TYPE_NF_BIT, "E410");
//
//        // Move Chai (already held in contract, just need to swap balances)
//        uint256 _chaiAmount = chai.chai(_amount);
//        interestTokenBalance[_fromTokenId] = interestTokenBalance[_fromTokenId].sub(_chaiAmount);
//        interestTokenBalance[_toTokenId] = interestTokenBalance[_toTokenId].add(_chaiAmount);
//
//        // Emit event
//        emit TransferCharge(_from, _fromTokenId, _toTokenId, _amount);
//    }

}

// ChargedParticles -- Interest-bearing NFTs based on the DAI Savings Token
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

pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../../node_modules/openzeppelin-solidity/contracts/utils/Address.sol";
import "../../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../../node_modules/openzeppelin-solidity/contracts/introspection/IERC165.sol";
import "../../node_modules/openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "../../node_modules/multi-token-standard/contracts/interfaces/IERC1155.sol";
import "../../node_modules/multi-token-standard/contracts/interfaces/IERC1155TokenReceiver.sol";
import "../assets/chai/IChai.sol";

/**
 * @dev Implementation of ERC1155 Multi-Token Standard contract
 * @dev see node_modules/multi-token-standard/contracts/tokens/ERC1155/ERC1155.sol
 * @dev NOTE Added Mixed Token Types: Fungible & Non-Fungible according to spec
 */
contract ERC1155 is IERC165 {
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

    function balanceOf(address _owner, uint256 _tokenId) public view returns (uint256) {
        if ((_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) && (_tokenId & NF_INDEX_MASK != 0)) {  // Non-Fungible Item
            return nfOwners[_tokenId] == _owner ? 1 : 0;
        }
        return balances[_owner][_tokenId];
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

    function isApprovedForAll(address _owner, address _operator) public view returns (bool isOperator) {
        return operators[_owner][_operator];
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
            balances[_to][_type] = balances[_to][_type].add(_amount);
            maxIndex[_type] = maxIndex[_type].add(_amount);
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
                balances[_to][_type] = balances[_to][_type].add(_amount);
                maxIndex[_type] = maxIndex[_type].add(_amount);
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
            balances[_from][_tokenId] = balances[_from][_tokenId].sub(_amount);
            maxIndex[_tokenId] = maxIndex[_tokenId].sub(_amount);
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
                balances[_from][_tokenId] = balances[_from][_tokenId].sub(_amount);
                maxIndex[_tokenId] = maxIndex[_tokenId].sub(_amount);
            }
        }

        emit TransferBatch(msg.sender, _from, address(0x0), _tokenIds, _amounts);
    }

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

    //
    //  Helper functions; here for reference but adds unnecessary GAS.
    //    Prefer testing token types directly.
    //

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
 *  -- ERC-1155 Edition
 */
contract ChargedParticlesCHAI is ERC1155 {
    using SafeMath for uint256;

    /***********************************|
    |        Variables and Events       |
    |__________________________________*/

    IERC20 internal dai;
    IChai internal chai;

    // Particles come in many "Types" created by Public Users.
    //   Each "Type" of Particle has a "Creator", who can set certain parameters
    //   for the Particle upon Creation.
    //   Particles can be Fungible (ERC20) where all tokens are the same in value.
    //     - These particles CAN NOT hold a charge, and do not require an underlying asset when minting.
    //   Particles can also be Non-Fungible (ERC721) where all tokens are unique in value.
    //     - These particles CAN hold a charge, and require a deposit of the underlying asset when minting.
    //   Particle Creators can also set restrictions on who can "mint" their particles, the max supply and
    //     how much of the underlying asset is required to mint a particle (1 DAI maybe?).
    //     NOTE: Currently, all particles of the same "Type" are required to have the same amount of
    //     underlying asset.  This could be changed with a bit of work though.
    //   These values are all optional, and can be left at 0 (zero) to specify no-limits.

    //       TypeID => Type Creator
    mapping (uint256 => address) internal registeredTypeCreators;

    //       TypeID => Required DAI
    mapping (uint256 => uint256) internal requiredFundingByType;   // Amount of Dai to deposit when minting

    //      TokenID => Max Supply
    mapping (uint256 => uint256) internal maxSupplyByType;

    //       TypeID => Access Type (1=Public / 2=Private)
    mapping (uint256 => uint8) internal registeredTypes;

    // This value is used to track the amount of CHAI each token holds.
    //   CHAI is always redeemable for more and more DAI over time, thus the interest.
    //
    //      TokenID => Balance
    mapping (uint256 => uint256) internal chaiBalanceByTokenId;    // Amount of Chai minted from Dai deposited

    // To Create "Types" (Fungible or Non-Fungible) there is a Fee.
    //  The Fee can be paid in ETH or in IONs.
    //  IONs are a custom ERC20 token minted within this contract.
    //  ETH paid upon minting is stored in contract, withdrawn by contract owner.
    //  IONs paid upon minting are burned.
    //  These values are completely optional and can be set to 0 to specify No Fee.
    uint256 internal createFeeEth;
    uint256 internal createFeeIon;

    // To Mint Tokens of any "Type", there is a Minting Fee, which is
    //  a small percentage of the Funding Asset of the token (in this case, DAI) upon Minting.
    //  A value of "50" here would represent a Fee of 0.5% of the Funding Asset ((50 / 10000) * 100)
    //    This allows a fee as low as 0.01%  (value of "1")
    //  This means that a newly minted particle would have 99.5% of its "Mass" and 0% of its "Charge".
    //    As the "Charge" increases over time, the particle will fill up the "Mass" to 100% and then
    //    the "Charge" will start building up.  Essentially, only a small portion of the interest
    //    is used to pay the minting fee.  The particle will be in "cool-down" mode until the "Mass"
    //    of the particle returns to 100% (this should be a relatively short period of time).
    //    When the particle reaches 100% "Mass" is can be "Melted" (or burned) to reclaim the underlying
    //    asset (in this case DAI).  Since the "Mass" will be back to 100%, "Melting" will yield at least 100%
    //    of the underlying asset back to the owner (plus any interest accrued, the "charge").
    //  This value is completely optional and can be set to 0 to specify No Fee.
    uint256 internal mintFee;

    // The amount of Fees collected from minting (collected in CHAI, paid out in DAI)
    uint256 internal collectedMintFees;

    // Internal ERC20 Token used for Creating "Types" of Particles;
    //   needs to be created as a private ERC20 type within this contract
    uint256 internal ionTokenId;

    // Contract Owner
    //  This value should be assigned to a Multisig Wallet or a DAO
    address private owner;

    bytes16 public version = "v0.1.3";

    event TransferCharge(address indexed _ownerOrOperator, uint256 indexed _fromTokenId, uint256 indexed _toTokenId, uint256 _amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /***********************************|
    |             Modifiers             |
    |__________________________________*/

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "E102");
        _;
    }

    /***********************************|
    |          Initialization           |
    |__________________________________*/

    constructor() public {
        // Constructor args suck!  see "setup()" function below
        //   createFeeEth = 35 szabo;     //  ERC20  = 0.000035 ETH  (~ USD $0.005)
        //                                //  ERC721 = 0.000070 ETH  (~ USD $0.01)
        //   createFeeIon = 10 ether;     //  ERC20  = 1 ION
        //                                //  ERC721 = 2 IONs
        //   mintFee = 50;                //  0.5% of Chai from deposited Dai

        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);
    }

    /***********************************|
    |            Public Read            |
    |__________________________________*/

    /**
     * @notice Gets the address of the contract owner.
     * @return The owner address
     */
    function getContractOwner() public view returns (address) {
        return owner;
    }

    /**
     * @notice Gets the Creator of a Token Type
     * @param _type     The Type ID of the Token
     * @return  The Creator Address
     */
    function getCreator(uint256 _type) public view returns (address) {
        return registeredTypeCreators[_type];
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
            if (maxSupplyByType[_type] > 0) {
                return maxIndex[_type] <= maxSupplyByType[_type].add(_amount);
            }
            // No Max
            return true;
        }
        // Private
        if (registeredTypeCreators[_type] != msg.sender) {
            return false;
        }
        // Has Max
        if (maxSupplyByType[_type] > 0) {
            return maxIndex[_type] <= maxSupplyByType[_type].add(_amount);
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
     * @param _tokenId      The ID of the Token
     * @return  The Amount of DAI held in the Token
     */
    function baseParticleMass(uint256 _tokenId) public view returns (uint256) {
        uint256 _type = _tokenId & TYPE_MASK;
        return requiredFundingByType[_type];
    }

    /**
     * @notice Gets the amount of interest the Token has generated (it's accumulated particle-charge)
     * @param _tokenId      The ID of the Token
     * @return  The amount of interest the Token has generated (in Funding Token; DAI)
     */
    function currentParticleCharge(uint256 _tokenId) public returns (uint256) {
        uint256 _type = _tokenId & TYPE_MASK;
        require(registeredTypes[_type] > 0, "E402");
        require(requiredFundingByType[_type] > 0, "E402");

        uint256 currentCharge = chai.dai(chaiBalanceByTokenId[_tokenId]);
        uint256 originalCharge = requiredFundingByType[_type];
        if (originalCharge >= currentCharge) { return 0; }
        return currentCharge.sub(originalCharge);
    }

    /**
     * @notice Allows the owner of the Token to collect the interest generated form the token
     *  without removing the underlying DAI that is held in the token
     * @param _tokenId      The ID of the Token
     * @return  The amount of interest released from the token (in Funding Token; DAI)
     */
    // collect current interest from particle
    function dischargeParticle(uint256 _tokenId) public returns (uint256) {
        address _owner = ownerOf(_tokenId);
        require((_owner == msg.sender) || isApprovedForAll(_owner, msg.sender), "E103");

        uint256 _currentChargeInDai = currentParticleCharge(_tokenId);
        require(_currentChargeInDai > 0, "E403");

        uint256 _paidChai = _payoutChargedDai(msg.sender, _currentChargeInDai);
        chaiBalanceByTokenId[_tokenId] = chaiBalanceByTokenId[_tokenId].sub(_paidChai);

        return _currentChargeInDai;
    }

    /***********************************|
    |   Public Create Particle Types    |
    |__________________________________*/

    /**
     * @notice Creates a new Particle Type which can later be minted/burned
     * @param _uri              A unique URI for the Token Type which will serve the JSON metadata
     * @param _isNF             True if the Type is a Non-Fungible (only Non-Fungible Tokens can hold DAI and generate interest)
     * @param _isPrivate        True if the Type is Private and can only be minted by the creator; otherwise anyone can mint
     * @param _requiredDai      The amount of DAI (in WEI) that is required to Mint a Token of this Type (the Particle Mass)
     *                          NOTE: This will be ignored for Fungible Tokens (ERC20)
     * @param _maxSupply        The Max Supply of Tokens that can be minted
     * @return The ID of the newly created Particle Type
     */
    function createParticleWithEther(string memory _uri, bool _isNF, bool _isPrivate, uint256 _requiredDai, uint256 _maxSupply) public payable returns (uint256 _particleTypeId) {
        (uint256 ethPrice, ) = getCreationPrice(_isNF);
        require(msg.value >= ethPrice, "E404");

        // Create Particle Type
        _particleTypeId = _createParticle(msg.sender, _uri, _isNF, _isPrivate, _requiredDai, _maxSupply);

        // Refund over-payment
        uint256 overage = msg.value.sub(ethPrice);
        if (overage > 0) {
            msg.sender.transfer(overage);
        }
    }

    /**
     * @notice Creates a new Particle Type which can later be minted/burned
     * @param _uri              A unique URI for the Token Type which will serve the JSON metadata
     * @param _isNF             True if the Type is a Non-Fungible (only Non-Fungible Tokens can hold DAI and generate interest)
     * @param _isPrivate        True if the Type is Private and can only be minted by the creator; otherwise anyone can mint
     * @param _requiredDai      The amount of DAI (in WEI) that is required to Mint a Token of this Type (the Particle Mass)
     *                          NOTE: This will be ignored for Fungible Tokens (ERC20)
     * @return The ID of the newly created Particle Type
     *
     * NOTE: Must approve THIS contract to TRANSFER your IONS on your behalf
     */
    function createParticleWithIons(string memory _uri, bool _isNF, bool _isPrivate, uint256 _requiredDai, uint256 _maxSupply) public returns (uint256 _particleTypeId) {
        ( , uint256 ionPrice) = getCreationPrice(_isNF);

        // Collect Ions as Payment
        _collectIons(msg.sender, ionPrice);

        // Create Particle Type
        _particleTypeId = _createParticle(msg.sender, _uri, _isNF, _isPrivate, _requiredDai, _maxSupply);
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
    function mintParticle(address _to, uint256 _type, uint256 _amount, bytes memory _data) public returns (uint256) {
        require(canMint(_type, _amount), "E407");
        address _self = address(this);

        // Mint Token
        uint256 _tokenId = _mint(_to, _type, _amount, _data);

        if (_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) {
            // Transfer DAI from User to Contract
            uint256 _requiredDai = requiredFundingByType[_type];
            _collectRequiredDai(msg.sender, _requiredDai);

            // Tokenize Interest
            uint256 _preBalance = chai.balanceOf(_self);
            chai.join(_self, _requiredDai);
            uint256 _postBalance = chai.balanceOf(_self);

            // Track Chai in each Token
            chaiBalanceByTokenId[_tokenId] = _totalChaiForToken(_postBalance.sub(_preBalance));
        }

        return _tokenId;
    }

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
    function mintParticles(address _to, uint256[] memory _types, uint256[] memory _amounts, bytes memory _data) public returns (uint256[] memory) {
        address _self = address(this);
        uint256 i;
        uint256 _type;
        uint256 _amount;
        uint256 _tokenId;
        uint256 _totalDai;
        uint256 _requiredDai;
        uint256 _count = _types.length;

        for (i = 0; i < _count; ++i) {
            _type = _types[i];
            _amount = _amounts[i];
            require(canMint(_type, _amount), "E407");
            _requiredDai = requiredFundingByType[_type];
            _totalDai = _requiredDai.add(_totalDai);
        }

        // Mint Tokens
        uint256[] memory _tokenIds = _mintBatch(_to, _types, _amounts, _data);

        if (_totalDai > 0) {
            // Transfer DAI from User to Contract
            _collectRequiredDai(msg.sender, _totalDai);

            uint256 _balance = chai.balanceOf(_self);
            for (i = 0; i < _count; ++i) {
                _tokenId = _tokenIds[i];
                _type = _tokenId & TYPE_MASK;
                _requiredDai = requiredFundingByType[_type];

                if (_requiredDai > 0) {
                    // Tokenize Interest
                    chai.join(_self, _requiredDai);

                    // Track Chai in each Token
                    chaiBalanceByTokenId[_tokenId] = _totalChaiForToken(chai.balanceOf(_self).sub(_balance));
                    _balance = chai.balanceOf(_self);
                }
            }
        }
        return _tokenIds;
    }

    /***********************************|
    |    Public Burn (ERC20 & ERC721)   |
    |__________________________________*/

    /**
     * @notice Destroys a Particle and releases the underlying DAI + Interest (Mass + Charge)
     * @param _tokenId  The ID of the token to burn
     * @param _amount   The amount of tokens to burn (always 1 for Non-Fungibles)
     */
    function burnParticle(uint256 _tokenId, uint256 _amount) public {
        // Verify Token
        uint256 _type = _tokenId & TYPE_MASK;
        require(registeredTypes[_type] > 0, "E402");

        // Burn Token
        _burn(msg.sender, _tokenId, _amount);

        // Payout Dai + Interest
        if (_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) {
            uint256 _tokenChai = chaiBalanceByTokenId[_tokenId];
            chaiBalanceByTokenId[_tokenId] = 0;
            _payoutFundedDai(msg.sender, _tokenChai);
        }
    }

    /**
     * @notice Destroys multiple Particles and releases the underlying DAI + Interest (Mass + Charge)
     * @param _tokenIds     The IDs of the tokens to burn
     * @param _amounts      The amounts of the tokens to burn (always 1 for Non-Fungibles)
     */
    function burnParticles(uint256[] memory _tokenIds, uint256[] memory _amounts) public {
        // Verify Token
        uint256 _tokenId;
        uint256 _totalChai;
        uint256 _count = _tokenIds.length;
        for (uint256 i = 0; i < _count; ++i) {
            _tokenId = _tokenIds[i];
            require(registeredTypes[_tokenId & TYPE_MASK] > 0, "E402");

            if (_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) {
                _totalChai = chaiBalanceByTokenId[_tokenId].add(_totalChai);
                chaiBalanceByTokenId[_tokenId] = 0;
            }
        }

        // Burn Tokens
        _burnBatch(msg.sender, _tokenIds, _amounts);

        // Payout Dai + Interest
        if (_totalChai > 0) {
            _payoutFundedDai(msg.sender, _totalChai);
        }
    }

    /***********************************|
    |         Transfer Charge           |
    |__________________________________*/

    /**
     * @notice Transfers a tokens full-charge from one particle to another
     * @param _from         The owner address to transfer the Charge from
     * @param _fromTokenId  The Token ID to transfer the Charge from
     * @param _toTokenId    The Token ID to transfer the Charge to
     */
    function transferCharge(address _from, uint256 _fromTokenId, uint256 _toTokenId) public {
        require((msg.sender == _from) || isApprovedForAll(_from, msg.sender), "E305");

        // Transfer Full Amount of Charge
        uint256 currentCharge = currentParticleCharge(_fromTokenId); // In Funding Token
        _transferCharge(_from, _fromTokenId, _toTokenId, currentCharge);
    }

    /**
     * @notice Transfers some of a tokens charge from one particle to another
     * @param _from         The owner address to transfer the Charge from
     * @param _fromTokenId  The Token ID to transfer the Charge from
     * @param _toTokenId    The Token ID to transfer the Charge to
     * @param _amount       The Amount of Charge to be transferred - must be <= particle charge
     */
    function transferCharge(address _from, uint256 _fromTokenId, uint256 _toTokenId, uint256 _amount) public {
        require((msg.sender == _from) || isApprovedForAll(_from, msg.sender), "E305");

        _transferCharge(_from, _fromTokenId, _toTokenId, _amount);
    }

    /***********************************|
    |            Only Owner             |
    |__________________________________*/

    /**
     * @dev Setup the DAI/CHAI contracts and configure the contract
     */
    function setup(address _daiAddress, address _chaiAddress, uint256 _createFeeEth, uint256 _createFeeIon, uint256 _mintFee) public onlyOwner {
        // Set DAI as Funding Token
        dai = IERC20(_daiAddress);
        chai = IChai(_chaiAddress);

        // Setup Chai to Tokenize DAI Interest
        dai.approve(_chaiAddress, uint(-1));

        createFeeEth = _createFeeEth;
        createFeeIon = _createFeeIon;
        mintFee = _mintFee;
    }

    /**
     * @dev Setup internal ION Token
     */
    function mintIons(string memory _uri, uint256 _amount) public onlyOwner returns (uint256) {
        // Create ION Token Type;
        //  ERC20, Private, Limited
        ionTokenId = _createParticle(owner, _uri, false, true, 0, _amount);

        // Mint ION Tokens to Owner
        _mint(owner, ionTokenId, _amount, "");

        // Remove owner of ION token to prevent further minting
        registeredTypeCreators[ionTokenId] = address(0x0);

        return ionTokenId;
    }

    /**
     * @dev Allows contract owner to withdraw any fees earned
     */
    function withdrawFees() public onlyOwner {
        uint256 _balance = address(this).balance;
        if (_balance > 0) {
            msg.sender.transfer(_balance);
        }
        if (collectedMintFees > 0) {
            _payoutFundedDai(msg.sender, collectedMintFees);
            collectedMintFees = 0;
        }
    }

    /**
     * @notice Transfers the ownership of the contract to new address
     * @param _newOwner Address of the new owner
     */
    function transferOwnership(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), "E101");
        emit OwnershipTransferred(owner, _newOwner);
        owner = _newOwner;
    }

    /***********************************|
    |         Private Functions         |
    |__________________________________*/

    /**
     * @notice Creates a new Particle Type which can later be minted/burned
     * @param _uri              A unique URI for the Token Type which will serve the JSON metadata
     * @param _isNF             True if the Type is a Non-Fungible (only Non-Fungible Tokens can hold DAI and generate interest)
     * @param _isPrivate        True if the Type is Private and can only be minted by the creator; otherwise anyone can mint
     * @param _requiredDai      The amount of DAI (in WEI) that is required to Mint a Token of this Type (the Particle Mass)
     *                          NOTE: This will be ignored for Fungible Tokens (ERC20)
     * @return The ID of the newly created Particle Type
     */
    function _createParticle(address _creator, string memory _uri, bool _isNF, bool _isPrivate, uint256 _requiredDai, uint256 _maxSupply) internal returns (uint256 _particleTypeId) {
        require(!_isNF || (_isNF && _requiredDai >= 1e6), "E406"); // 0.000000000001 DAI  or  1000000 WEI

        // Create Type
        _particleTypeId = _createType(_uri, _isNF);

        // Type Access (Public or Private minting)
        registeredTypes[_particleTypeId] = _isPrivate ? 2 : 1;

        // Creator of Type
        registeredTypeCreators[_particleTypeId] = _creator;

        // Max Supply of Token; 0 = No Max
        maxSupplyByType[_particleTypeId] = _maxSupply;

        // Required Funding for NFTs
        requiredFundingByType[_particleTypeId] = _isNF ? _requiredDai : 0;
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
    function _collectRequiredDai(address _from, uint256 _requiredDai) internal {
        // Transfer DAI from User to Contract
        uint256 _userDaiBalance = dai.balanceOf(_from);
        require(_requiredDai <= _userDaiBalance, "E405");
        require(dai.transferFrom(_from, address(this), _requiredDai), "E408");
    }

    /**
     * @dev Pays out a specified amount of CHAI
     * @param _to           The owner address to pay out to
     * @param _totalChai    The total amount of CHAI to pay out
     */
    function _payoutFundedDai(address _to, uint256 _totalChai) internal {
        address _self = address(this);

        // Exit Chai and collect Dai + Interest
        chai.exit(_self, _totalChai);

        // Transfer Dai + Interest
        uint256 _receivedDai = dai.balanceOf(_self);
        require(dai.transferFrom(_self, _to, _receivedDai), "E408");
    }

    /**
     * @dev Pays out a specified amount of DAI
     * @param _to           The owner address to pay out to
     * @param _totalDai     The total amount of DAI to pay out
     */
    function _payoutChargedDai(address _to, uint256 _totalDai) internal returns (uint256) {
        address _self = address(this);

        // Collect Interest
        //  contract receives DAI,
        //  function call returns amount of CHAI exchanged
        uint256 _chai = chai.draw(_self, _totalDai);

        // Transfer Interest
        uint256 _receivedDai = dai.balanceOf(_self);
        require(dai.transferFrom(_self, _to, _receivedDai), "E408");
        return _chai;
    }

    /**
     * @dev Transfers a tokens charge from one particle to another
     * @param _from         The owner address to transfer the Charge from
     * @param _fromTokenId  The Token ID to transfer the Charge from
     * @param _toTokenId    The Token ID to transfer the Charge to
     * @param _amount       The Amount of Charge to be transferred - must be <= particle charge
     */
    function _transferCharge(address _from, uint256 _fromTokenId, uint256 _toTokenId, uint256 _amount) internal {
        uint256 currentCharge = currentParticleCharge(_fromTokenId); // In Funding Token
        require(currentCharge > 0, "E403");
        require(currentCharge >= _amount, "E409");

        // Verify Tokens are NFTs
        require(_fromTokenId & TYPE_NF_BIT == TYPE_NF_BIT, "E410");
        require(_toTokenId & TYPE_NF_BIT == TYPE_NF_BIT, "E410");

        // Move Chai (already held in contract, just need to swap balances)
        uint256 _chaiAmount = chai.chai(_amount);
        chaiBalanceByTokenId[_fromTokenId] = chaiBalanceByTokenId[_fromTokenId].sub(_chaiAmount);
        chaiBalanceByTokenId[_toTokenId] = chaiBalanceByTokenId[_toTokenId].add(_chaiAmount);

        // Emit event
        emit TransferCharge(_from, _fromTokenId, _toTokenId, _amount);
    }

    /**
     * @dev Calculates the amount of DAI held within a token during minting
     *      Note: Accounts for any contract fees
     * @param _tokenChai    The total amount of DAI used to fund the token
     * @return  The actual amount of DAI to fund the token - fees
     */
    function _totalChaiForToken(uint256 _tokenChai) internal returns (uint256) {
        if (mintFee == 0) { return _tokenChai; }
        uint256 _mintFee = _tokenChai.mul(mintFee).div(1e4);
        collectedMintFees = collectedMintFees.add(_mintFee);
        return _tokenChai.sub(_mintFee);
    }
}

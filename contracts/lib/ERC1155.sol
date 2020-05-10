// ERC1155.sol - Charged Particles
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
//  100:        ERC1155
//      101         Invalid Recipient
//      102         Invalid on-received message
//      103         Invalid arrays length
//      104         Invalid type
//      105         Invalid owner/operator
//      106         Insufficient balance
//      107         Invalid URI for Type
//      108         Owner index out of bounds
//      109         Global index out of bounds
//      110         Approval to current owner
//      111         Approve caller is not owner nor approved for all
//      112         Approved query for nonexistent token

pragma solidity 0.5.16;

import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/introspection/IERC165.sol";
import "multi-token-standard/contracts/interfaces/IERC1155TokenReceiver.sol";


/**
 * @notice Implementation of ERC1155 Multi-Token Standard contract
 * @dev see node_modules/multi-token-standard/contracts/tokens/ERC1155/ERC1155.sol
 */
contract ERC1155 is Initializable, IERC165 {
    using Address for address;
    using SafeMath for uint256;

    /***********************************|
    |     Variables/Events/Modifiers    |
    |__________________________________*/

    // Fungibility-Type Flags
    uint256 constant internal TYPE_MASK = uint256(uint128(~0)) << 128;
    uint256 constant internal NF_INDEX_MASK = uint128(~0);
    uint256 constant internal TYPE_NF_BIT = 1 << 255;

    // Interface Signatures
    bytes4 constant internal INTERFACE_SIGNATURE_ERC165 = 0x01ffc9a7;
    bytes4 constant internal INTERFACE_SIGNATURE_ERC1155 = 0xd9b67a26;
    bytes4 constant internal ERC1155_RECEIVED_VALUE = 0xf23a6e61;
    bytes4 constant internal ERC1155_BATCH_RECEIVED_VALUE = 0xbc197c81;

    // Type Nonce for each Unique Type
    uint256 internal nonce;

    //
    // Generic (ERC20 & ERC721)
    // 
    //       Account =>         Operator => Allowed?
    mapping (address => mapping (address => bool)) internal operators;   // Operator Approval for All Tokens by Type
    //        TypeID => Total Minted Supply
    mapping (uint256 => uint256) internal mintedByType;

    //
    // ERC20 Specific
    //
    //       Account =>           TypeID => ERC20 Balance
    mapping (address => mapping (uint256 => uint256)) internal balances;
    //        TypeID => Total Circulating Supply (reduced on burn)
    mapping (uint256 => uint256) internal supplyByType;

    //
    // ERC721 Specific
    //
    //       TokenID => Operator
    mapping (uint256 => address) internal tokenApprovals;   // Operator Approval per Token
    //       TokenID => Owner
    mapping (uint256 => address) internal nfOwners;
    //       TokenID => URI for the Token Metadata
    mapping (uint256 => string) internal tokenUri;
    //
    // Enumerable NFTs
    mapping (uint256 => mapping (uint256 => uint256)) internal ownedTokensByTypeIndex;
    mapping (uint256 => mapping (uint256 => uint256)) internal allTokensByTypeIndex;
    mapping (uint256 => mapping (address => uint256[])) internal ownedTokensByType;
    mapping (uint256 => uint256[]) internal allTokensByType; // Circulating Supply

    //
    // Events
    //

    event TransferSingle(
        address indexed _operator,
        address indexed _from,
        address indexed _to,
        uint256 _id,
        uint256 _amount
    );

    event TransferBatch(
        address indexed _operator,
        address indexed _from,
        address indexed _to,
        uint256[] _ids,
        uint256[] _amounts
    );

    event Approval(
        address indexed _owner,
        address indexed _operator,
        uint256 indexed _tokenId
    );

    event ApprovalForAll(
        address indexed _owner,
        address indexed _operator,
        bool _approved
    );

    event URI(
        uint256 indexed _id, // ID = Type or Token ID
        string _uri
    );

    /***********************************|
    |          Initialization           |
    |__________________________________*/

    function initialize() public initializer {
    }

    /***********************************|
    |            Public Read            |
    |__________________________________*/

    /**
     * @notice Gets the URI of the Token Metadata
     * @param _id  The Type ID of the Token to get the URI for
     * @return  The URI of the Token Metadata
     */
    function uri(uint256 _id) public view returns (string memory) {
        return tokenUri[_id];
    }

    /**
     * @notice Checks if a specific token interface is supported
     * @param _interfaceID  The ID of the Interface to check
     * @return  True if the interface ID is supported
     */
    function supportsInterface(bytes4 _interfaceID) external view returns (bool) {
        if (_interfaceID == INTERFACE_SIGNATURE_ERC165 ||
        _interfaceID == INTERFACE_SIGNATURE_ERC1155) {
            return true;
        }
        return false;
    }

    /**
     * @notice Gets the Total Circulating Supply of a Token-Type
     * @param _typeId  The Type ID of the Token
     * @return  The Total Circulating Supply of the Token-Type
     */
    function totalSupply(uint256 _typeId) public view returns (uint256) {
        if (_typeId & TYPE_NF_BIT == TYPE_NF_BIT) {
            return allTokensByType[_typeId].length;
        }
        return supplyByType[_typeId];
    }

    /**
     * @notice Gets the Total Minted Supply of a Token-Type
     * @param _typeId  The Type ID of the Token
     * @return  The Total Minted Supply of the Token-Type
     */
    function totalMinted(uint256 _typeId) public view returns (uint256) {
        return mintedByType[_typeId];
    }

    /**
     * @notice Gets the Owner of a Non-fungible Token (ERC-721 only)
     * @param _tokenId  The ID of the Token
     * @return  The Address of the Owner of the Token
     */
    function ownerOf(uint256 _tokenId) public view returns (address) {
        require(_tokenId & TYPE_NF_BIT == TYPE_NF_BIT, "E104");
        return nfOwners[_tokenId];
    }

    /**
     * @notice Get the balance of an account's Tokens
     * @param _tokenOwner  The address of the token holder
     * @param _typeId      The Type ID of the Token
     * @return The Owner's Balance of the Token-Type
     */
    function balanceOf(address _tokenOwner, uint256 _typeId) public view returns (uint256) {
        // Non-fungible
        if (_typeId & TYPE_NF_BIT == TYPE_NF_BIT) {
            _typeId = _typeId & TYPE_MASK;
            return ownedTokensByType[_typeId][_tokenOwner].length;
        }
        // Fungible
        return balances[_tokenOwner][_typeId];
    }

    /**
     * @notice Get the balance of multiple account/token pairs
     * @param _owners   The addresses of the token holders
     * @param _typeIds  The Type IDs of the Tokens
     * @return The Owner's Balance of the Token-Types
     */
    function balanceOfBatch(address[] memory _owners, uint256[] memory _typeIds) public view returns (uint256[] memory) {
        require(_owners.length == _typeIds.length, "E103");

        uint256[] memory _balances = new uint256[](_owners.length);
        for (uint256 i = 0; i < _owners.length; ++i) {
            uint256 id = _typeIds[i];
            address owner = _owners[i];

            // Non-fungible
            if (id & TYPE_NF_BIT == TYPE_NF_BIT) {
                id = id & TYPE_MASK;
                _balances[i] = ownedTokensByType[id][owner].length;
            }
            // Fungible
            else {
                _balances[i] = balances[owner][id];
            }
        }

        return _balances;
    }

    /**
     * @notice Gets a specific Token by Index of a Users Enumerable Non-fungible Tokens (ERC-721 only)
     * @param _typeId  The Type ID of the Token 
     * @param _owner   The address of the Token Holder
     * @param _index   The Index of the Token 
     * @return  The ID of the Token by Owner, Type & Index
     */
    function tokenOfOwnerByIndex(uint256 _typeId, address _owner, uint256 _index) public view returns (uint256) {
        require(_index < balanceOf(_owner, _typeId), "E108");
        return ownedTokensByType[_typeId][_owner][_index];
    }

    /**
     * @notice Gets a specific Token by Index in All Enumerable Non-fungible Tokens (ERC-721 only)
     * @param _typeId  The Type ID of the Token 
     * @param _index   The Index of the Token 
     * @return  The ID of the Token by Type & Index
     */
    function tokenByIndex(uint256 _typeId, uint256 _index) public view returns (uint256) {
        require(_index < totalSupply(_typeId), "E109");
        return allTokensByType[_typeId][_index];
    }

    /**
     * @notice Sets an Operator as Approved to Manage a specific Token
     * @param _operator  Address to add to the set of authorized operators
     * @param _tokenId  The ID of the Token
     */
    function approve(address _operator, uint256 _tokenId) public {
        address _owner = ownerOf(_tokenId);
        require(_operator != _owner, "E110");
        require(msg.sender == _owner || isApprovedForAll(_owner, msg.sender), "E111");

        tokenApprovals[_tokenId] = _operator;
        emit Approval(_owner, _operator, _tokenId);
    }

    /**
     * @notice Gets the Approved Operator of a specific Token
     * @param _tokenId  The ID of the Token
     * @return  The address of the approved operator
     */
    function getApproved(uint256 _tokenId) public view returns (address) {
        address owner = ownerOf(_tokenId);
        require(owner != address(0x0), "E112");
        return tokenApprovals[_tokenId];
    }

    /**
     * @notice Enable or disable approval for a third party ("operator") to manage all of caller's tokens
     * @param _operator  Address to add to the set of authorized operators
     * @param _approved  True if the operator is approved, false to revoke approval
     */
    function setApprovalForAll(address _operator, bool _approved) public {
        operators[msg.sender][_operator] = _approved;
        emit ApprovalForAll(msg.sender, _operator, _approved);
    }

    /**
     * @notice Queries the approval status of an operator for a given owner
     * @param _tokenOwner   The owner of the Tokens
     * @param _operator     Address of authorized operator
     * @return True if the operator is approved, false if not
     */
    function isApprovedForAll(address _tokenOwner, address _operator) public view returns (bool) {
        return operators[_tokenOwner][_operator];
    }

    /**
     * @notice Transfers amount of an _id from the _from address to the _to address specified
     * @param _from     The Address of the Token Holder
     * @param _to       The Address of the Token Receiver
     * @param _id       ID of the Token
     * @param _amount   The Amount to transfer
     */
    function transferFrom(address _from, address _to, uint256 _id, uint256 _amount) public {
        require((msg.sender == _from) || isApprovedForAll(_from, msg.sender), "E105");
        require(_to != address(0x0),"E101");

        _safeTransferFrom(_from, _to, _id, _amount);
    }

    /**
     * @notice Safe-transfers amount of an _id from the _from address to the _to address specified
     * @param _from     The Address of the Token Holder
     * @param _to       The Address of the Token Receiver
     * @param _id       ID of the Token
     * @param _amount   The Amount to transfer
     * @param _data     Additional data with no specified format, sent in call to `_to`
     */
    function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _amount, bytes memory _data) public {
        require((msg.sender == _from) || isApprovedForAll(_from, msg.sender), "E105");
        require(_to != address(0x0),"E101");

        _safeTransferFrom(_from, _to, _id, _amount);
        _callonERC1155Received(_from, _to, _id, _amount, _data);
    }

    /**
     * @notice Send multiple types of Tokens from the _from address to the _to address (with safety call)
     * @param _from     The Address of the Token Holder
     * @param _to       The Address of the Token Receiver
     * @param _ids      IDs of each Token
     * @param _amounts  The Amount to transfer per Token
     * @param _data     Additional data with no specified format, sent in call to `_to`
     */
    function safeBatchTransferFrom(address _from, address _to, uint256[] memory _ids, uint256[] memory _amounts, bytes memory _data) public {
        require((msg.sender == _from) || isApprovedForAll(_from, msg.sender), "E105");
        require(_to != address(0x0),"E101");

        _safeBatchTransferFrom(_from, _to, _ids, _amounts);
        _callonERC1155BatchReceived(_from, _to, _ids, _amounts, _data);
    }

    /***********************************|
    |         Private Functions         |
    |__________________________________*/

    /**
     * @notice Transfers amount amount of an _id from the _from address to the _to address specified
     * @param _from     The Address of the Token Holder
     * @param _to       The Address of the Token Receiver
     * @param _id       ID of the Token
     * @param _amount   The Amount to transfer
     */
    function _safeTransferFrom(address _from, address _to, uint256 _id, uint256 _amount) internal {
        // Non-Fungible
        if (_id & TYPE_NF_BIT == TYPE_NF_BIT) {
            uint256 _typeId = _id & TYPE_MASK;

            require(nfOwners[_id] == _from);
            nfOwners[_id] = _to;
            _amount = 1;

            _removeTokenFromOwnerEnumeration(_typeId, _from, _id);
            _addTokenToOwnerEnumeration(_typeId, _to, _id);
        }
        // Fungible
        else {
//            require(_amount <= balances[_from][_id]); // SafeMath will throw if balance is negative
            balances[_from][_id] = balances[_from][_id].sub(_amount); // Subtract amount
            balances[_to][_id] = balances[_to][_id].add(_amount);     // Add amount
        }

        // Emit event
        emit TransferSingle(msg.sender, _from, _to, _id, _amount);
    }

    /**
     * @notice Send multiple types of Tokens from the _from address to the _to address (with safety call)
     * @param _from     The Address of the Token Holder
     * @param _to       The Address of the Token Receiver
     * @param _ids      IDs of each Token
     * @param _amounts  The Amount to transfer per Token
     */
    function _safeBatchTransferFrom(address _from, address _to, uint256[] memory _ids, uint256[] memory _amounts) internal {
        require(_ids.length == _amounts.length, "E103");

        uint256 id;
        uint256 amount;
        uint256 typeId;
        uint256 nTransfer = _ids.length;
        for (uint256 i = 0; i < nTransfer; ++i) {
            id = _ids[i];
            amount = _amounts[i];

            if (id & TYPE_NF_BIT == TYPE_NF_BIT) { // Non-Fungible
                typeId = id & TYPE_MASK;
                require(nfOwners[id] == _from);
                nfOwners[id] = _to;

                _removeTokenFromOwnerEnumeration(typeId, _from, id);
                _addTokenToOwnerEnumeration(typeId, _to, id);
            } else {
//                require(amount <= balances[_from][id]); // SafeMath will throw if balance is negative
                balances[_from][id] = balances[_from][id].sub(amount);
                balances[_to][id] = balances[_to][id].add(amount);
            }
        }

        emit TransferBatch(msg.sender, _from, _to, _ids, _amounts);
    }

    /**
     * @dev Creates a new Type, either FT or NFT
     * @param _uri   The Metadata URI of the Token (ERC721 only)
     * @param _isNF  True for NFT Types; False otherwise
     */
    function _createType(string memory _uri, bool _isNF) internal returns (uint256 _type) {
        require(bytes(_uri).length > 0, "E107");

        _type = (++nonce << 128);
        if (_isNF) {
            _type = _type | TYPE_NF_BIT;
        }
        tokenUri[_type] = _uri;

        // emit a Transfer event with Create semantic to help with discovery.
        emit TransferSingle(msg.sender, address(0x0), address(0x0), _type, 0);
        emit URI(_type, _uri);
    }

    /**
     * @dev Mints a new Token, either FT or NFT
     * @param _to      The Address of the Token Receiver
     * @param _type    The Type ID of the Token
     * @param _amount  The amount of the Token to Mint
     * @param _URI     The Metadata URI of the Token (ERC721 only)
     * @param _data    Additional data with no specified format, sent in call to `_to`
     * @return The Token ID of the newly minted Token
     */
    function _mint(address _to, uint256 _type, uint256 _amount, string memory _URI, bytes memory _data) internal returns (uint256) {
        uint256 _tokenId;

        // Non-fungible
        if (_type & TYPE_NF_BIT == TYPE_NF_BIT) {
            uint256 index = mintedByType[_type].add(1);
            mintedByType[_type] = index;

            _tokenId  = _type | index;
            nfOwners[_tokenId] = _to;
            tokenUri[_tokenId] = _URI;
            _amount = 1;

            _addTokenToOwnerEnumeration(_type, _to, _tokenId);
            _addTokenToAllTokensEnumeration(_type, _tokenId);
        }

        // Fungible
        else {
            _tokenId = _type;
            supplyByType[_type] = supplyByType[_type].add(_amount);
            mintedByType[_type] = mintedByType[_type].add(_amount);
            balances[_to][_type] = balances[_to][_type].add(_amount);
        }

        emit TransferSingle(msg.sender, address(0x0), _to, _tokenId, _amount);
        _callonERC1155Received(address(0x0), _to, _tokenId, _amount, _data);

        return _tokenId;
    }

    /**
     * @dev Mints a Batch of new Tokens, either FT or NFT
     * @param _to       The Address of the Token Receiver
     * @param _types    The Type IDs of the Tokens
     * @param _amounts  The amounts of the Tokens to Mint
     * @param _URIs     The Metadata URI of the Tokens (ERC721 only)
     * @param _data     Additional data with no specified format, sent in call to `_to`
     * @return The Token IDs of the newly minted Tokens
     */
    function _mintBatch(address _to, uint256[] memory _types, uint256[] memory _amounts, string[] memory _URIs, bytes memory _data) internal returns (uint256[] memory) {
        require(_types.length == _amounts.length, "E103");
        uint256 _type;
        uint256 _index;
        uint256 _tokenId;
        uint256 _count = _types.length;

        uint256[] memory _tokenIds = new uint256[](_count);

        for (uint256 i = 0; i < _count; i++) {
            _type = _types[i];

            // Non-fungible
            if (_type & TYPE_NF_BIT == TYPE_NF_BIT) {
                _index = mintedByType[_type].add(1);
                mintedByType[_type] = _index;

                _tokenId  = _type | _index;
                nfOwners[_tokenId] = _to;
                _tokenIds[i] = _tokenId;
                tokenUri[_tokenId] = _URIs[i];
                _amounts[i] = 1;

                _addTokenToOwnerEnumeration(_type, _to, _tokenId);
                _addTokenToAllTokensEnumeration(_type, _tokenId);
            }

            // Fungible
            else {
                _tokenIds[i] = _type;
                supplyByType[_type] = supplyByType[_type].add(_amounts[i]);
                mintedByType[_type] = mintedByType[_type].add(_amounts[i]);
                balances[_to][_type] = balances[_to][_type].add(_amounts[i]);
            }
        }

        emit TransferBatch(msg.sender, address(0x0), _to, _tokenIds, _amounts);
        _callonERC1155BatchReceived(address(0x0), _to, _tokenIds, _amounts, _data);

        return _tokenIds;
    }

    /**
     * @dev Burns an existing Token, either FT or NFT
     * @param _from     The Address of the Token Holder
     * @param _tokenId  The ID of the Token
     * @param _amount   The Amount to burn
     */
    function _burn(address _from, uint256 _tokenId, uint256 _amount) internal {
        uint256 _typeId = _tokenId;

        // Non-fungible
        if (_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) {
            address _tokenOwner = ownerOf(_tokenId);
            require(_tokenOwner == _from || isApprovedForAll(_tokenOwner, _from), "E105");
            nfOwners[_tokenId] = address(0x0);
            tokenUri[_tokenId] = "";
            _typeId = _tokenId & TYPE_MASK;
            _amount = 1;

            _removeTokenFromOwnerEnumeration(_typeId, _tokenOwner, _tokenId);
            _removeTokenFromAllTokensEnumeration(_typeId, _tokenId);
        }

        // Fungible
        else {
            require(balanceOf(_from, _tokenId) >= _amount, "E106");
            supplyByType[_typeId] = supplyByType[_typeId].sub(_amount);
            balances[_from][_typeId] = balances[_from][_typeId].sub(_amount);
        }

        emit TransferSingle(msg.sender, _from, address(0x0), _tokenId, _amount);
    }

    /**
     * @dev Burns a Batch of existing Tokens, either FT or NFT
     * @param _from      The Address of the Token Holder
     * @param _tokenIds  The IDs of the Tokens
     * @param _amounts   The Amounts to Burn of each Token
     */
    function _burnBatch(address _from, uint256[] memory _tokenIds, uint256[] memory _amounts) internal {
        require(_tokenIds.length == _amounts.length, "E103");

        uint256 _tokenId;
        uint256 _typeId;
        address _tokenOwner;
        uint256 _count = _tokenIds.length;
        for (uint256 i = 0; i < _count; i++) {
            _tokenId = _tokenIds[i];
            _typeId = _tokenId;

            // Non-fungible
            if (_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) {
                _tokenOwner = ownerOf(_tokenId);
                require(_tokenOwner == _from || isApprovedForAll(_tokenOwner, _from), "E105");
                nfOwners[_tokenId] = address(0x0);
                tokenUri[_tokenId] = "";
                _typeId = _tokenId & TYPE_MASK;
                _amounts[i] = 1;

                _removeTokenFromOwnerEnumeration(_typeId, _tokenOwner, _tokenId);
                _removeTokenFromAllTokensEnumeration(_typeId, _tokenId);
            }

            // Fungible
            else {
                require(balanceOf(_from, _tokenId) >= _amounts[i], "E106");
                supplyByType[_typeId] = supplyByType[_typeId].sub(_amounts[i]);
                balances[_from][_tokenId] = balances[_from][_tokenId].sub(_amounts[i]);
            }
        }

        emit TransferBatch(msg.sender, _from, address(0x0), _tokenIds, _amounts);
    }

    /**
     * @dev Adds NFT Tokens to a Users Enumerable List
     * @param _typeId   The Type ID of the Token 
     * @param _to       The Address of the Token Receiver
     * @param _tokenId  The ID of the Token
     */
    function _addTokenToOwnerEnumeration(uint256 _typeId, address _to, uint256 _tokenId) internal {
        ownedTokensByTypeIndex[_typeId][_tokenId] = ownedTokensByType[_typeId][_to].length;
        ownedTokensByType[_typeId][_to].push(_tokenId);
    }

    /**
     * @dev Adds NFT Tokens to the All-Tokens Enumerable List
     * @param _typeId   The Type ID of the Token 
     * @param _tokenId  The ID of the Token
     */
    function _addTokenToAllTokensEnumeration(uint256 _typeId, uint256 _tokenId) internal {
        allTokensByTypeIndex[_typeId][_tokenId] = allTokensByType[_typeId].length;
        allTokensByType[_typeId].push(_tokenId);
    }

    /**
     * @dev Removes NFT Tokens from a Users Enumerable List
     * @param _typeId   The Type ID of the Token 
     * @param _from     The Address of the Token Holder
     * @param _tokenId  The ID of the Token
     */
    function _removeTokenFromOwnerEnumeration(uint256 _typeId, address _from, uint256 _tokenId) internal {
        uint256 _lastTokenIndex = ownedTokensByType[_typeId][_from].length.sub(1);
        uint256 _tokenIndex = ownedTokensByTypeIndex[_typeId][_tokenId];

        if (_tokenIndex != _lastTokenIndex) {
            uint256 _lastTokenId = ownedTokensByType[_typeId][_from][_lastTokenIndex];

            ownedTokensByType[_typeId][_from][_tokenIndex] = _lastTokenId;
            ownedTokensByTypeIndex[_typeId][_lastTokenId] = _tokenIndex;
        }
        ownedTokensByType[_typeId][_from].length--;
        ownedTokensByTypeIndex[_typeId][_tokenId] = 0;
    }

    /**
     * @dev Removes NFT Tokens from the All-Tokens Enumerable List
     * @param _typeId   The Type ID of the Token 
     * @param _tokenId  The ID of the Token
     */
    function _removeTokenFromAllTokensEnumeration(uint256 _typeId, uint256 _tokenId) internal {
        uint256 _lastTokenIndex = allTokensByType[_typeId].length.sub(1);
        uint256 _tokenIndex = allTokensByTypeIndex[_typeId][_tokenId];
        uint256 _lastTokenId = allTokensByType[_typeId][_lastTokenIndex];

        allTokensByType[_typeId][_tokenIndex] = _lastTokenId;
        allTokensByTypeIndex[_typeId][_lastTokenId] = _tokenIndex;

        allTokensByType[_typeId].length--;
        allTokensByTypeIndex[_typeId][_tokenId] = 0;
    }

    /**
     * @dev Check if the Receiver is a Contract and ensure compatibility to the ERC1155 spec
     */
    function _callonERC1155Received(address _from, address _to, uint256 _id, uint256 _amount, bytes memory _data) internal {
        // Check if recipient is a contract
        if (_to.isContract()) {
            bytes4 retval = IERC1155TokenReceiver(_to).onERC1155Received(msg.sender, _from, _id, _amount, _data);
            require(retval == ERC1155_RECEIVED_VALUE, "E102");
        }
    }

    /**
     * @dev  Check if the Receiver is a Contract and ensure compatibility to the ERC1155 spec
     */
    function _callonERC1155BatchReceived(address _from, address _to, uint256[] memory _ids, uint256[] memory _amounts, bytes memory _data) internal {
        // Pass data if recipient is a contract
        if (_to.isContract()) {
            bytes4 retval = IERC1155TokenReceiver(_to).onERC1155BatchReceived(msg.sender, _from, _ids, _amounts, _data);
            require(retval == ERC1155_BATCH_RECEIVED_VALUE, "E102");
        }
    }
}


// SPDX-License-Identifier: MIT

// BridgedERC1155.sol - Charged Particles
// Copyright (c) 2019, 2020 Rob Secord <robsecord.eth>
//
// Original Idea: https://github.com/pelith/erc-1155-adapter
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

pragma solidity 0.6.10;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/IERC721Receiver.sol";
import "./ERC1155.sol";


/**
 * @notice ERC-1155 Token Standard with support for Bridges to individual ERC-20 & ERC-721 Token Contracts
 */
abstract contract BridgedERC1155 is Initializable, ERC1155 {

    //        TypeID => Token Bridge Address
    mapping (uint256 => address) internal bridge;

    // Template Contracts for creating Token Bridges
    address internal templateErc20;
    address internal templateErc721;

    //
    // Events
    //
    event NewBridge(uint256 indexed _typeId, address indexed _bridge);

    //
    // Modifiers
    //
    /**
     * @dev Throws if called by any account other than a Bridge contract.
     */
    modifier onlyBridge(uint256 _typeId) {
        require(bridge[_typeId] == msg.sender, "B1155: ONLY_BRIDGE");
        _;
    }


    /***********************************|
    |          Initialization           |
    |__________________________________*/

    function initialize() public virtual override initializer {
        ERC1155.initialize();

        // Create Bridge Contract Templates
        templateErc20 = address(new ERC20Bridge());
        templateErc721 = address(new ERC721Bridge());
    }


    /***********************************|
    |            Only Bridge            |
    |__________________________________*/

    /**
     * @notice Sets an Operator Approval to manage a specific token by type in the ERC1155 Contract from a Bridge Contract
     */
    function approveBridged(
        uint256 _typeId,
        address _from,
        address _operator,
        uint256 _tokenId
    )
        public
        onlyBridge(_typeId)
    {
        uint256 _tokenTypeId = _tokenId;
        if (_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) {
            _tokenTypeId = _tokenId & TYPE_MASK;
        }
        require(_tokenTypeId == _typeId, "B1155: INVALID_TYPE");

        address _owner = _ownerOf(_tokenId);
        require(_operator != _owner, "B1155: INVALID_OPERATOR");
        require(_from == _owner || isApprovedForAll(_owner, _from), "B1155: NOT_OPERATOR");

        tokenApprovals[_tokenId] = _operator;
        emit Approval(_owner, _operator, _tokenId);
    }

    /**
     * @notice Sets an Operator Approval to manage all tokens by type in the ERC1155 Contract from a Bridge Contract
     */
    function setApprovalForAllBridged(
        uint256 _typeId,
        address _from,
        address _operator,
        bool _approved
    )
        public
        onlyBridge(_typeId)
    {
        operators[_from][_operator] = _approved;
        emit ApprovalForAll(_from, _operator, _approved);
    }

    /**
     * @notice Safe-transfers a specific token by type in the ERC1155 Contract from a Bridge Contract
     */
    function transferFromBridged(
        uint256 _typeId,
        address _from,
        address _to,
        uint256 _tokenId,
        uint256 _value
    )
        public
        onlyBridge(_typeId)
        returns (bool)
    {
        require(_to != address(0x0), "B1155: INVALID_ADDRESS");

        uint256 _tokenTypeId = _tokenId;
        if (_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) {
            _tokenTypeId = _tokenId & TYPE_MASK;
        }
        require(_tokenTypeId == _typeId, "B1155: INVALID_TYPE");

        _safeTransferFrom(_from, _to, _tokenId, _value);
        return true;
    }


    /***********************************|
    |         Private Functions         |
    |__________________________________*/

    /**
     * @dev Creates an ERC20 Token Bridge Contract to interface with the ERC1155 Contract
     */
    function _createErc20Bridge(
        uint256 _typeId,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    )
        internal
        returns (address)
    {
        require(bridge[_typeId] == address(0), "B1155: INVALID_BRIDGE");

        address newBridge = _createClone(templateErc20);
        ERC20Bridge(newBridge).setup(_typeId, _name, _symbol, _decimals);
        bridge[_typeId] = newBridge;

        emit NewBridge(_typeId, newBridge);
        return newBridge;
    }

    /**
     * @dev Creates an ERC721 Token Bridge Contract to interface with the ERC1155 Contract
     */
    function _createErc721Bridge(
        uint256 _typeId,
        string memory _name,
        string memory _symbol
    )
        internal
        returns (address)
    {
        require(bridge[_typeId] == address(0), "B1155: INVALID_BRIDGE");

        address newBridge = _createClone(templateErc721);
        ERC721Bridge(newBridge).setup(_typeId, _name, _symbol);
        bridge[_typeId] = newBridge;

        emit NewBridge(_typeId, newBridge);
        return newBridge;
    }

    /**
     * @dev Creates Contracts from a Template via Cloning
     * see: https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1167.md
     */
    function _createClone(address target) internal returns (address result) {
        bytes20 targetBytes = bytes20(target);
        // solhint-disable-next-line
        assembly {
            let clone := mload(0x40)
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone, 0x14), targetBytes)
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            result := create(0, clone, 0x37)
        }
    }
}


/**
 * @notice ERC20 Token Bridge
 */
contract ERC20Bridge {
    using SafeMath for uint256;

    BridgedERC1155 public entity;

    uint256 public typeId;
    string public name;
    string public symbol;
    uint8 public decimals;

    mapping (address => mapping (address => uint256)) private allowed;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setup(uint256 _typeId, string memory _name, string memory _symbol, uint8 _decimals) public {
        require(typeId == 0 && address(entity) == address(0), "B1155: ERC20_ALREADY_INIT");
        entity = BridgedERC1155(msg.sender);
        typeId = _typeId;
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function totalSupply() external view returns (uint256) {
        return entity.totalSupply(typeId);
    }

    function balanceOf(address _account) external view returns (uint256) {
        return entity.balanceOf(_account, typeId);
    }

    function transfer(address _recipient, uint256 _amount) external returns (bool) {
        require(entity.transferFromBridged(typeId, msg.sender, _recipient, typeId, _amount), "B1155: ERC20_TRANSFER_FAILED");
        emit Transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function allowance(address _owner, address _spender) external view returns (uint256) {
        return allowed[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) external returns (bool) {
        allowed[msg.sender][_spender] = _amount;
        emit Approval(msg.sender, _spender, _amount);
        return true;
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool) {
        allowed[_sender][msg.sender] = allowed[_sender][msg.sender].sub(_amount);
        require(entity.transferFromBridged(typeId, _sender, _recipient, typeId, _amount), "B1155: ERC20_TRANSFER_FAILED");
        emit Transfer(_sender, _recipient, _amount);
        return true;
    }
}
// ERC20 ABI
/*
[
    {
        "anonymous": false,
        "inputs": [
            {
                "indexed": true,
                "internalType": "address",
                "name": "from",
                "type": "address"
            },
            {
                "indexed": true,
                "internalType": "address",
                "name": "to",
                "type": "address"
            },
            {
                "indexed": true,
                "internalType": "uint256",
                "name": "tokenId",
                "type": "uint256"
            }
        ],
        "name": "Transfer",
        "type": "event"
    },
    {
        "constant": false,
        "inputs": [
            {
                "internalType": "address",
                "name": "_to",
                "type": "address"
            },
            {
                "internalType": "uint256",
                "name": "_tokenId",
                "type": "uint256"
            }
        ],
        "name": "approve",
        "outputs": [],
        "payable": false,
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [
            {
                "internalType": "address",
                "name": "_account",
                "type": "address"
            }
        ],
        "name": "balanceOf",
        "outputs": [
            {
                "internalType": "uint256",
                "name": "",
                "type": "uint256"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [],
        "name": "entity",
        "outputs": [
            {
                "internalType": "contract IBridgedERC1155",
                "name": "",
                "type": "address"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [
            {
                "internalType": "uint256",
                "name": "_tokenId",
                "type": "uint256"
            }
        ],
        "name": "getApproved",
        "outputs": [
            {
                "internalType": "address",
                "name": "",
                "type": "address"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [
            {
                "internalType": "address",
                "name": "_owner",
                "type": "address"
            },
            {
                "internalType": "address",
                "name": "_operator",
                "type": "address"
            }
        ],
        "name": "isApprovedForAll",
        "outputs": [
            {
                "internalType": "bool",
                "name": "",
                "type": "bool"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [],
        "name": "name",
        "outputs": [
            {
                "internalType": "string",
                "name": "",
                "type": "string"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [
            {
                "internalType": "uint256",
                "name": "_tokenId",
                "type": "uint256"
            }
        ],
        "name": "ownerOf",
        "outputs": [
            {
                "internalType": "address",
                "name": "",
                "type": "address"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": false,
        "inputs": [
            {
                "internalType": "address",
                "name": "_from",
                "type": "address"
            },
            {
                "internalType": "address",
                "name": "_to",
                "type": "address"
            },
            {
                "internalType": "uint256",
                "name": "_tokenId",
                "type": "uint256"
            }
        ],
        "name": "safeTransferFrom",
        "outputs": [],
        "payable": false,
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "constant": false,
        "inputs": [
            {
                "internalType": "address",
                "name": "_from",
                "type": "address"
            },
            {
                "internalType": "address",
                "name": "_to",
                "type": "address"
            },
            {
                "internalType": "uint256",
                "name": "_tokenId",
                "type": "uint256"
            },
            {
                "internalType": "bytes",
                "name": "_data",
                "type": "bytes"
            }
        ],
        "name": "safeTransferFrom",
        "outputs": [],
        "payable": false,
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "constant": false,
        "inputs": [
            {
                "internalType": "address",
                "name": "_operator",
                "type": "address"
            },
            {
                "internalType": "bool",
                "name": "_approved",
                "type": "bool"
            }
        ],
        "name": "setApprovalForAll",
        "outputs": [],
        "payable": false,
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "constant": false,
        "inputs": [
            {
                "internalType": "uint256",
                "name": "_typeId",
                "type": "uint256"
            },
            {
                "internalType": "string",
                "name": "_name",
                "type": "string"
            },
            {
                "internalType": "string",
                "name": "_symbol",
                "type": "string"
            }
        ],
        "name": "setup",
        "outputs": [],
        "payable": false,
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [
            {
                "internalType": "bytes4",
                "name": "interfaceId",
                "type": "bytes4"
            }
        ],
        "name": "supportsInterface",
        "outputs": [
            {
                "internalType": "bool",
                "name": "",
                "type": "bool"
            }
        ],
        "payable": false,
        "stateMutability": "pure",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [],
        "name": "symbol",
        "outputs": [
            {
                "internalType": "string",
                "name": "",
                "type": "string"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [
            {
                "internalType": "uint256",
                "name": "_index",
                "type": "uint256"
            }
        ],
        "name": "tokenByIndex",
        "outputs": [
            {
                "internalType": "uint256",
                "name": "",
                "type": "uint256"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [
            {
                "internalType": "address",
                "name": "_owner",
                "type": "address"
            },
            {
                "internalType": "uint256",
                "name": "_index",
                "type": "uint256"
            }
        ],
        "name": "tokenOfOwnerByIndex",
        "outputs": [
            {
                "internalType": "uint256",
                "name": "",
                "type": "uint256"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [
            {
                "internalType": "uint256",
                "name": "_tokenId",
                "type": "uint256"
            }
        ],
        "name": "tokenURI",
        "outputs": [
            {
                "internalType": "string",
                "name": "",
                "type": "string"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [],
        "name": "totalSupply",
        "outputs": [
            {
                "internalType": "uint256",
                "name": "",
                "type": "uint256"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": false,
        "inputs": [
            {
                "internalType": "address",
                "name": "_from",
                "type": "address"
            },
            {
                "internalType": "address",
                "name": "_to",
                "type": "address"
            },
            {
                "internalType": "uint256",
                "name": "_tokenId",
                "type": "uint256"
            }
        ],
        "name": "transferFrom",
        "outputs": [],
        "payable": false,
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [],
        "name": "typeId",
        "outputs": [
            {
                "internalType": "uint256",
                "name": "",
                "type": "uint256"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    }
]
*/

/**
 * @notice ERC721 Token Bridge
 */
contract ERC721Bridge {
    BridgedERC1155 public entity;

    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 private constant ERC721_RECEIVED = 0x150b7a02;
    uint256 public typeId;
    string public name;
    string public symbol;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function setup(uint256 _typeId, string memory _name, string memory _symbol) public {
        require(typeId == 0 && address(entity) == address(0), "B1155: ERC721_ALREADY_INIT");
        entity = BridgedERC1155(msg.sender);
        typeId = _typeId;
        name = _name;
        symbol = _symbol;
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        require(interfaceId != 0xffffffff, "B1155: ERC721_INVALID_INTERFACE");
        return interfaceId == INTERFACE_ID_ERC721;
    }

    function totalSupply() external view returns (uint256) {
        return entity.totalSupply(typeId);
    }

    function balanceOf(address _account) external view returns (uint256) {
        return entity.balanceOf(_account, typeId);
    }

    function ownerOf(uint256 _tokenId) external view returns (address) {
        return entity.ownerOf(_tokenId);
    }

    function approve(address _to, uint256 _tokenId) external {
        entity.approveBridged(typeId, msg.sender, _to, _tokenId);
    }
    function getApproved(uint256 _tokenId) external view returns (address) {
        return entity.getApproved(_tokenId);
    }

    function setApprovalForAll(address _operator, bool _approved) external {
        entity.setApprovalForAllBridged(typeId, msg.sender, _operator, _approved);
    }
    function isApprovedForAll(address _owner, address _operator) external view returns (bool) {
        return entity.isApprovedForAll(_owner, _operator);
    }

    function transferFrom(address _from, address _to, uint256 _tokenId) external {
        _transferFrom(msg.sender, _from, _to, _tokenId);
    }
    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external {
        _safeTransferFrom(msg.sender, _from, _to, _tokenId, "");
    }
    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes calldata _data) external {
        _safeTransferFrom(msg.sender, _from, _to, _tokenId, _data);
    }

    // Enumeration
    function tokenOfOwnerByIndex(address _owner, uint256 _index) external view returns (uint256) {
        return entity.tokenOfOwnerByIndex(typeId, _owner, _index);
    }
    function tokenByIndex(uint256 _index) external view returns (uint256) {
        return entity.tokenByIndex(typeId, _index);
    }

    // Metadata
    function tokenURI(uint256 _tokenId) external view returns (string memory) {
        return entity.uri(_tokenId);
    }

    function _transferFrom(address _operator, address _from, address _to, uint256 _tokenId) internal {
        require((_operator == _from) || entity.isApprovedForAll(_from, _operator), "B1155: ERC721_NOT_OPERATOR");
        require(entity.transferFromBridged(typeId, _from, _to, _tokenId, 1), "B1155: ERC721_TRANSFER_FAILED");
        emit Transfer(_from, _to, _tokenId);
    }

    function _safeTransferFrom(address _operator, address _from, address _to, uint256 _tokenId, bytes memory _data) internal {
        require((_operator == _from) || entity.isApprovedForAll(_from, _operator), "B1155: ERC721_NOT_OPERATOR");
        require(entity.transferFromBridged(typeId, _from, _to, _tokenId, 1), "B1155: ERC721_TRANSFER_FAILED");
        require(_checkOnERC721Received(_operator, _from, _to, _tokenId, _data), "B1155: ERC721_INVALID_RECEIVER");
        emit Transfer(_from, _to, _tokenId);
    }

    function _isContract(address account) internal view returns (bool) {
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly { codehash := extcodehash(account) }
        return (codehash != 0x0 && codehash != accountHash);
    }

    function _checkOnERC721Received(address _operator, address _from, address _to, uint256 _tokenId, bytes memory _data) internal returns (bool) {
        if (!_isContract(_to)) { return true; }
        bytes4 retval = IERC721Receiver(_to).onERC721Received(_operator, _from, _tokenId, _data);
        return (retval == ERC721_RECEIVED);
    }
}
// ERC721 ABI
/*
[
    {
        "anonymous": false,
        "inputs": [
            {
                "indexed": true,
                "internalType": "address",
                "name": "from",
                "type": "address"
            },
            {
                "indexed": true,
                "internalType": "address",
                "name": "to",
                "type": "address"
            },
            {
                "indexed": true,
                "internalType": "uint256",
                "name": "tokenId",
                "type": "uint256"
            }
        ],
        "name": "Transfer",
        "type": "event"
    },
    {
        "constant": false,
        "inputs": [
            {
                "internalType": "address",
                "name": "_to",
                "type": "address"
            },
            {
                "internalType": "uint256",
                "name": "_tokenId",
                "type": "uint256"
            }
        ],
        "name": "approve",
        "outputs": [],
        "payable": false,
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [
            {
                "internalType": "address",
                "name": "_account",
                "type": "address"
            }
        ],
        "name": "balanceOf",
        "outputs": [
            {
                "internalType": "uint256",
                "name": "",
                "type": "uint256"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [],
        "name": "entity",
        "outputs": [
            {
                "internalType": "contract IBridgedERC1155",
                "name": "",
                "type": "address"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [
            {
                "internalType": "uint256",
                "name": "_tokenId",
                "type": "uint256"
            }
        ],
        "name": "getApproved",
        "outputs": [
            {
                "internalType": "address",
                "name": "",
                "type": "address"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [
            {
                "internalType": "address",
                "name": "_owner",
                "type": "address"
            },
            {
                "internalType": "address",
                "name": "_operator",
                "type": "address"
            }
        ],
        "name": "isApprovedForAll",
        "outputs": [
            {
                "internalType": "bool",
                "name": "",
                "type": "bool"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [],
        "name": "name",
        "outputs": [
            {
                "internalType": "string",
                "name": "",
                "type": "string"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [
            {
                "internalType": "uint256",
                "name": "_tokenId",
                "type": "uint256"
            }
        ],
        "name": "ownerOf",
        "outputs": [
            {
                "internalType": "address",
                "name": "",
                "type": "address"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": false,
        "inputs": [
            {
                "internalType": "address",
                "name": "_from",
                "type": "address"
            },
            {
                "internalType": "address",
                "name": "_to",
                "type": "address"
            },
            {
                "internalType": "uint256",
                "name": "_tokenId",
                "type": "uint256"
            }
        ],
        "name": "safeTransferFrom",
        "outputs": [],
        "payable": false,
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "constant": false,
        "inputs": [
            {
                "internalType": "address",
                "name": "_from",
                "type": "address"
            },
            {
                "internalType": "address",
                "name": "_to",
                "type": "address"
            },
            {
                "internalType": "uint256",
                "name": "_tokenId",
                "type": "uint256"
            },
            {
                "internalType": "bytes",
                "name": "_data",
                "type": "bytes"
            }
        ],
        "name": "safeTransferFrom",
        "outputs": [],
        "payable": false,
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "constant": false,
        "inputs": [
            {
                "internalType": "address",
                "name": "_operator",
                "type": "address"
            },
            {
                "internalType": "bool",
                "name": "_approved",
                "type": "bool"
            }
        ],
        "name": "setApprovalForAll",
        "outputs": [],
        "payable": false,
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "constant": false,
        "inputs": [
            {
                "internalType": "uint256",
                "name": "_typeId",
                "type": "uint256"
            },
            {
                "internalType": "string",
                "name": "_name",
                "type": "string"
            },
            {
                "internalType": "string",
                "name": "_symbol",
                "type": "string"
            }
        ],
        "name": "setup",
        "outputs": [],
        "payable": false,
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [
            {
                "internalType": "bytes4",
                "name": "interfaceId",
                "type": "bytes4"
            }
        ],
        "name": "supportsInterface",
        "outputs": [
            {
                "internalType": "bool",
                "name": "",
                "type": "bool"
            }
        ],
        "payable": false,
        "stateMutability": "pure",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [],
        "name": "symbol",
        "outputs": [
            {
                "internalType": "string",
                "name": "",
                "type": "string"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [
            {
                "internalType": "uint256",
                "name": "_index",
                "type": "uint256"
            }
        ],
        "name": "tokenByIndex",
        "outputs": [
            {
                "internalType": "uint256",
                "name": "",
                "type": "uint256"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [
            {
                "internalType": "address",
                "name": "_owner",
                "type": "address"
            },
            {
                "internalType": "uint256",
                "name": "_index",
                "type": "uint256"
            }
        ],
        "name": "tokenOfOwnerByIndex",
        "outputs": [
            {
                "internalType": "uint256",
                "name": "",
                "type": "uint256"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [
            {
                "internalType": "uint256",
                "name": "_tokenId",
                "type": "uint256"
            }
        ],
        "name": "tokenURI",
        "outputs": [
            {
                "internalType": "string",
                "name": "",
                "type": "string"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [],
        "name": "totalSupply",
        "outputs": [
            {
                "internalType": "uint256",
                "name": "",
                "type": "uint256"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    },
    {
        "constant": false,
        "inputs": [
            {
                "internalType": "address",
                "name": "_from",
                "type": "address"
            },
            {
                "internalType": "address",
                "name": "_to",
                "type": "address"
            },
            {
                "internalType": "uint256",
                "name": "_tokenId",
                "type": "uint256"
            }
        ],
        "name": "transferFrom",
        "outputs": [],
        "payable": false,
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "constant": true,
        "inputs": [],
        "name": "typeId",
        "outputs": [
            {
                "internalType": "uint256",
                "name": "",
                "type": "uint256"
            }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
    }
]

*/

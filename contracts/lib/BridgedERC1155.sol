// BridgedERC1155.sol
// MIT License
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

// Reduce deployment gas costs by limiting the size of text used in error messages
// ERROR CODES:
//  200:        BridgedERC1155
//      201         Invalid Bridge
//      202         Non-existent Bridge
//      203         Token is not of Type
//      204         Approval to current owner
//      205         Approve caller is not owner nor approved for all
//      206         Bridge already setup
//      207         Invalid owner/operator
//      208         ERC-20: Transfer failed
//      209         ERC-721: Transfer failed
//      210         ERC721: Transfer to non ERC721Receiver implementer
//      211         ERC165: Invalid interface id

pragma solidity ^0.5.16;


import "../../node_modules/@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import "../../node_modules/@openzeppelin/contracts-ethereum-package/contracts/introspection/IERC165.sol";
import "../../node_modules/@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/IERC721Receiver.sol";
import "../../node_modules/@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "./ERC1155.sol";


contract BridgedERC1155 is Initializable, ERC1155 {
    bytes4 constant internal ERC1155_TOKEN_RECEIVER = 0x4e2312e0;

    //       TypeID => Bridge Address
    mapping(uint256 => address) internal bridge;

    address internal templateErc20;
    address internal templateErc721;

    event NewBridge(uint256 indexed _typeId, address indexed _bridge);

    function initialize() public initializer {
        ERC1155.initialize();
        templateErc20 = address(new ERC20Bridge());
        templateErc721 = address(new ERC721Bridge());
    }

    function approveBridged(uint256 _typeId, address _from, address _operator, uint256 _tokenId) public {
        require(bridge[_typeId] == msg.sender, "E201");

        uint256 _tokenTypeId = _tokenId & TYPE_MASK;
        require(_tokenTypeId == _typeId, "E203");

        address _owner = ownerOf(_tokenId);
        require(_operator != _owner, "E204");
        require(_from == _owner || isApprovedForAll(_owner, _from), "E205");

        tokenApprovals[_tokenId] = _operator;
        emit Approval(_owner, _operator, _tokenId);
    }

    function setApprovalForAllBridged(uint256 _typeId, address _from, address _operator, bool _approved) public {
        require(bridge[_typeId] == msg.sender, "E201");

        operators[_from][_operator] = _approved;
        emit ApprovalForAll(_from, _operator, _approved);
    }


    function transferFromBridged(uint256 _typeId, address _from, address _to, uint256 _tokenId, uint256 _value) public returns (bool) {
        require(bridge[_typeId] == msg.sender, "E201");
        require(_to != address(0x0), "E301");

        uint256 _tokenTypeId = _tokenId & TYPE_MASK;
        require(_tokenTypeId == _typeId, "E203");

        _safeTransferFrom(_from, _to, _tokenId, _value);
        return true;
    }

    function _createErc20Bridge(uint256 _typeId, string memory _name, string memory _symbol, uint8 _decimals) internal returns (address) {
        require(bridge[_typeId] == address(0), "E202");

        address newBridge = _createClone(templateErc20);
        ERC20Bridge(newBridge).setup(_typeId, _name, _symbol, _decimals);
        bridge[_typeId] = newBridge;

        emit NewBridge(_typeId, newBridge);
        return newBridge;
    }

    function _createErc721Bridge(uint256 _typeId, string memory _name, string memory _symbol) internal returns (address) {
        require(bridge[_typeId] == address(0), "E202");

        address newBridge = _createClone(templateErc721);
        ERC721Bridge(newBridge).setup(_typeId, _name, _symbol);
        bridge[_typeId] = newBridge;

        emit NewBridge(_typeId, newBridge);
        return newBridge;
    }

    // see: https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1167.md
    function _createClone(address target) internal returns (address result) {
        bytes20 targetBytes = bytes20(target);
        assembly {
            let clone := mload(0x40)
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone, 0x14), targetBytes)
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            result := create(0, clone, 0x37)
        }
    }
}

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
        require(typeId == 0 && address(entity) == address(0), "E206");
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
        require(entity.transferFromBridged(typeId, msg.sender, _recipient, typeId, _amount), "E208");
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
        require(entity.transferFromBridged(typeId, _sender, _recipient, typeId, _amount), "E208");
        emit Transfer(_sender, _recipient, _amount);
        return true;
    }
}

contract ERC721Bridge {
    BridgedERC1155 public entity;

    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 private constant ERC721_RECEIVED = 0x150b7a02;
    uint256 public typeId;
    string public name;
    string public symbol;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function setup(uint256 _typeId, string memory _name, string memory _symbol) public {
        require(typeId == 0 && address(entity) == address(0), "E206");
        entity = BridgedERC1155(msg.sender);
        typeId = _typeId;
        name = _name;
        symbol = _symbol;
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        require(interfaceId != 0xffffffff, "E211");
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
        require((_operator == _from) || entity.isApprovedForAll(_from, _operator), "E207");
        require(entity.transferFromBridged(typeId, _from, _to, _tokenId, 1), "E209");
        emit Transfer(_from, _to, _tokenId);
    }

    function _safeTransferFrom(address _operator, address _from, address _to, uint256 _tokenId, bytes memory _data) internal {
        require((_operator == _from) || entity.isApprovedForAll(_from, _operator), "E207");
        require(entity.transferFromBridged(typeId, _from, _to, _tokenId, 1), "E209");
        require(_checkOnERC721Received(_operator, _from, _to, _tokenId, _data), "E210");
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

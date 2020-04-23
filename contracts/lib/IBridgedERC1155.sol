// BridgedERC1155.sol - Charged Particles
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

pragma solidity ^0.5.16;

contract IBridgedERC1155 {
    event NewBridge(uint256 indexed _typeId, address indexed _bridge);

    function ownerOf(uint256 _tokenId) public view returns (address);
    function balanceOf(address _tokenOwner, uint256 _typeId) public view returns (uint256);
    function totalSupply(uint256 _typeId) public view returns (uint256);

    function getApproved(uint256 _tokenId) public view returns (address);
    function isApprovedForAll(address _tokenOwner, address _operator) public view returns (bool isOperator);

    function uri(uint256 _id) public view returns (string memory);
    function tokenOfOwnerByIndex(uint256 _typeId, address _owner, uint256 _index) public view returns (uint256);
    function tokenByIndex(uint256 _typeId, uint256 _index) public view returns (uint256);

    function approveBridged(uint256 _typeId, address _from, address _operator, uint256 _tokenId) public;
    function setApprovalForAllBridged(uint256 _typeId, address _from, address _operator, bool _approved) public;
    function transferFromBridged(uint256 _typeId, address _from, address _to, uint256 _tokenId, uint256 _value) public returns (bool);
}

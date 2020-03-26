// IChargedParticlesERC1155.sol -- Token Manager
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

pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

/**
 * @notice Interface for Charged Particles ERC1155 - Token Manager
 */
contract IChargedParticlesERC1155 {
    function isNonFungible(uint256 _id) public pure returns(bool);
    function isFungible(uint256 _id) public pure returns(bool);
    function getNonFungibleIndex(uint256 _id) public pure returns(uint256);
    function getNonFungibleBaseType(uint256 _id) public pure returns(uint256);
    function isNonFungibleBaseType(uint256 _id) public pure returns(bool);
    function isNonFungibleItem(uint256 _id) public pure returns(bool);

    function createType(string memory _uri, bool isNF) public returns (uint256);
    function mint(address _to, uint256 _typeId, uint256 _amount, string memory _uri, bytes memory _data) public returns (uint256);
    function mintBatch(address _to, uint256[] memory _types, uint256[] memory _amounts, string[] memory _URIs, bytes memory _data) public returns (uint256[] memory);
    function burn(address _from, uint256 _tokenId, uint256 _amount) public;
    function burnBatch(address _from, uint256[] memory _tokenIds, uint256[] memory _amounts) public;
    function createErc20Bridge(uint256 _typeId, string memory _name, string memory _symbol, uint8 _decimals) public returns (address);
    function createErc721Bridge(uint256 _typeId, string memory _name, string memory _symbol) public returns (address);

    function uri(uint256 _id) public view returns (string memory);
    function totalSupply(uint256 _typeId) public view returns (uint256);
    function totalMinted(uint256 _typeId) public view returns (uint256);
    function ownerOf(uint256 _tokenId) public view returns (address);
    function balanceOf(address _tokenOwner, uint256 _typeId) public view returns (uint256);
    function balanceOfBatch(address[] memory _owners, uint256[] memory _typeIds) public view returns (uint256[] memory);
}

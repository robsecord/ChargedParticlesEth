// SPDX-License-Identifier: MIT

// IChargedParticlesTokenManager.sol -- Token Manager
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

pragma solidity 0.6.10;
pragma experimental ABIEncoderV2;

/**
 * @notice Interface for Charged Particles ERC1155 - Token Manager
 */
interface IChargedParticlesTokenManager {
    function isNonFungible(uint256 _id) external pure returns(bool);
    function isFungible(uint256 _id) external pure returns(bool);
    function getNonFungibleIndex(uint256 _id) external pure returns(uint256);
    function getNonFungibleBaseType(uint256 _id) external pure returns(uint256);
    function isNonFungibleBaseType(uint256 _id) external pure returns(bool);
    function isNonFungibleItem(uint256 _id) external pure returns(bool);

    function createType(string calldata _uri, bool isNF) external returns (uint256);

    function mint(
        address _to, 
        uint256 _typeId, 
        uint256 _amount, 
        string calldata _uri, 
        bytes calldata _data
    ) external returns (uint256);
    
    // function mintBatch(
    //     address _to, 
    //     uint256[] calldata _types, 
    //     uint256[] calldata _amounts, 
    //     string[] calldata _uris, 
    //     bytes calldata _data
    // ) external returns (uint256[] memory);
    
    function burn(
        address _from, 
        uint256 _tokenId, 
        uint256 _amount
    ) external;
    
    // function burnBatch(
    //     address _from, 
    //     uint256[] calldata _tokenIds, 
    //     uint256[] calldata _amounts
    // ) external;
    
    function createErc20Bridge(uint256 _typeId, string calldata _name, string calldata _symbol, uint8 _decimals) external returns (address);
    function createErc721Bridge(uint256 _typeId, string calldata _name, string calldata _symbol) external returns (address);

    function uri(uint256 _id) external view returns (string memory);
    function totalSupply(uint256 _typeId) external view returns (uint256);
    function totalMinted(uint256 _typeId) external view returns (uint256);
    function ownerOf(uint256 _tokenId) external view returns (address);
    function balanceOf(address _tokenOwner, uint256 _typeId) external view returns (uint256);
    // function balanceOfBatch(address[] calldata _owners, uint256[] calldata _typeIds) external view returns (uint256[] memory);
}

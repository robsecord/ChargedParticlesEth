// ChargedParticlesERC1155.sol -- Charged Particles
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

import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "./lib/BridgedERC1155.sol";


/**
 * @notice Charged Particles ERC1155 - Token Manager
 */
contract ChargedParticlesERC1155 is Initializable, Ownable, ReentrancyGuard, BridgedERC1155 {
    using SafeMath for uint256;
    using Address for address payable;

    /***********************************|
    |     Variables/Events/Modifiers    |
    |__________________________________*/

    // Address to the Charged Particles Controller Contract
    address chargedParticles;

    // Throws if called by any account other than the Charged Particles contract.
    modifier onlyChargedParticles() {
        require(msg.sender == chargedParticles, "Caller is not ChargedParticles");
        _;
    }


    /***********************************|
    |          Initialization           |
    |__________________________________*/

    function initialize(address sender) public initializer {
        Ownable.initialize(sender);
        ReentrancyGuard.initialize();
        BridgedERC1155.initialize();
    }


    /***********************************|
    |            Public Read            |
    |__________________________________*/

    function isNonFungible(uint256 _id) public pure returns(bool) {
        return _id & TYPE_NF_BIT == TYPE_NF_BIT;
    }
    function isFungible(uint256 _id) public pure returns(bool) {
        return _id & TYPE_NF_BIT == 0;
    }
    function getNonFungibleIndex(uint256 _id) public pure returns(uint256) {
        return _id & NF_INDEX_MASK;
    }
    function getNonFungibleBaseType(uint256 _id) public pure returns(uint256) {
        return _id & TYPE_MASK;
    }
    function isNonFungibleBaseType(uint256 _id) public pure returns(bool) {
        return (_id & TYPE_NF_BIT == TYPE_NF_BIT) && (_id & NF_INDEX_MASK == 0);
    }
    function isNonFungibleItem(uint256 _id) public pure returns(bool) {
        return (_id & TYPE_NF_BIT == TYPE_NF_BIT) && (_id & NF_INDEX_MASK != 0);
    }


    /***********************************|
    |      Only Charged Particles       |
    |__________________________________*/

    /**
     * @dev Creates a new Particle Type, either FT or NFT
     */
    function createType(
        string memory _uri,
        bool isNF
    )
        public
        onlyChargedParticles
        returns (uint256)
    {
        return _createType(_uri, isNF);
    }

    /**
     * @dev Mints a new Particle, either FT or NFT
     */
    function mint(
        address _to,
        uint256 _typeId,
        uint256 _amount,
        string memory _uri,
        bytes memory _data
    )
        public
        onlyChargedParticles
        returns (uint256)
    {
        return _mint(_to, _typeId, _amount, _uri, _data);
    }

    /**
     * @dev Mints a Batch of new Particles, either FT or NFT
     */
    function mintBatch(
        address _to,
        uint256[] memory _types,
        uint256[] memory _amounts,
        string[] memory _URIs,
        bytes memory _data
    )
        public
        onlyChargedParticles
        returns (uint256[] memory)
    {
        return mintBatch(_to, _types, _amounts, _URIs, _data);
    }

    /**
     * @dev Burns an existing Particle, either FT or NFT
     */
    function burn(
        address _from,
        uint256 _tokenId,
        uint256 _amount
    )
        public
        onlyChargedParticles
    {
        _burn(_from, _tokenId, _amount);
    }

    /**
     * @dev Burns a Batch of existing Particles, either FT or NFT
     */
    function burnBatch(
        address _from,
        uint256[] memory _tokenIds,
        uint256[] memory _amounts
    )
        public
        onlyChargedParticles
    {
        _burnBatch(_from, _tokenIds, _amounts);
    }

    /**
     * @dev Creates an ERC20 Token Bridge Contract to interface with the ERC1155 Contract
     */
    function createErc20Bridge(
        uint256 _typeId,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    )
        public
        onlyChargedParticles
        returns (address)
    {
        return _createErc20Bridge(_typeId, _name, _symbol, _decimals);
    }

    /**
     * @dev Creates an ERC721 Token Bridge Contract to interface with the ERC1155 Contract
     */
    function createErc721Bridge(
        uint256 _typeId,
        string memory _name,
        string memory _symbol
    )
        public
        onlyChargedParticles
        returns (address)
    {
        return _createErc721Bridge(_typeId, _name, _symbol);
    }


    /***********************************|
    |          Only Admin/DAO           |
    |__________________________________*/

    /**
     * @dev Sets the Address to the Charged Particles Controller Contract
     */
    function setChargedParticles(address _chargedParticles) public onlyOwner {
        chargedParticles = _chargedParticles;
    }
}

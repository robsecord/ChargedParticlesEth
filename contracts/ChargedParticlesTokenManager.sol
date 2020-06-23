// SPDX-License-Identifier: MIT

// ChargedParticlesTokenManager.sol -- Charged Particles
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

import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";

import "./lib/BridgedERC1155.sol";


/**
 * @notice Charged Particles ERC1155 - Token Manager
 */
contract ChargedParticlesTokenManager is Initializable, AccessControlUpgradeSafe, BridgedERC1155 {
    using SafeMath for uint256;
    using Address for address payable;

    // Integrated Controller Contracts
    mapping (address => bool) internal fusedParticles;
    // mapping (address => mapping (uint256 => bool)) internal fusedParticleTypes;
    mapping (uint256 => address) internal fusedParticleTypes;

    // Contract Version
    bytes16 public version;

    // Throws if called by any account other than a Fused-Particle contract.
    modifier onlyFusedParticles() {
        require(fusedParticles[msg.sender], "CPTM: ONLY_FUSED");
        _;
    }

    // Throws if called by any account other than the Charged Particles DAO contract.
    modifier onlyDao() {
        require(hasRole(ROLE_DAO_GOV, msg.sender), "CPTM: INVALID_DAO");
        _;
    }


    /***********************************|
    |          Initialization           |
    |__________________________________*/

    function initialize() public override initializer {
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ROLE_DAO_GOV, msg.sender);
        BridgedERC1155.initialize();
        version = "v0.4.1";
    }


    /***********************************|
    |            Public Read            |
    |__________________________________*/

    function isNonFungible(uint256 _id) external override pure returns(bool) {
        return _id & TYPE_NF_BIT == TYPE_NF_BIT;
    }
    function isFungible(uint256 _id) external override pure returns(bool) {
        return _id & TYPE_NF_BIT == 0;
    }
    function getNonFungibleIndex(uint256 _id) external override pure returns(uint256) {
        return _id & NF_INDEX_MASK;
    }
    function getNonFungibleBaseType(uint256 _id) external override pure returns(uint256) {
        return _id & TYPE_MASK;
    }
    function isNonFungibleBaseType(uint256 _id) external override pure returns(bool) {
        return (_id & TYPE_NF_BIT == TYPE_NF_BIT) && (_id & NF_INDEX_MASK == 0);
    }
    function isNonFungibleItem(uint256 _id) external override pure returns(bool) {
        return (_id & TYPE_NF_BIT == TYPE_NF_BIT) && (_id & NF_INDEX_MASK != 0);
    }

    /**
     * @notice Gets the Creator of a Token Type
     * @param _typeId     The Type ID of the Token
     * @return  The Creator Address
     */
    function getTypeCreator(uint256 _typeId) external view returns (address) {
        return fusedParticleTypes[_typeId];
    }


    /***********************************|
    |      Only Charged Particles       |
    |__________________________________*/

    /**
     * @dev Creates a new Particle Type, either FT or NFT
     */
    function createType(
        string calldata _uri,
        bool isNF
    )
        external
        override
        onlyFusedParticles
        returns (uint256)
    {
        uint256 _typeId = _createType(_uri, isNF);
        fusedParticleTypes[_typeId] = msg.sender;
        return _typeId;
    }

    /**
     * @dev Mints a new Particle, either FT or NFT
     */
    function mint(
        address _to,
        uint256 _typeId,
        uint256 _amount,
        string calldata _uri,
        bytes calldata _data
    )
        external
        override
        onlyFusedParticles
        returns (uint256)
    {
        require(fusedParticleTypes[_typeId] == msg.sender, "CPTM: ONLY_FUSED");
        return _mint(_to, _typeId, _amount, _uri, _data);
    }

    /**
     * @dev Mints a Batch of new Particles, either FT or NFT
     */
    // function mintBatch(
    //     address _to,
    //     uint256[] calldata _types,
    //     uint256[] calldata _amounts,
    //     string[] calldata _URIs,
    //     bytes calldata _data
    // )
    //     external
    //     override
    //     onlyFusedParticles
    //     returns (uint256[] memory)
    // {
    //     for (uint256 i = 0; i < _types.length; i++) {
    //         require(fusedParticleTypes[_types[i]] == msg.sender, "CPTM: ONLY_FUSED");
    //     }
    //     return _mintBatch(_to, _types, _amounts, _URIs, _data);
    // }

    /**
     * @dev Burns an existing Particle, either FT or NFT
     */
    function burn(
        address _from,
        uint256 _tokenId,
        uint256 _amount
    )
        external
        override
        onlyFusedParticles
    {
        uint256 _typeId = _tokenId;
        if (_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) {
            _typeId = _tokenId & TYPE_MASK;
        }
        require(fusedParticleTypes[_typeId] == msg.sender, "CPTM: ONLY_FUSED");
        _burn(_from, _tokenId, _amount);
    }

    /**
     * @dev Burns a Batch of existing Particles, either FT or NFT
     */
    // function burnBatch(
    //     address _from,
    //     uint256[] calldata _tokenIds,
    //     uint256[] calldata _amounts
    // )
    //     external
    //     override
    //     onlyFusedParticles
    // {
    //     for (uint256 i = 0; i < _tokenIds.length; i++) {
    //         uint256 _typeId = _tokenIds[i];
    //         if (_typeId & TYPE_NF_BIT == TYPE_NF_BIT) {
    //             _typeId = _typeId & TYPE_MASK;
    //         }
    //         require(fusedParticleTypes[_typeId] == msg.sender, "CPTM: ONLY_FUSED");
    //     }
    //     _burnBatch(_from, _tokenIds, _amounts);
    // }

    /**
     * @dev Creates an ERC20 Token Bridge Contract to interface with the ERC1155 Contract
     */
    function createErc20Bridge(
        uint256 _typeId,
        string calldata _name,
        string calldata _symbol,
        uint8 _decimals
    )
        external
        override
        onlyFusedParticles
        returns (address)
    {
        require(fusedParticleTypes[_typeId] == msg.sender, "CPTM: ONLY_FUSED");
        return _createErc20Bridge(_typeId, _name, _symbol, _decimals);
    }

    /**
     * @dev Creates an ERC721 Token Bridge Contract to interface with the ERC1155 Contract
     */
    function createErc721Bridge(
        uint256 _typeId,
        string calldata _name,
        string calldata _symbol
    )
        external
        override
        onlyFusedParticles
        returns (address)
    {
        require(fusedParticleTypes[_typeId] == msg.sender, "CPTM: ONLY_FUSED");
        return _createErc721Bridge(_typeId, _name, _symbol);
    }


    /***********************************|
    |          Only Admin/DAO           |
    |__________________________________*/

    /**
     * @dev Adds an Integration Controller Contract as a Fused Particle to allow Creating/Minting
     */
    function setFusedParticleState(address _particleAddress, bool _fusedState) external onlyDao {
        fusedParticles[_particleAddress] = _fusedState;
    }
}

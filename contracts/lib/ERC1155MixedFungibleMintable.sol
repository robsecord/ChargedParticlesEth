pragma solidity ^0.5.13;

import "./ERC1155MixedFungible.sol";


contract ERC1155MixedFungibleMintable is ERC1155MixedFungible {

    uint256 internal nonce;
    mapping (uint256 => uint256) internal maxIndex;


    //
    // Create Types (ERC20 & ERC721)
    //

    function _createType(string memory _uri, bool _isNF) internal returns (uint256 _type) {
        _type = (++nonce << 128);

        if (_isNF) {
            _type = _type | TYPE_NF_BIT;
        }

        // emit a Transfer event with Create semantic to help with discovery.
        emit TransferSingle(msg.sender, address(0x0), address(0x0), _type, 0);

        if (bytes(_uri).length > 0) {
            emit URI(_uri, _type);
        }
    }

    //
    // Fungible (ERC20)
    //

    function _mintFungible(address _to, uint256 _type, uint256 _amount, bytes memory _data) internal {
        require(_type & TYPE_NF_BIT == 0, "ERC1155MixedFungibleMintable#_mintFungible: INVALID_TYPE");
        _mint(_to, _type, _amount, _data);
    }

    function _mintFungibleBatch(address _to, uint256[] memory _types, uint256[] memory _amounts, bytes memory _data) internal {
        for (uint256 i = 0; i < _types.length; ++i) {
            require(_types[i] & TYPE_NF_BIT == 0, "ERC1155MixedFungibleMintable#_mintFungibleBatch: INVALID_TYPE");
        }
        _batchMint(_to, _types, _amounts, _data);
    }

    function _burnFungible(address _from, uint256 _type, uint256 _amount) internal {
        require(_type & TYPE_NF_BIT == 0, "ERC1155MixedFungibleMintable#_burnFungible: INVALID_TYPE");
        require(balanceOf(_from, _type) >= _amount, "ERC1155MixedFungibleMintable#_burnFungible: INSUFFICIENT_BALANCE");
        _burn(_from, _type, _amount);
    }

    function _burnFungibleBatch(address _from, uint256[] memory _types, uint256[] memory _amounts) internal {
        for (uint256 i = 0; i < _types.length; ++i) {
            require(_types[i] & TYPE_NF_BIT == 0, "ERC1155MixedFungibleMintable#_burnFungibleBatch: INVALID_TYPE");
            require(balanceOf(_from, _types[i]) >= _amounts[i], "ERC1155MixedFungibleMintable#_burnFungibleBatch: INSUFFICIENT_BALANCE");
        }
        _batchBurn(_from, _types, _amounts);
    }

    //
    // Non-Fungible (ERC721)
    //

    function _mintNonFungible(address _to, uint256 _type, bytes memory _data) internal returns (uint256 tokenId) {
        require(_type & TYPE_NF_BIT == TYPE_NF_BIT, "ERC1155MixedFungibleMintable#_mintNonFungible: INVALID_TYPE");

        // Index are 1-based.
        uint256 index = maxIndex[_type] + 1;
        maxIndex[_type] = index;

        tokenId  = _type | index;
        nfOwners[tokenId] = _to;

        emit TransferSingle(msg.sender, address(0x0), _to, tokenId, 1);
        _callonERC1155Received(address(0x0), _to, tokenId, 1, _data);
    }

    function _mintNonFungibleBatch(address _to, uint256[] memory _types, bytes memory _data) internal returns (uint256[] memory) {
        uint256[] memory _tokenIds = new uint256[](_types.length);
        uint256[] memory _amounts = new uint256[](_types.length);

        for (uint256 i = 0; i < _types.length; ++i) {
            uint256 _type = _types[i];
            require(_type & TYPE_NF_BIT == TYPE_NF_BIT, "ERC1155MixedFungibleMintable#_mintNonFungibleBatch: INVALID_TYPE");

            // Index are 1-based.
            uint256 _index = maxIndex[_type] + 1;
            maxIndex[_type] = _index;

            uint256 _tokenId  = _type | _index;
            nfOwners[_tokenId] = _to;
            _tokenIds[i] = _tokenId;
            _amounts[i] = 1;
        }

        emit TransferBatch(msg.sender, address(0x0), _to, _tokenIds, _amounts);
        _callonERC1155BatchReceived(address(0x0), _to, _tokenIds, _amounts, _data);
        return _tokenIds;
    }

    function _burnNonFungible(address _from, uint256 _tokenId) internal {
        require((_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) && (_tokenId & NF_INDEX_MASK != 0), "ERC1155MixedFungibleMintable#_burnNonFungible: INVALID_TYPE");
        require(ownerOf(_tokenId) == _from, "ERC1155MixedFungibleMintable#_burnNonFungible: INVALID_OWNER");

        nfOwners[_tokenId] = address(0x0);
        emit TransferSingle(msg.sender, _from, address(0x0), _tokenId, 1);
    }

    function _burnNonFungibleBatch(address _from, uint256[] memory _tokenIds) internal {
        uint256[] memory _amounts = new uint256[](_tokenIds.length);

        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            uint256 _tokenId = _tokenIds[i];
            require((_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) && (_tokenId & NF_INDEX_MASK != 0), "ERC1155MixedFungibleMintable#_burnNonFungibleBatch: INVALID_TYPE");
            require(ownerOf(_tokenId) == _from, "ERC1155MixedFungibleMintable#_burnNonFungibleBatch: INVALID_OWNER");

            nfOwners[_tokenId] = address(0x0);
            _amounts[i] = 1;
        }
        emit TransferBatch(msg.sender, _from, address(0x0), _tokenIds, _amounts);
    }
}

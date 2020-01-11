pragma solidity ^0.5.13;

import "multi-token-standard/contracts/tokens/ERC1155PackedBalance/ERC1155PackedBalance.sol";
import "multi-token-standard/contracts/tokens/ERC1155PackedBalance/ERC1155MintBurnPackedBalance.sol";

/**
    @dev Extension to ERC1155 for Mixed Fungible and Non-Fungible Items support
    The main benefit is sharing of common type information, just like you do when
    creating a fungible id.
*/
contract ERC1155MixedFungible is ERC1155PackedBalance, ERC1155MintBurnPackedBalance {

    // Use a split bit implementation.
    // Store the type in the upper 128 bits..
    uint256 constant internal TYPE_MASK = uint256(uint128(~0)) << 128;

    // ..and the non-fungible index in the lower 128
    uint256 constant internal NF_INDEX_MASK = uint128(~0);

    // The top bit is a flag to tell if this is a NFI.
    uint256 constant internal TYPE_NF_BIT = 1 << 255;

    mapping (uint256 => address) internal nfOwners;


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


    function ownerOf(uint256 _id) public view returns (address) {
        require(_id & TYPE_NF_BIT == TYPE_NF_BIT, "Token is not an Non-Fungible token");
        return nfOwners[_id];
    }

    function balanceOf(address _owner, uint256 _id) public view returns (uint256) {
        if ((_id & TYPE_NF_BIT == TYPE_NF_BIT) && (_id & NF_INDEX_MASK != 0)) {  // Non-Fungible Item
            return nfOwners[_id] == _owner ? 1 : 0;
        }
        return super.balanceOf(_owner, _id);
    }

    function balanceOfBatch(address[] memory _owners, uint256[] memory _ids) public view returns (uint256[] memory) {
        require(_owners.length == _ids.length);

        uint256[] memory balances = new uint256[](_owners.length);
        for (uint256 i = 0; i < _owners.length; ++i) {
            uint256 id = _ids[i];
            if ((id & TYPE_NF_BIT == TYPE_NF_BIT) && (id & NF_INDEX_MASK != 0)) { // Non-Fungible Item
                balances[i] = nfOwners[id] == _owners[i] ? 1 : 0;
            } else {
                balances[i] = super.balanceOf(_owners[i], id);
            }
        }

        return balances;
    }


    /**
     * @notice Transfers amount amount of an _id from the _from address to the _to address specified
     * @param _from    Source address
     * @param _to      Target address
     * @param _id      ID of the token type
     * @param _amount  Transfered amount
     * @param _data    Additional data with no specified format, sent in call to `_to`
     */
    function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _amount, bytes memory _data) public {
        // Requirements
        require((msg.sender == _from) || isApprovedForAll(_from, msg.sender), "ERC1155MixedFungible#safeTransferFrom: INVALID_OPERATOR");
        require(_to != address(0),"ERC1155MixedFungible#safeTransferFrom: INVALID_RECIPIENT");
        // require(_amount <= balances);  Not necessary since checked with _viewUpdateBinValue() checks

        if (_id & TYPE_NF_BIT == TYPE_NF_BIT) { // Non-Fungible
            _amount = 1;
            _safeNfTransferFrom(_from, _to, _id);
        } else {
            _safeTransferFrom(_from, _to, _id, _amount);
        }
        _callonERC1155Received(_from, _to, _id, _amount, _data);
    }

    /**
     * @notice Send multiple types of Tokens from the _from address to the _to address (with safety call)
     * @dev Arrays should be sorted so that all ids in a same storage slot are adjacent (more efficient)
     * @param _from     Source addresses
     * @param _to       Target addresses
     * @param _ids      IDs of each token type
     * @param _amounts  Transfer amounts per token type
     * @param _data     Additional data with no specified format, sent in call to `_to`
     */
    function safeBatchTransferFrom(address _from, address _to, uint256[] memory _ids, uint256[] memory _amounts, bytes memory _data) public {
        // Requirements
        require((msg.sender == _from) || isApprovedForAll(_from, msg.sender), "ERC1155MixedFungible#safeBatchTransferFrom: INVALID_OPERATOR");
        require(_to != address(0),"ERC1155MixedFungible#safeBatchTransferFrom: INVALID_RECIPIENT");

        _safeMixedBatchTransferFrom(_from, _to, _ids, _amounts);
        _callonERC1155BatchReceived(_from, _to, _ids, _amounts, _data);
    }

    /**
     * @notice Transfers amount amount of an _id from the _from address to the _to address specified
     * @param _from    Source address
     * @param _to      Target address
     * @param _id      ID of the token type
     */
    function _safeNfTransferFrom(address _from, address _to, uint256 _id) internal {
        require(nfOwners[_id] == _from);
        nfOwners[_id] = _to;

        // Emit event
        emit TransferSingle(msg.sender, _from, _to, _id, 1);
    }

    /**
     * @notice Send multiple types of Tokens from the _from address to the _to address (with safety call)
     * @dev Arrays should be sorted so that all ids in a same storage slot are adjacent (more efficient)
     * @param _from     Source addresses
     * @param _to       Target addresses
     * @param _ids      IDs of each token type
     * @param _amounts  Transfer amounts per token type
     */
    function _safeMixedBatchTransferFrom(address _from, address _to, uint256[] memory _ids, uint256[] memory _amounts) internal {
        require(_ids.length == _amounts.length, "ERC1155MixedFungible#_safeMixedBatchTransferFrom: INVALID_ARRAYS_LENGTH");

        uint256 i;
        uint256 id;
        uint256 amount;
        uint256 ft = 0;
        uint256 nft = 0;
        for (i = 0; i < _ids.length; ++i) {
            id = _ids[i];
            if (id & TYPE_NF_BIT == TYPE_NF_BIT) { // Non-Fungible
                nft++;
            } else {
                ft++;
            }
        }

        uint256[] memory fungibles = new uint256[](ft);
        uint256[] memory fungibleAmounts = new uint256[](ft);

        uint256[] memory nonFungibles = new uint256[](nft);
        uint256[] memory nonFungibleAmounts = new uint256[](nft);

        ft = 0;
        nft = 0;
        for (i = 0; i < _ids.length; ++i) {
            id = _ids[i];
            amount = _amounts[i];

            if (id & TYPE_NF_BIT == TYPE_NF_BIT) { // Non-Fungible
                require(nfOwners[id] == _from);
                nfOwners[id] = _to;
                nonFungibles[nft] = id;
                nonFungibleAmounts[nft] = 1;
                nft++;
            } else {
                fungibles[ft] = id;
                fungibleAmounts[ft] = amount;
                ft++;
            }
        }

        if (ft > 0) {
            // Emits Fungible Batch Event
            _safeBatchTransferFrom(_from, _to, fungibles, fungibleAmounts);
        }

        if (nft > 0) {
            // NonFungible Batch Event
            emit TransferBatch(msg.sender, _from, _to, nonFungibles, nonFungibleAmounts);
        }
    }
}

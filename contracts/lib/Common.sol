// SPDX-License-Identifier: MIT

// Common.sol -- Charged Particles
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


/**
 * @notice Common Vars for Charged Particles
 */
contract Common {
    
    uint256 constant internal DEPOSIT_FEE_MODIFIER = 1e4;   // 10000  (100%)
    uint256 constant internal MAX_CUSTOM_DEPOSIT_FEE = 5e3; // 5000   (50%)
    uint256 constant internal MIN_DEPOSIT_FEE = 1e6;        // 1000000 (0.000000000001 ETH  or  1000000 WEI)

    bytes32 constant public ROLE_DAO_GOV = keccak256("ROLE_DAO_GOV");
    bytes32 constant public ROLE_MAINTAINER = keccak256("ROLE_MAINTAINER");

    // Fungibility-Type Flags
    uint256 constant internal TYPE_MASK = uint256(uint128(~0)) << 128;  
    uint256 constant internal NF_INDEX_MASK = uint128(~0);
    uint256 constant internal TYPE_NF_BIT = 1 << 255;

    // Interface Signatures
    bytes4 constant internal INTERFACE_SIGNATURE_ERC165 = 0x01ffc9a7;
    bytes4 constant internal INTERFACE_SIGNATURE_ERC721 = 0x80ac58cd;
    bytes4 constant internal INTERFACE_SIGNATURE_ERC1155 = 0xd9b67a26;
    bytes4 constant internal ERC1155_RECEIVED_VALUE = 0xf23a6e61;
    bytes4 constant internal ERC1155_BATCH_RECEIVED_VALUE = 0xbc197c81;

}

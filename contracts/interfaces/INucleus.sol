// SPDX-License-Identifier: MIT

// INucleus.sol -- Charged Particles
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

pragma solidity ^0.6.10;

/**
 * @title Particle Nucleus interface
 * @dev The base layer for underlying assets attached to Charged Particles
 */
interface INucleus {
    // Balance in Asset Token
    function assetBalance(address _account) external returns (uint);

    // Balance in Interest-bearing Token
    function interestBalance(address _account) external returns (uint);

    // Get amount of Asset Token equivalent to Interest Token
    function toAsset(uint _interestAmount) external returns (uint);

    // Get amount of Interest Token equivalent to Asset Token
    function toInterest(uint _assetAmount) external returns (uint);

    // Deposit Asset Token and receive Interest-bearing Token
    function depositAsset(address _account, uint _assetAmount) external;

    // Withdraw amount specified in Interest-bearing Token
    function withdrawInterest(address _account, uint _interestAmount) external;

    // Withdraw amount specified in Asset Token
    function withdrawAsset(address _account, uint _assetAmount) external returns (uint);
}

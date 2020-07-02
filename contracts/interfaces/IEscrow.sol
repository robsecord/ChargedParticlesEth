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
 * @title Particle Escrow interface
 * @dev The base escrow for underlying assets attached to Charged Particles
 */
interface IEscrow {
    //
    // Must override:
    //
    function isPaused() external view returns (bool);
    function baseParticleMass(uint256 _tokenUuid) external view returns (uint256);
    function currentParticleCharge(uint256 _tokenUuid) external returns (uint256);
    function energizeParticle(address _contractAddress, uint256 _tokenUuid, uint256 _assetAmount) external returns (uint256);

    function dischargeParticle(address _receiver, uint256 _tokenUuid) external returns (uint256, uint256);
    function dischargeParticleAmount(address _receiver, uint256 _tokenUuid, uint256 _assetAmount) external returns (uint256, uint256);

    function releaseParticle(address _receiver, uint256 _tokenUuid) external returns (uint256);

    function withdrawFees(address _contractAddress, address _receiver) external returns (uint256);

    // 
    // Inherited from EscrowBase:
    //
    function getAssetTokenAddress() external view returns (address);
    function getInterestTokenAddress() external view returns (address);
}

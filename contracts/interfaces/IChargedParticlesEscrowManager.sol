// SPDX-License-Identifier: MIT

// IChargedParticlesEscrow.sol -- Interest-bearing NFTs
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
 * @notice Interface for the Charged Particles Escrow
 */
interface IChargedParticlesEscrowManager {

    function isAssetPairEnabled(bytes16 _assetPairId) external view returns (bool);
    function getAssetPairsCount() external view returns (uint);
    function getAssetPairByIndex(uint _index) external view returns (bytes16);
    function getAssetTokenEscrow(bytes16 _assetPairId) external view returns (address);
    function getAssetTokenAddress(bytes16 _assetPairId) external view returns (address);
    function getInterestTokenAddress(bytes16 _assetPairId) external view returns (address);

    function getUUID(address _contractAddress, uint256 _id) external pure returns (uint256);
    function getAssetMinDeposit(address _contractAddress) external view returns (uint256);
    function getAssetMaxDeposit(address _contractAddress) external view returns (uint256);
    function getFeesForDeposit(address _contractAddress, uint256 _interestTokenAmount) external view returns (uint256, uint256);
    function getFeeForDeposit(address _contractAddress, uint256 _interestTokenAmount) external view returns (uint256);

    function setDischargeApproval(address _contractAddress, uint256 _tokenId, address _operator) external;
    function isApprovedForDischarge(address _contractAddress, uint256 _tokenId, address _operator) external view returns (bool);

    function baseParticleMass(address _contractAddress, uint256 _tokenId, bytes16 _assetPairId) external view returns (uint256);
    function currentParticleCharge(address _contractAddress, uint256 _tokenId, bytes16 _assetPairId) external returns (uint256);

    /***********************************|
    |     Register Contract Settings    |
    |(For External Contract Integration)|
    |__________________________________*/

    function isContractOwner(address _account, address _contract) external view returns (bool);
    function registerContractType(address _contractAddress) external;
    function registerContractSetting_ReleaseBurn(address _contractAddress, bool _releaseRequiresBurn) external;
    function registerContractSetting_AssetPair(address _contractAddress, bytes16 _assetPairId) external;
    function registerContractSetting_DepositFee(address _contractAddress, uint256 _depositFee) external;
    function registerContractSetting_MinDeposit(address _contractAddress, uint256 _minDeposit) external;
    function registerContractSetting_MaxDeposit(address _contractAddress, uint256 _maxDeposit) external;

    function withdrawContractFees(address _contractAddress, address _receiver, bytes16 _assetPairId) external;

    /***********************************|
    |          Particle Charge          |
    |__________________________________*/

    function energizeParticle(address _contractAddress, uint256 _tokenId, bytes16 _assetPairId, uint256 _assetAmount) external returns (uint256);

    function dischargeParticle(address _receiver, address _contractAddress, uint256 _tokenId, bytes16 _assetPairId) external returns (uint256, uint256);
    function dischargeParticleAmount(address _receiver, address _contractAddress, uint256 _tokenId, bytes16 _assetPairId, uint256 _assetAmount) external returns (uint256, uint256);

    function releaseParticle(address _receiver, address _contractAddress, uint256 _tokenId, bytes16 _assetPairId) external returns (uint256);
    function finalizeRelease(address _receiver, address _contractAddress, uint256 _tokenId, bytes16 _assetPairId) external returns (uint256);
}

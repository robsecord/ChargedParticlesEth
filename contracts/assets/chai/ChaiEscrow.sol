// SPDX-License-Identifier: MIT

// ChargedParticlesEscrowManager.sol -- Charged Particles
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

import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "../../lib/EscrowBase.sol";

/**
 * @notice Chai-Escrow for Charged Particles
 */
contract ChaiEscrow is EscrowBase {
    using SafeMath for uint256;

    /**
     * @notice Gets the Amount of Asset Tokens that have been Deposited into the Particle
     *    representing the Mass of the Particle.
     * @param _tokenUuid        The ID of the Token within the External Contract
     * @return  The Amount of underlying Assets held within the Token
     */
    function baseParticleMass(uint256 _tokenUuid) external override view returns (uint256) {
        return _baseParticleMass(_tokenUuid);
    }

    /**
     * @notice Gets the amount of Interest that the Particle has generated representing
     *    the Charge of the Particle
     * @param _tokenUuid        The ID of the Token within the External Contract
     * @return  The amount of interest the Token has generated (in Asset Token)
     */
    function currentParticleCharge(uint256 _tokenUuid) external override returns (uint256) {
        return _currentParticleCharge(_tokenUuid);
    }

    /***********************************|
    |        Energize Particles         |
    |__________________________________*/

    /**
     * @notice Fund Particle with Asset Token
     *    Must be called by the Owner providing the Asset
     *    Owner must Approve THIS contract as Operator of Asset
     *
     * NOTE: DO NOT Energize an ERC20 Token, as anyone who holds any amount
     *       of the same ERC20 token could discharge or release the funds.
     *       All holders of the ERC20 token would essentially be owners of the Charged Particle.
     *
     * @param _tokenUuid        The ID of the Token to Energize
     * @param _assetAmount      The Amount of Asset Token to Energize the Token with
     * @return  The amount of Interest-bearing Tokens added to the escrow for the Token
     */
    function energizeParticle(
        address _contractAddress,
        uint256 _tokenUuid,
        uint256 _assetAmount
    )
        external
        override
        onlyEscrow
        whenNotPaused
        returns (uint256)
    {
        uint256 _existingInterest = interestTokenBalance[_tokenUuid];
        uint256 _existingBalance = assetTokenBalance[_tokenUuid];
        uint256 _newBalance = _assetAmount.add(_existingBalance);

        // Validate Minimum-Required Balance
        require(_newBalance >= MIN_DEPOSIT_FEE, "CHE: INSUFF_DEPOSIT");

        // Collect Asset Token (reverts on fail)
        //   Has to be msg.sender, otherwise anyone could energize anyone else's particles,
        //   with the victim's assets, provided the victim has approved this contract in the past.
        //   If contracts wish to energize a particle, they must first collect the asset
        //   from the user, and approve this contract to transfer from the source contract
        _collectAssetToken(msg.sender, _assetAmount);

        // Tokenize Interest
        uint256 _interestAmount = _tokenizeInterest(_contractAddress, _assetAmount);

        // Track Asset Token Balance (Mass of each Particle)
        assetTokenBalance[_tokenUuid] = _assetAmount.add(_existingBalance);

        // Track Interest-bearing Token Balance (Charge of each Particle)
        interestTokenBalance[_tokenUuid] = _interestAmount.add(_existingInterest);

        // Return amount of Interest-bearing Token energized
        return _interestAmount;
    }

    /***********************************|
    |        Discharge Particles        |
    |__________________________________*/

    /**
     * @notice Allows the owner or operator of the Token to collect or transfer the interest generated
     *         from the token without removing the underlying Asset that is held within the token.
     * @param _receiver         The Address to Receive the Discharged Asset Tokens
     * @param _tokenUuid        The ID of the Token to Discharge
     * @return  Two values; 1: Amount of Asset Token Received, 2: Remaining Charge of the Token
     */
    function dischargeParticle(
        address _receiver,
        uint256 _tokenUuid
    )
        external
        override
        onlyEscrow
        whenNotPaused
        returns (uint256, uint256)
    {
        uint256 _currentCharge = _currentParticleCharge(_tokenUuid);
        return _discharge(_receiver, _tokenUuid, _currentCharge);
    }

    /**
     * @notice Allows the owner or operator of the Token to collect or transfer a specific amount the interest
     *         generated from the token without removing the underlying Asset that is held within the token.
     * @param _receiver         The Address to Receive the Discharged Asset Tokens
     * @param _tokenUuid        The ID of the Token to Discharge
     * @param _assetAmount      The specific amount of Asset Token to Discharge from the Token
     * @return  Two values; 1: Amount of Asset Token Received, 2: Remaining Charge of the Token
     */
    function dischargeParticleAmount(
        address _receiver,
        uint256 _tokenUuid,
        uint256 _assetAmount
    )
        external
        override
        onlyEscrow
        whenNotPaused
        returns (uint256, uint256)
    {
        return _discharge(_receiver, _tokenUuid, _assetAmount);
    }

    /**
     * @notice Releases the Full amount of Asset + Interest held within the Particle by Asset-Pair
     *    Tokens that require Burn before Release MUST call "finalizeRelease" after Burning the Token.
     *    In such cases, the Order of Operations should be:
     *       1. call "releaseParticle"
     *       2. Burn Token
     *       3. call "finalizeRelease"
     *    This should be done in a single, atomic transaction
     *
     * @param _receiver         The Address to Receive the Released Asset Tokens
     * @param _tokenUuid        The ID of the Token to Release
     * @return  The Total Amount of Asset Token Released including all converted Interest
     */
    function releaseParticle(
        address _receiver,
        uint256 _tokenUuid
    )
        external
        override
        onlyEscrow
        returns (uint256)
    {
        require(_baseParticleMass(_tokenUuid) > 0, "CHE: INSUFF_MASS");

        // Release Particle to Receiver
        return _payoutFull(_tokenUuid, _receiver);
    }

    /***********************************|
    |           Collect Fees            |
    |__________________________________*/

    /**
     * @notice Allows External Contracts to withdraw any Fees earned
     * @param _contractAddress  The Address to the External Contract to withdraw Collected Fees for
     * @param _receiver         The Address of the Receiver of the Collected Fees
     */
    function withdrawFees(address _contractAddress, address _receiver) external override onlyEscrow returns (uint256) {
        uint256 _interestAmount = collectedFees[_contractAddress];
        if (_interestAmount > 0) {
            collectedFees[_contractAddress] = 0;
            _withdrawFees(_receiver, _interestAmount);
        }
        return _interestAmount;
    }

    /***********************************|
    |        Internal Functions         |
    |__________________________________*/

    /**
     * @notice Gets the Amount of Asset Tokens that have been Deposited into the Particle
     *    representing the Mass of the Particle.
     * @param _tokenUuid        The ID of the Token within the External Contract
     * @return  The Amount of underlying Assets held within the Token
     */
    function _baseParticleMass(uint256 _tokenUuid) internal view returns (uint256) {
        return assetTokenBalance[_tokenUuid];
    }

    /**
     * @notice Gets the amount of Interest that the Particle has generated representing
     *    the Charge of the Particle
     * @param _tokenUuid        The ID of the Token within the External Contract
     * @return  The amount of interest the Token has generated (in Asset Token)
     */
    function _currentParticleCharge(uint256 _tokenUuid) internal returns (uint256) {
        uint256 _rawBalance = interestTokenBalance[_tokenUuid];
        uint256 _currentCharge = interestToken.toAsset(_rawBalance);
        uint256 _originalCharge = assetTokenBalance[_tokenUuid];
        if (_originalCharge >= _currentCharge) { return 0; }
        return _currentCharge.sub(_originalCharge);
    }

    /**
     * @dev Collects the Required Asset Token from the users wallet
     */
    function _collectAssetToken(address _from, uint256 _assetAmount) internal {
        uint256 _userAssetBalance = assetToken.balanceOf(_from);
        require(_assetAmount <= _userAssetBalance, "CHE: INSUFF_ASSETS");
         // Be sure to Approve this Contract to transfer your Asset Token
        require(assetToken.transferFrom(_from, address(this), _assetAmount), "CHE: TRANSFER_FAILED");
    }

    /**
     * @dev Converts an Asset Token to an Interest Token
     */
    function _tokenizeInterest(
        address _contractAddress,
        uint256 _assetAmount
    )
        internal
        returns (uint256)
    {
        address _self = address(this);
        uint256 _preBalance = interestToken.interestBalance(_self);
        interestToken.depositAsset(_self, _assetAmount);
        uint256 _postBalance = interestToken.interestBalance(_self);
        return _getMassByDeposit(_contractAddress, _postBalance.sub(_preBalance));
    }

    /**
     * @dev Discharges the Interest from a Token
     */
    function _discharge(
        address _receiver,
        uint256 _tokenUuid,
        uint256 _assetAmount
    )
        internal
        returns (uint256, uint256)
    {
        // Validate Discharge Amount
        uint256 _currentCharge = _currentParticleCharge(_tokenUuid);
        require(_currentCharge > 0, "CHE: INSUFF_CHARGE");
        require(_currentCharge <= _assetAmount, "CHE: INSUFF_BALANCE");

        // Precalculate Amount to Discharge to Receiver
        (uint256 _interestAmount, uint256 _receivedAmount) = _siphonAsset(_assetAmount);

        // Track Interest-bearing Token Balance (Mass of each Particle)
        uint256 _interestBalance = interestTokenBalance[_tokenUuid].sub(_interestAmount);
        interestTokenBalance[_tokenUuid] = _interestBalance;

        // Transfer Assets to Receiver
        _payoutAssets(_receiver, _receivedAmount);

        // AmountReceived, Remaining charge
        return (_receivedAmount, _currentCharge.sub(_receivedAmount));
    }

    /**
     * @dev Collects a Specified Asset Amount of the Asset Token from the Interest Token stored for the Particle
     */
    function _siphonAsset(uint256 _assetAmount) internal returns (uint256, uint256) {
        address _self = address(this);

        // Collect Interest
        //  contract receives Asset Token,
        //  function call returns amount of Interest-token exchanged
        uint256 _preAssetAmount = assetToken.balanceOf(_self);
        uint256 _interestAmount = interestToken.withdrawAsset(_self, _assetAmount);
        uint256 _postAssetAmount = assetToken.balanceOf(_self);
        uint256 _receivedAmount = _postAssetAmount.sub(_preAssetAmount);

        // Transfer Interest
        return (_interestAmount, _receivedAmount);
    }

    /**
     * @dev Collects a Specified Interest Amount of the Asset Token from the Interest Token stored for the Particle
     */
    function _siphonInterest(uint256 _interestAmount) internal returns (uint256, uint256) {
        address _self = address(this);

        // Collect Interest
        //  contract receives Asset Token,
        uint256 _preAssetAmount = assetToken.balanceOf(_self);
        interestToken.withdrawInterest(_self, _interestAmount);
        uint256 _postAssetAmount = assetToken.balanceOf(_self);
        uint256 _receivedAmount = _postAssetAmount.sub(_preAssetAmount);

        // Transfer Interest
        return (_interestAmount, _receivedAmount);
    }

    /**
     * @dev Pays out a specified amount of the Asset Token
     */
    function _payoutAssets(address _receiver, uint256 _assetAmount) internal {
        address _self = address(this);
        require(assetToken.transferFrom(_self, _receiver, _assetAmount), "CHE: TRANSFER_FAILED");
    }

    /**
     * @dev Pays out the full amount of the Asset Token + Interest Token
     */
    function _payoutFull(uint256 _tokenUuid, address _receiver) internal returns (uint256) {
        // Get Interest-bearing Token Balance & Reset
        uint256 _interestAmount = interestTokenBalance[_tokenUuid];
        interestTokenBalance[_tokenUuid] = 0;

        // Determine Amount of Assets to Transfer to Receiver
        (, uint256 _receivedAmount) = _siphonInterest(_interestAmount);

        // Transfer Assets to Receiver
        _payoutAssets(_receiver, _receivedAmount);

        return _receivedAmount;
    }

    /**
     * @dev Withdraws Fees in the form of Asset Tokens
     */
    function _withdrawFees(address _receiver, uint256 _interestAmount) internal {
        // Determine Amount of Assets to Transfer to Receiver
        (, uint256 _receivedAmount) = _siphonInterest(_interestAmount);

        // Transfer Assets to Receiver
        _payoutAssets(_receiver, _receivedAmount);
    }
}

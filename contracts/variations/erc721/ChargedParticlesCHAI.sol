// ChargedParticles -- Interest-bearing NFTs based on the DAI Savings Token
// MIT License
// Copyright (c) 2019, 2020 Rob Secord <robsecord.eth>
//
// Permission is hereby granted, free of chaarge, to any person obtaining a copy
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

// Reduce deployment gas costs by limiting the size of text used in error messages
// ERROR CODES:
//  100:        ADDRESS, OWNER, OPERATOR
//      101         Invalid Address
//      102         Sender is not owner
//      103         Sender is not owner or operator
//      104         Insufficient balance
//      105         Unable to send value, recipient may have reverted
//  200:        MATH
//      201         Addition Overflow
//      202         Subtraction Overflow
//      203         Multiplication overflow
//      204         Division by zero
//      205         Modulo by zero
//  300:        ERC721
//      301         Invalid Recipient
//      302         Invalid on-received message
//      303         Invalid tokenId
//      304         Invalid owner/operator
//      305         Token ID already exists
//  400:        ChargedParticles
//      401         Invalid Method
//      402         Unregistered Type
//      403         Particle has no Charge
//      404         Insufficient DAI Balance
//      405         Transfer Failed
//      406         Particle has insufficient charge

pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../../../node_modules/openzeppelin-solidity/contracts/utils/Address.sol";
import "../../../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../../../node_modules/openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "../../../node_modules/openzeppelin-solidity/contracts/token/ERC721/ERC721Metadata.sol";
import "../../assets/chai/IChai.sol";

/**
 * @notice Charged Particles Contract - Interest-Bearing NFTs
 *  -- ERC-721 Edition
 */
contract ChargedParticlesCHAI is ERC721Metadata {
    using SafeMath for uint256;

    /***********************************|
    |        Variables and Events       |
    |__________________________________*/

    IERC20 internal dai;
    IChai internal chai;

    // This value is used to track the amount of CHAI each token holds.
    //   CHAI is always redeemable for more and more DAI over time, thus the interest.
    //
    mapping(uint256 => uint256) internal chaiBalanceByTokenId;    // Amount of Chai minted from Dai deposited

    // To Mint Tokens there is a Minting Fee, which is a small percentage of the Funding Asset
    //    of the token (in this case, DAI) upon Minting.
    //  A value of "50" here would represent a Fee of 0.5% of the Funding Asset ((50 / 10000) * 100)
    //    This allows a fee as low as 0.01%  (value of "1")
    //  This means that a newly minted particle would have 99.5% of its "Mass" and 0% of its "Charge".
    //    As the "Charge" increases over time, the particle will fill up the "Mass" to 100% and then
    //    the "Charge" will start building up.  Essentially, only a small portion of the interest
    //    is used to pay the minting fee.  The particle will be in "cool-down" mode until the "Mass"
    //    of the particle returns to 100% (this should be a relatively short period of time).
    //    When the particle reaches 100% "Mass" is can be "Melted" (or burned) to reclaim the underlying
    //    asset (in this case DAI).  Since the "Mass" will be back to 100%, "Melting" will yield at least 100%
    //    of the underlying asset back to the owner (plus any interest accrued, the "charge").
    //  This value is completely optional and can be set to 0 to specify No Fee.
    uint256 internal mintFee;

    // The amount of Fees collected from minting (collected in CHAI, paid out in DAI)
    uint256 internal collectedFees;

    // Amount of Dai to deposit when minting
    uint256 internal requiredFunding;

    // Track total amount of Particles in existence
    uint256 internal totalMintedTokens;

    // Contract Owner
    //  This value should be assigned to a Multisig Wallet or a DAO
    address private owner;

    bytes16 public version = "v0.1.3";

    event TransferCharge(address indexed from, uint256 indexed _fromTokenId, uint256 indexed _toTokenId, uint256 _amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /***********************************|
    |             Modifiers             |
    |__________________________________*/

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "E102");
        _;
    }

    /***********************************|
    |          Initialization           |
    |__________________________________*/

    constructor() ERC721Metadata("ChargedParticles", "IONS") public {
        // Constructor args suck!  see "setup()" function below
        // requiredFunding = 1e18;
        // mintFee = 50;    //  0.5% of Chai from deposited Dai

        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);
    }

    /***********************************|
    |            Public Read            |
    |__________________________________*/

    /**
     * @notice Gets the address of the contract owner.
     * @return The address of the owner
     */
    function getContractOwner() public view returns (address) {
        return owner;
    }

    /***********************************|
    |         Particle Physics          |
    |__________________________________*/

    /**
     * @notice Gets the Amount of Base DAI held in the Token (amount token was minted with)
     * @return  The Amount of DAI held in the Token
     */
    function baseParticleMass() public view returns (uint256) {
        return requiredFunding;
    }

    /**
     * @notice Gets the amount of interest the Token has generated (it's accumulated particle-charge)
     * @param _tokenId      The ID of the Token
     * @return  The amount of interest the Token has generated
     */
    function currentParticleCharge(uint256 _tokenId) public returns (uint256) {
        require(_exists(_tokenId), "E402");

        uint256 currentCharge = chai.dai(chaiBalanceByTokenId[_tokenId]);
        if (requiredFunding >= currentCharge) { return 0; }
        return currentCharge.sub(requiredFunding);
    }

    /**
     * @notice Allows the owner of the Token to collect the interest generated from the token
     *  without removing the underlying DAI that is held in the token
     * @param _tokenId      The ID of the Token
     * @return  The amount of interest released from the token
     */
    function dischargeParticle(uint256 _tokenId) public returns (uint256) {
        require(_isApprovedOrOwner(msg.sender, _tokenId), "E103");

        uint256 _currentChargeInDai = currentParticleCharge(_tokenId);
        require(_currentChargeInDai > 0, "E403");

        uint256 _paidChai = _payoutChargedDai(msg.sender, _currentChargeInDai);
        chaiBalanceByTokenId[_tokenId] = chaiBalanceByTokenId[_tokenId].sub(_paidChai);

        return _currentChargeInDai;
    }


    /***********************************|
    |            Public Mint            |
    |__________________________________*/

    /**
     * @notice Mints multiple new Particles
     * @param _to       The owner address to assign the new tokens to
     * @param _amount   The amount of tokens to mint
     * @param _data     Custom data used for transferring tokens into contracts
     * @return  The IDs of the newly minted tokens
     */
    function mintParticles(address _to, uint256 _amount, bytes memory _data) public returns (uint256[] memory) {
        address _self = address(this);
        uint256 i;
        uint256 _tokenId;
        uint256 _totalDai;
        uint256[] memory _tokenIds = new uint256[](_amount);

        for (i = 0; i < _amount; ++i) {
            _totalDai = requiredFunding.add(_totalDai);

            _tokenId = (totalMintedTokens.add(i+1));
            _tokenIds[i] = _tokenId;
            _safeMint(_to, _tokenId, _data);
        }
        totalMintedTokens = totalMintedTokens.add(_amount);

        if (_totalDai > 0) {
            // Transfer DAI from User to Contract
            _collectRequiredDai(msg.sender, _totalDai);

            uint256 _balance = chai.balanceOf(_self);
            for (i = 0; i < _amount; ++i) {
                _tokenId = _tokenIds[i];

                // Tokenize Interest
                chai.join(_self, requiredFunding);

                // Track Chai in each Token
                 chaiBalanceByTokenId[_tokenId] = _totalChaiForToken(chai.balanceOf(_self).sub(_balance));
                _balance = chai.balanceOf(_self);
            }
        }
        return _tokenIds;
    }

    /***********************************|
    |            Public Burn            |
    |__________________________________*/

    /**
     * @notice Destroys a Particle and releases the underlying DAI + Interest (Mass + Charge)
     * @param _tokenId      The ID of the token to burn
     */
    function burnParticle(uint256 _tokenId) public {
        // Burn Token
        _burn(msg.sender, _tokenId);

        // Payout Dai + Interest
        uint256 _tokenChai = chaiBalanceByTokenId[_tokenId];
        chaiBalanceByTokenId[_tokenId] = 0;
        _payoutFundedDai(msg.sender, _tokenChai);
    }

    /**
     * @notice Destroys multiple Particles and releases the underlying DAI + Interest (Mass + Charge)
     * @param _tokenIds     The IDs of the tokens to burn
     */
    function burnParticles(uint256[] memory _tokenIds) public {
        uint256 _tokenId;
        uint256 _totalChai;
        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            _tokenId = _tokenIds[i];

            // Burn Token
            _burn(msg.sender, _tokenId);

            // Payout Dai + Interest
            _totalChai = chaiBalanceByTokenId[_tokenId].add(_totalChai);
            chaiBalanceByTokenId[_tokenId] = 0;
        }
        _payoutFundedDai(msg.sender, _totalChai);
    }

    /***********************************|
    |         Transfer Charge           |
    |__________________________________*/

    /**
     * @notice Transfers a tokens full-charge from one particle to another
     * @param _fromTokenId  The Token ID to transfer the Charge from
     * @param _toTokenId    The Token ID to transfer the Charge to
     */
    function transferCharge(uint256 _fromTokenId, uint256 _toTokenId) public {
        require(_isApprovedOrOwner(msg.sender, _fromTokenId), "E103");

        // Transfer Full Amount of Charge
        uint256 currentCharge = currentParticleCharge(_fromTokenId); // In Funding Token
        _transferCharge(msg.sender, _fromTokenId, _toTokenId, currentCharge);
    }

    /**
     * @notice Transfers some of a tokens charge from one particle to another
     * @param _fromTokenId  The Token ID to transfer the Charge from
     * @param _toTokenId    The Token ID to transfer the Charge to
     * @param _amount       The Amount of Charge to be transferred - must be <= particle charge
     */
    function transferCharge(uint256 _fromTokenId, uint256 _toTokenId, uint256 _amount) public {
        require(_isApprovedOrOwner(msg.sender, _fromTokenId), "E103");

        _transferCharge(msg.sender, _fromTokenId, _toTokenId, _amount);
    }

    /***********************************|
    |            Only Owner             |
    |__________________________________*/

    /**
     * @dev Setup the DAI/CHAI contracts and configure the contract
     */
    function setup(address _daiAddress, address _chaiAddress, uint256 _mintFee, uint256 _requiredFunding) public onlyOwner {
        // Set DAI as Funding Token
        dai = IERC20(_daiAddress);
        chai = IChai(_chaiAddress);

        // Setup Chai to Tokenize DAI Interest
        dai.approve(_chaiAddress, uint(-1));

        mintFee = _mintFee;
        requiredFunding = _requiredFunding;
    }

    /**
     * @dev Allows contract owner to withdraw any fees earned
     */
    function withdrawFees() public onlyOwner {
        uint256 _balance = address(this).balance;
        if (_balance > 0) {
            msg.sender.transfer(_balance);
        }
        if (collectedFees > 0) {
            _payoutFundedDai(msg.sender, collectedFees);
            collectedFees = 0;
        }
    }

    /**
     * @notice Transfers the ownership of the contract to new address
     * @param _newOwner Address of the new owner
     */
    function transferOwnership(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), "E101");
        emit OwnershipTransferred(owner, _newOwner);
        owner = _newOwner;
    }

    /***********************************|
    |         Private Functions         |
    |__________________________________*/

    /**
     * @dev Collects the Required DAI from the users wallet during Minting
     * @param _from         The owner address to collect the DAI from
     * @param _requiredDai  The amount of DAI to collect from the user
     */
    function _collectRequiredDai(address _from, uint256 _requiredDai) internal {
        // Transfer DAI from User to Contract
        uint256 _userDaiBalance = dai.balanceOf(_from);
        require(_requiredDai <= _userDaiBalance, "E404");
        require(dai.transferFrom(_from, address(this), _requiredDai), "E405");
    }

    /**
     * @dev Pays out a specified amount of CHAI
     * @param _to           The owner address to pay out to
     * @param _totalChai    The total amount of CHAI to pay out
     */
    function _payoutFundedDai(address _to, uint256 _totalChai) internal {
        address _self = address(this);

        // Exit Chai and collect Dai + Interest
        chai.exit(_self, _totalChai);

        // Transfer Dai + Interest
        uint256 _receivedDai = dai.balanceOf(_self);
        require(dai.transferFrom(_self, _to, _receivedDai), "E405");
    }

    /**
     * @dev Pays out a specified amount of DAI
     * @param _to           The owner address to pay out to
     * @param _totalDai     The total amount of DAI to pay out
     */
    function _payoutChargedDai(address _to, uint256 _totalDai) internal returns (uint256) {
        address _self = address(this);

        // Collect Interest
        uint256 _chai = chai.draw(_self, _totalDai);

        // Transfer Interest
        uint256 _receivedDai = dai.balanceOf(_self);
        require(dai.transferFrom(_self, _to, _receivedDai), "E405");
        return _chai;
    }

    /**
     * @dev Transfers a tokens charge from one particle to another
     * @param _from         The owner address to transfer the Charge from
     * @param _fromTokenId  The Token ID to transfer the Charge from
     * @param _toTokenId    The Token ID to transfer the Charge to
     * @param _amount       The Amount of Charge to be transferred - must be <= particle charge
     */
    function _transferCharge(address _from, uint256 _fromTokenId, uint256 _toTokenId, uint256 _amount) internal {
        uint256 currentCharge = currentParticleCharge(_fromTokenId); // In Funding Token
        require(currentCharge > 0, "E403");
        require(currentCharge >= _amount, "E406");

        // Move Chai (already held in contract, just need to swap balances)
        uint256 _chaiAmount = chai.chai(_amount);
        chaiBalanceByTokenId[_fromTokenId] = chaiBalanceByTokenId[_fromTokenId].sub(_chaiAmount);
        chaiBalanceByTokenId[_toTokenId] = chaiBalanceByTokenId[_toTokenId].add(_chaiAmount);

        // Emit event
        emit TransferCharge(_from, _fromTokenId, _toTokenId, _amount);
    }

    /**
     * @dev Calculates the amount of DAI held within a token during minting
     *      Note: Accounts for any contract fees
     * @param _tokenChai    The total amount of DAI used to fund the token
     * @return  The actual amount of DAI to fund the token - fees
     */
    function _totalChaiForToken(uint256 _tokenChai) internal returns (uint256) {
        if (mintFee == 0) { return _tokenChai; }
        uint256 _mintFee = _tokenChai.mul(mintFee).div(1e4);
        collectedFees = collectedFees.add(_mintFee);
        return _tokenChai.sub(_mintFee);
    }
}

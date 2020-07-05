// SPDX-License-Identifier: MIT

// EscrowBase.sol
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

import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IEscrow.sol";
import "../interfaces/INucleus.sol";
import "../interfaces/IChargedParticlesEscrowManager.sol";

import "./Common.sol";

/**
 * @notice Escrow-Base Contract
 */
abstract contract EscrowBase is Initializable, OwnableUpgradeSafe, IEscrow, Common {
    using SafeMath for uint256;

    IChargedParticlesEscrowManager internal escrowMgr;

    // Contract Interface to Asset Token
    IERC20 internal assetToken;
    
    // Contract Interface to Interest-bearing Token
    INucleus internal interestToken;

    // These values are used to track the amount of Interest-bearing Tokens each Particle holds.
    //   The Interest-bearing Token is always redeemable for
    //   more and more of the Asset Token over time, thus the interest.
    //
    //     TokenUUID => Balance
    mapping (uint256 => uint256) internal interestTokenBalance;     // Current Balance in Interest Token
    mapping (uint256 => uint256) internal assetTokenBalance;      // Original Amount Deposited in Asset Token

    // Contract => Deposit Fees earned for External Contracts
    // (collected in Interest-bearing Token, paid out in Asset Token)
    mapping (address => uint256) internal collectedFees;

    bool public paused;

    // Throws if called by any account other than the Charged Particles Escrow Controller.
    modifier onlyEscrow() {
        require(msg.sender == address(escrowMgr), "CPEB: INVALID_ESCROW");
        _;
    }

    // Throws if called by any account other than the Charged Particles Escrow Controller.
    modifier whenNotPaused() {
        require(paused != true, "CPEB: PAUSED");
        _;
    }

    /***********************************|
    |          Initialization           |
    |__________________________________*/

    function initialize() public initializer {
        __Ownable_init();
        paused = true;
    }

    /***********************************|
    |              Public               |
    |__________________________________*/

    function isPaused() external override view returns (bool) {
        return paused;
    }

    function getAssetTokenAddress() external override view returns (address) {
        return address(assetToken);
    }

    function getInterestTokenAddress() external override view returns (address) {
        return address(interestToken);
    }


    /***********************************|
    |          Only Admin/DAO           |
    |__________________________________*/

    /**
     * @dev Connects to the Charged Particles Escrow-Controller 
     */
    function setPausedState(bool _paused) external onlyOwner {
        paused = _paused;
    }

    /**
     * @dev Connects to the Charged Particles Escrow-Controller 
     */
    function setEscrowManager(address _escrowMgr) external onlyOwner {
        escrowMgr = IChargedParticlesEscrowManager(_escrowMgr);
    }

    /**
     * @dev Register Contracts for Asset/Interest Pairs
     */
    function registerAssetPair(address _assetTokenAddress, address _interestTokenAddress) external onlyOwner {
        require(_assetTokenAddress != address(0x0), "CPEB: INVALID_ASSET_TOKEN");
        require(_interestTokenAddress != address(0x0), "CPEB: INVALID_INTEREST_TOKEN");

        // Register Addresses
        assetToken = IERC20(_assetTokenAddress);
        interestToken = INucleus(_interestTokenAddress);

        // Allow this contract to Tokenize Interest of Asset
        assetToken.approve(_interestTokenAddress, uint(-1));
    }

    /***********************************|
    |         Private Functions         |
    |__________________________________*/

    /**
     * @dev Calculates the amount of Interest-bearing Tokens are held within a Particle after Fees
     * @return  The actual amount of Interest-bearing Tokens used to fund the Particle minus fees
     */
    function _getMassByDeposit(
        address _contractAddress,
        uint256 _interestTokenAmount
    )
        internal
        returns (uint256)
    {
        // Internal Fees
        address _escrow = address(escrowMgr);
        (uint256 _depositFee, uint256 _customFee) = escrowMgr.getFeesForDeposit(_contractAddress, _interestTokenAmount);
        collectedFees[_escrow] = _depositFee.add(collectedFees[_escrow]);

        // Custom Fees for External Contract
        if (_customFee > 0) {
            collectedFees[_contractAddress] = _customFee.add(collectedFees[_contractAddress]);
        }

        // Total Deposit
        return _interestTokenAmount.sub(_depositFee).sub(_customFee);
    }
}

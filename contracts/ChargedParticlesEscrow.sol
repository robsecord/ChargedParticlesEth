// ChargedParticlesEscrow.sol -- Interest-bearing NFTs
// MIT License
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

// Reduce deployment gas costs by limiting the size of text used in error messages
// ERROR CODES:
//  300:        ChargedParticlesEscrow
//      301         Asset-Pair is not enabled
//      302         Asset-Pair is not allowed
//      303         Asset-Pair has not been registered
//      304         Contract is not registered
//      305         Invalid Contract Operator
//      306         Must be creator of type
//      307         Invalid address
//      308         Invalid Asset Token address
//      309         Invalid Interest Token address
//      310         Invalid owner/operator
//      311         Index out-of-bounds
//      312         Invalid Token-Type Interface
//      313         Requires setting a Single Custom Asset-Pair
//      314         Setting releaseRequiresBurn cannot be true for Multi-Asset Particles
//      315         Deposit Fee is too high
//      316         Minimum deposit is not high enough
//      317         Caller is not Contract Owner
//      318         Token must be Non-fungible
//      319         Token Balance is lower than required limit
//      320         Token Balance is lower than allowed limit
//      321         Token Balance is higher than allowed limit
//      322         Token not prepared for release or unapproved operator
//      323         Token requires burning before release
//      324         Insufficient Asset Token funds
//      325         Failed to transfer Asset Token
//      326         Particle has Insufficient Charge
//      327         Transfer Failed


pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/introspection/IERC165.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "./assets/INucleus.sol";

contract IOwnable {
    function owner() public view returns (address);
}

contract INonFungible {
    function ownerOf(uint256 _tokenId) public view returns (address);
    function isApprovedForAll(address _owner, address _operator) external view returns (bool);
}

contract IChargedParticles {
    function getTypeCreator(uint256 _type) public view returns (address);
}

/**
 * @notice Charged Particles Contract - Interest-Bearing NFTs
 */
contract ChargedParticlesEscrow is Initializable, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    uint256 constant internal DEPOSIT_FEE_MODIFIER = 1e4;   // 10000  (100%)
    uint256 constant internal MAX_CUSTOM_DEPOSIT_FEE = 5e3; // 5000   (50%)
    uint256 constant internal MIN_DEPOSIT_FEE = 1e6;        // 1000000 (0.000000000001 ETH  or  1000000 WEI)

    uint256 constant internal TYPE_NF_BIT = 1 << 255;                   // ERC1155 Common Non-fungible Token Bit
    uint256 constant internal TYPE_MASK = uint256(uint128(~0)) << 128;  // ERC1155 Common Non-fungible Type Mask

    bytes4 constant internal INTERFACE_SIGNATURE_ERC721 = 0x80ac58cd;
    bytes4 constant internal INTERFACE_SIGNATURE_ERC1155 = 0xd9b67a26;

    /***********************************|
    |       Per Contract Settings       |
    |__________________________________*/

    //
    // Optional Limits set by Owner of External Token Contracts;
    //  - Any user can add any ERC721 or ERC1155 token as a Charged Particle without Limits,
    //    unless the Owner of the ERC721 or ERC1155 token contract registers the token here
    //    and sets the Custom Limits for their token(s)
    //

    //      Contract => Has this contract address been Registered with Custom Limits?
    mapping (address => bool) internal custom_registeredContract;

    //      Contract => Does the Release-Action require the Charged Particle Token to be burned first?
    mapping (address => bool) internal custom_releaseRequiresBurn;

    //      Contract => Specific Asset-Pair that is allowed (otherwise, any Asset-Pair is allowed)
    mapping (address => bytes16) internal custom_assetPairId;

    //      Contract =>    Asset-Pair-ID => Deposit Fees earned for Contract Owner
    mapping (address => mapping (bytes16 => uint256)) internal custom_assetDepositFee;

    //      Contract =>    Asset-Pair-ID => Allowed Limit of Asset Token [min, max]
    mapping (address => mapping (bytes16 => uint256)) internal custom_assetDepositMin;
    mapping (address => mapping (bytes16 => uint256)) internal custom_assetDepositMax;

    /***********************************|
    |         Per Token Settings        |
    |  (specific to Charged Particles)  |
    |__________________________________*/

    //        TypeID => Address that collects the custom fees for a specific type
    mapping (uint256 => address) internal creator_feeCollector;

    //        TypeID => Specific Asset-Pair that is allowed (otherwise, any Asset-Pair is allowed)
    mapping (uint256 => bytes16) internal creator_assetPairId;

    //        TypeID =>    Asset-Pair-ID => Deposit Fees earned for Type Creator
    mapping (uint256 => mapping (bytes16 => uint256)) internal creator_assetDepositFee;

    //        TypeID =>    Asset-Pair-ID => Allowed Limit of Asset Token [min, max]
    mapping (uint256 => mapping (bytes16 => uint256)) internal creator_assetDepositMin;
    mapping (uint256 => mapping (bytes16 => uint256)) internal creator_assetDepositMax;

    /***********************************|
    |       Internal Vars/Events        |
    |__________________________________*/

    // The Charged Particles ERC1155 Token Contract
    address internal chargedParticles;

    // Various Interest-bearing Tokens may act as the Nucleus for a Charged Particle
    //   Interest-bearing Tokens (like Chai) are funded with an underlying Asset Token (like Dai)
    //
    // Asset-Pair-ID => Contract Interface to Asset Token
    mapping (bytes16 => IERC20) internal assetToken;
    //
    // Asset-Pair-ID => Contract Interface to Interest-bearing Token
    mapping (bytes16 => INucleus) internal interestToken;

    // Asset-Pair-IDs
    bytes16[] internal assetPairs;
    mapping (bytes16 => bool) internal assetPairEnabled;

    // These values are used to track the amount of Interest-bearing Tokens each Particle holds.
    //   The Interest-bearing Token is always redeemable for
    //   more and more of the Asset Token over time, thus the interest.
    //
    //     TokenUUID =>    Asset-Pair-ID => Balance
    mapping (uint256 => mapping (bytes16 => uint256)) internal interestTokenBalance;     // Current Balance in Interest Token
    mapping (uint256 => mapping (bytes16 => uint256)) internal assetTokenDeposited;      // Original Amount Deposited in Asset Token

    //     TokenUUID => Token Release Operator
    mapping (uint256 => address) internal assetToBeReleased;

    // Asset-Pair-ID => Deposit Fees earned by Contract
    // (collected in Interest-bearing Token, paid out in Asset Token)
    mapping (bytes16 => uint256) internal collectedFees;

    //      Contract =>    Asset-Pair-ID => Deposit Fees earned for External Contract
    mapping (address => mapping (bytes16 => uint256)) internal custom_collectedDepositFees;

    //        TypeID =>    Asset-Pair-ID => Deposit Fees earned for External Particle Type Creator
    mapping (uint256 => mapping (bytes16 => uint256)) internal creator_collectedDepositFees;

    // To "Energize" Particles of any Type, there is a Deposit Fee, which is
    //  a small percentage of the Interest-bearing Asset of the token immediately after deposit.
    //  A value of "50" here would represent a Fee of 0.5% of the Funding Asset ((50 / 10000) * 100)
    //    This allows a fee as low as 0.01%  (value of "1")
    //  This means that a brand new particle would have 99.5% of its "Mass" and 0% of its "Charge".
    //    As the "Charge" increases over time, the particle will fill up the "Mass" to 100% and then
    //    the "Charge" will start building up.  Essentially, only a small portion of the interest
    //    is used to pay the deposit fee.  The particle will be in "cool-down" mode until the "Mass"
    //    of the particle returns to 100% (this should be a relatively short period of time).
    //    When the particle reaches 100% "Mass" is can be "Released" (or burned) to reclaim the underlying
    //    asset + interest.  Since the "Mass" will be back to 100%, "Releasing" will yield at least 100%
    //    of the underlying asset back to the owner (plus any interest accrued, the "charge").
    uint256 public depositFee;

    // Contract Version
    bytes16 public version;

    //
    // Events
    //

    event RegisterParticleContract(address indexed _contractAddress);
    event CustomFeesWithdrawn(address indexed _contractAddress, address indexed _receiver);
    event CreatorFeesWithdrawn(address indexed _sender, address indexed _creatorAddress);
    event EnergizedParticle(address indexed _contractAddress, uint256 indexed _tokenId, bytes16 _assetPairId, uint256 _assetBalance, uint256 _interestBalance);
    event DischargedParticle(address indexed _contractAddress, uint256 indexed _tokenId, address indexed _receiver, bytes16 _assetPairId, uint256 _receivedAmount, uint256 _interestBalance);
    event ReleasedParticle(address indexed _contractAddress, uint256 indexed _tokenId, address indexed _receiver, bytes16 _assetPairId, uint256 _receivedAmount);
    event ContractFeesWithdrawn(address indexed _receiver);

    /***********************************|
    |          Initialization           |
    |__________________________________*/

    function initialize(address sender) public initializer {
        Ownable.initialize(sender);
        ReentrancyGuard.initialize();
        version = "v0.2.4";
    }

    /***********************************|
    |         Particle Physics          |
    |__________________________________*/

    function isAssetPairEnabled(bytes16 _assetPairId) public view returns (bool) {
        return assetPairEnabled[_assetPairId];
    }

    function getAssetPairsCount() public view returns (uint) {
        return assetPairs.length;
    }

    function getAssetPairByIndex(uint _index) public view returns (bytes16) {
        require(_index >= 0 && _index < assetPairs.length, "E311");
        return assetPairs[_index];
    }

    function getAssetTokenAddress(bytes16 _assetPairId) public view returns (address) {
        require(isAssetPairEnabled(_assetPairId), "E301");
        return address(assetToken[_assetPairId]);
    }

    function getInterestTokenAddress(bytes16 _assetPairId) public view returns (address) {
        require(isAssetPairEnabled(_assetPairId), "E301");
        return address(interestToken[_assetPairId]);
    }

    function getTokenUUID(address _contractAddress, uint256 _tokenId) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_contractAddress, _tokenId)));
    }

    function getAssetMinDeposit(address _contractAddress, uint256 _typeId, bytes16 _assetPairId) public view returns (uint256) {
        if (_contractAddress == chargedParticles) {
            return creator_assetDepositMin[_typeId][_assetPairId];
        }
        return custom_assetDepositMin[_contractAddress][_assetPairId];
    }

    function getAssetMaxDeposit(address _contractAddress, uint256 _typeId, bytes16 _assetPairId) public view returns (uint256) {
        if (_contractAddress == chargedParticles) {
            return creator_assetDepositMax[_typeId][_assetPairId];
        }
        return custom_assetDepositMax[_contractAddress][_assetPairId];
    }

    /**
     * @dev Calculates the amount of Fees to be paid for a specific deposit amount
     * @return  The amount of base fees and the amount of creator fees
     */
    function getFeesForDeposit(
        address _contractAddress,
        uint256 _typeId,
        uint256 _interestTokenAmount,
        bytes16 _assetPairId
    )
        public
        view
        returns (uint256, uint256, uint256)
    {
        uint256 _depositFee;
        uint256 _customFee;
        uint256 _creatorFee;

        if (depositFee > 0) {
            _depositFee = _interestTokenAmount.mul(depositFee).div(DEPOSIT_FEE_MODIFIER);
        }

        if (_contractAddress == chargedParticles) {
            uint256 _creatorFeeSetting = creator_assetDepositFee[_typeId][_assetPairId];
            if (_creatorFeeSetting > 0) {
                _creatorFee = _interestTokenAmount.mul(_creatorFeeSetting).div(DEPOSIT_FEE_MODIFIER);
            }
        } else {
            uint256 _customFeeSetting = custom_assetDepositFee[_contractAddress][_assetPairId];
            if (_customFeeSetting > 0) {
                _customFee = _interestTokenAmount.mul(_customFeeSetting).div(DEPOSIT_FEE_MODIFIER);
            }
        }

        return (_depositFee, _customFee, _creatorFee);
    }

    /**
     * @dev Calculates the Total Fee to be paid for a specific deposit amount
     * @return  The amount of base fees plus the amount of custom/creator fees
     */
    function getFeeForDeposit(
        address _contractAddress,
        uint256 _typeId,
        uint256 _interestTokenAmount,
        bytes16 _assetPairId
    )
        public
        view
        returns (uint256)
    {
        (uint256 _depositFee, uint256 _customFee, uint256 _creatorFee) = getFeesForDeposit(_contractAddress, _typeId, _interestTokenAmount, _assetPairId);
        return _depositFee.add(_customFee).add(_creatorFee);
    }

    /**
     * @notice Gets the Amount of Asset Tokens that have been Deposited
     * @param _contractAddress  The Address to the External Contract of the Token
     * @param _tokenId          The ID of the Token within the External Contract
     * @param _assetPairId      The Asset-Pair ID to check the balance of
     * @return  The Amount of underlying Assets held within the Token
     */
    function baseParticleMass(address _contractAddress, uint256 _tokenId, bytes16 _assetPairId) public view returns (uint256) {
        uint256 _tokenUuid = getTokenUUID(_contractAddress, _tokenId);
        return assetTokenDeposited[_tokenUuid][_assetPairId];
    }

    /**
     * @notice Gets the amount of Charge the Particle has generated (it's accumulated interest)
     * @param _tokenId      The ID of the Token
     * @return  The amount of interest the Token has generated (in Asset Token)
     */
    function currentParticleCharge(address _contractAddress, uint256 _tokenId, bytes16 _assetPairId) public returns (uint256) {
        uint256 _tokenUuid = getTokenUUID(_contractAddress, _tokenId);
        uint256 _rawBalance = interestTokenBalance[_tokenUuid][_assetPairId];
        uint256 _currentCharge = interestToken[_assetPairId].toAsset(_rawBalance);
        uint256 _originalCharge = assetTokenDeposited[_tokenUuid][_assetPairId];
        if (_originalCharge >= _currentCharge) { return 0; }
        return _currentCharge.sub(_originalCharge);
    }

    /***********************************|
    |     Register Contract Settings    |
    |(For External Contract Integration)|
    |__________________________________*/

    function isContractOwnerOperator(address _account, address _contract) public view returns (bool) {
        address _contractOwner = IOwnable(_contract).owner();
        return _contractOwner == _account || owner() == _account;
    }

    function registerContractType(address _contractAddress) public {
        // Check Token Interface to ensure compliance
        IERC165 _tokenInterface = IERC165(_contractAddress);
        bool _is721 = _tokenInterface.supportsInterface(INTERFACE_SIGNATURE_ERC721);
        bool _is1155 = _tokenInterface.supportsInterface(INTERFACE_SIGNATURE_ERC1155);
        require(_is721 || _is1155, "E312");

        // Check Contract Owner to prevent random people from setting Limits
        require(isContractOwnerOperator(msg.sender, _contractAddress), "E305");

        // Contract Registered!
        custom_registeredContract[_contractAddress] = true;

        emit RegisterParticleContract(_contractAddress);
    }

    function registerContractSetting_ReleaseBurn(address _contractAddress, bool _releaseRequiresBurn) public {
        require(custom_registeredContract[_contractAddress], "E304");
        require(isContractOwnerOperator(msg.sender, _contractAddress), "E305");

        require(custom_assetPairId[_contractAddress].length > 0, "E313");

        custom_releaseRequiresBurn[_contractAddress] = _releaseRequiresBurn;
    }

    function registerContractSetting_AssetPair(address _contractAddress, bytes16 _assetPairId) public {
        require(custom_registeredContract[_contractAddress], "E304");
        require(isContractOwnerOperator(msg.sender, _contractAddress), "E305");

        if (_assetPairId.length > 0) {
            require(assetPairEnabled[_assetPairId], "E301");
        } else {
            require(custom_releaseRequiresBurn[_contractAddress] != true, "E314");
        }

        custom_assetPairId[_contractAddress] = _assetPairId;
    }

    function registerContractSetting_DepositFee(address _contractAddress, bytes16 _assetPairId, uint256 _depositFee) public {
        require(custom_registeredContract[_contractAddress], "E304");
        require(isContractOwnerOperator(msg.sender, _contractAddress), "E305");

        require(assetPairEnabled[_assetPairId], "E301");
        require(_depositFee <= MAX_CUSTOM_DEPOSIT_FEE, "E315");

        custom_assetDepositFee[_contractAddress][_assetPairId] = _depositFee;
    }

    function registerContractSetting_MinDeposit(address _contractAddress, bytes16 _assetPairId, uint256 _minDeposit) public {
        require(custom_registeredContract[_contractAddress], "E304");
        require(isContractOwnerOperator(msg.sender, _contractAddress), "E305");

        require(assetPairEnabled[_assetPairId], "E301");
        require(_minDeposit == 0 || _minDeposit > MIN_DEPOSIT_FEE, "E316");

        custom_assetDepositMin[_contractAddress][_assetPairId] = _minDeposit;
    }

    function registerContractSetting_MaxDeposit(address _contractAddress, bytes16 _assetPairId, uint256 _maxDeposit) public {
        require(custom_registeredContract[_contractAddress], "E304");
        require(isContractOwnerOperator(msg.sender, _contractAddress), "E305");

        require(assetPairEnabled[_assetPairId], "E301");

        custom_assetDepositMax[_contractAddress][_assetPairId] = _maxDeposit;
    }


    /***********************************|
    |     Register Creator Settings     |
    |__________________________________*/

    function isTypeCreator(address _account, uint256 _typeId) public view returns (bool) {
        if (_account == chargedParticles) { return true; }
        address _typeCreator = IChargedParticles(chargedParticles).getTypeCreator(_typeId);
        return _typeCreator == _account;
    }

    function registerCreatorSetting_FeeCollector(uint256 _typeId, address _feeCollector) public {
        require(isTypeCreator(msg.sender, _typeId), "E306");
        creator_feeCollector[_typeId] = _feeCollector;
    }

    function registerCreatorSetting_AssetPair(uint256 _typeId, bytes16 _assetPairId) public {
        require(isTypeCreator(msg.sender, _typeId), "E306");

        if (_assetPairId.length > 0) {
            require(assetPairEnabled[_assetPairId], "E301");
        }

        creator_assetPairId[_typeId] = _assetPairId;
    }

    function registerCreatorSetting_DepositFee(uint256 _typeId, bytes16 _assetPairId, uint256 _depositFee) public {
        require(isTypeCreator(msg.sender, _typeId), "E306");

        require(assetPairEnabled[_assetPairId], "E301");
        require(_depositFee <= MAX_CUSTOM_DEPOSIT_FEE, "E315");

        creator_assetDepositFee[_typeId][_assetPairId] = _depositFee;
    }

    function registerCreatorSetting_MinDeposit(uint256 _typeId, bytes16 _assetPairId, uint256 _minDeposit) public {
        require(isTypeCreator(msg.sender, _typeId), "E306");

        require(assetPairEnabled[_assetPairId], "E301");
        require(_minDeposit == 0 || _minDeposit > MIN_DEPOSIT_FEE, "E316");

        creator_assetDepositMin[_typeId][_assetPairId] = _minDeposit;
    }

    function registerCreatorSetting_MaxDeposit(uint256 _typeId, bytes16 _assetPairId, uint256 _maxDeposit) public {
        require(isTypeCreator(msg.sender, _typeId), "E306");

        require(assetPairEnabled[_assetPairId], "E301");

        creator_assetDepositMax[_typeId][_assetPairId] = _maxDeposit;
    }

    /***********************************|
    |           Collect Fees            |
    |__________________________________*/

    /**
     * @dev Allows External Contract Owners to withdraw any Custom Fees earned
     */
    function withdrawContractFees(address _contractAddress, address _receiver) public nonReentrant {
        require(custom_registeredContract[_contractAddress], "E304");

        // Validate Contract Owner
        address _contractOwner = IOwnable(_contractAddress).owner();
        require(_contractOwner == msg.sender, "E317");

        bool withdrawn;
        for (uint i = 0; i < assetPairs.length; i++) {
            bytes16 _assetPairId = assetPairs[i];
            uint256 _interestAmount = custom_collectedDepositFees[_contractAddress][_assetPairId];
            if (_interestAmount > 0) {
                _withdrawFees(_receiver, _assetPairId, _interestAmount);
            }
        }

        if (withdrawn) {
            emit CustomFeesWithdrawn(_contractAddress, _receiver);
        }
    }

    /**
     * @dev Allows Particle Type Creators to withdraw any Fees earned
     */
    function withdrawCreatorFees(address _sender, uint256 _typeId) public nonReentrant {
        bool withdrawn;
        for (uint i = 0; i < assetPairs.length; i++) {
            bytes16 _assetPairId = assetPairs[i];
            uint256 _interestAmount = creator_collectedDepositFees[_typeId][_assetPairId];
            if (_interestAmount > 0) {
                _withdrawFees(creator_feeCollector[_typeId], _assetPairId, _interestAmount);
                withdrawn = true;
            }
        }

        if (withdrawn) {
            _sender = (msg.sender == chargedParticles) ? _sender : msg.sender;
            emit CreatorFeesWithdrawn(_sender, creator_feeCollector[_typeId]);
        }
    }

    /***********************************|
    |        Energize Particles         |
    |__________________________________*/

    //
    //  Fund Particle with Asset Token
    //  Must be called by the Owner providing the Asset
    //  Owner must Approve THIS contract as Operator of Asset
    //
    //  NOTE: DO NOT Energize an ERC20 Token, as anyone who holds any amount
    //        of the same ERC20 token could discharge or release the funds.
    //        All holders of the ERC20 token would essentially be owners of the Charged Particle.
    //
    function energizeParticle(
        address _contractAddress,
        uint256 _tokenId,
        bytes16 _assetPairId,
        uint256 _assetAmount
    )
        external
        nonReentrant
        returns (uint256)
    {
//        require(_isNonFungibleToken(_contractAddress, _tokenId), "E318");
        require(assetPairEnabled[_assetPairId], "E301");

        // Get Token UUID & Balance
        uint256 typeId;
        uint256 _tokenUuid = getTokenUUID(_contractAddress, _tokenId);
        uint256 _existingBalance = assetTokenDeposited[_tokenUuid][_assetPairId];
        uint256 _newBalance = _assetAmount.add(_existingBalance);

        // Validate Minimum-Required Balance
        require(_newBalance >= MIN_DEPOSIT_FEE, "E319");

        // Validate Type-Creator Settings
        if (_contractAddress == chargedParticles) {
            typeId = _tokenId & TYPE_MASK;

            // Valid Asset-Pair?
            if (creator_assetPairId[typeId].length > 0) {
                require(_assetPairId == creator_assetPairId[typeId], "E302");
            }

            // Valid Amount?
            if (creator_assetDepositMin[typeId][_assetPairId] > 0) {
                require(_newBalance >= creator_assetDepositMin[typeId][_assetPairId], "E320");
            }
            if (creator_assetDepositMax[typeId][_assetPairId] > 0) {
                require(_newBalance <= creator_assetDepositMax[typeId][_assetPairId], "E321");
            }
        }

        // Validate Custom Contract Settings
        else {
            bool hasCustomSettings = custom_registeredContract[_contractAddress];
            if (hasCustomSettings) {
                // Valid Asset-Pair?
                if (custom_assetPairId[_contractAddress].length > 0) {
                    require(_assetPairId == custom_assetPairId[_contractAddress], "E302");
                }

                // Valid Amount?
                if (custom_assetDepositMin[_contractAddress][_assetPairId] > 0) {
                    require(_newBalance >= custom_assetDepositMin[_contractAddress][_assetPairId], "E320");
                }
                if (custom_assetDepositMax[_contractAddress][_assetPairId] > 0) {
                    require(_newBalance <= custom_assetDepositMax[_contractAddress][_assetPairId], "E321");
                }
            }
        }

        // Collect Asset Token (reverts on fail)
        //   Has to be msg.sender, otherwise anyone could energize anyone else's particles,
        //   provided the victim has approved this contract in the past.
        //   If contracts wish to energize a particle, they must first collect the asset
        //   from the user, and approve this contract to transfer from the source contract
        _collectAssetToken(msg.sender, _assetPairId, _assetAmount);

        // Tokenize Interest
        uint256 _interestAmount = _tokenizeInterest(_contractAddress, typeId, _assetPairId, _assetAmount);

        // Track Asset Token Balance (Mass of each Particle)
        uint256 _assetBalance = _assetAmount.add(assetTokenDeposited[_tokenUuid][_assetPairId]);
        assetTokenDeposited[_tokenUuid][_assetPairId] = _assetBalance;

        // Track Interest-bearing Token Balance (Charge of each Particle)
        uint256 _interestBalance = _interestAmount.add(interestTokenBalance[_tokenUuid][_assetPairId]);
        interestTokenBalance[_tokenUuid][_assetPairId] = _interestBalance;

        emit EnergizedParticle(_contractAddress, _tokenId, _assetPairId, _assetBalance, _interestBalance);

        // Return amount of Interest-bearing Token energized
        return _interestAmount;
    }

    // Add Asset; convert to Interest-Token to increase Charge, but not Mass
//    function rechargeParticle() public {
//        // TODO..
//    }


    /***********************************|
    |        Discharge Particles        |
    |__________________________________*/

    /**
     * @notice Allows the owner or operator of the Token to collect or transfer the interest generated
     *         from the token without removing the underlying Asset that is held within the token.
     * @param _tokenId      The ID of the Token
     * @return  The amount of interest released from the token (in Funding Token; DAI)
     */
    function dischargeParticle(
        address _receiver,
        address _contractAddress,
        uint256 _tokenId,
        bytes16 _assetPairId
    )
        external
        nonReentrant
        returns (uint256, uint256)
    {
        uint256 _currentCharge = currentParticleCharge(_contractAddress, _tokenId, _assetPairId);
        return _discharge(_receiver, _contractAddress, _tokenId, _assetPairId, _currentCharge);
    }

    function dischargeParticle(
        address _receiver,
        address _contractAddress,
        uint256 _tokenId,
        bytes16 _assetPairId,
        uint256 _assetAmount
    )
        external
        nonReentrant
        returns (uint256, uint256)
    {
        return _discharge(_receiver, _contractAddress, _tokenId, _assetPairId, _assetAmount);
    }


    /***********************************|
    |         Release Particles         |
    |__________________________________*/

    //
    // Releases the Full amount of Asset + Interest held within the Particle by Asset-Pair
    //
    function releaseParticle(
        address _receiver,
        address _contractAddress,
        uint256 _tokenId,
        bytes16 _assetPairId
    )
        external
        nonReentrant
        returns (uint256)
    {
        INonFungible _tokenInterface = INonFungible(_contractAddress);

        // Validate Token Owner/Operator
        address _tokenOwner = _tokenInterface.ownerOf(_tokenId);
        require((_tokenOwner == msg.sender) || _tokenInterface.isApprovedForAll(_tokenOwner, msg.sender), "E310");

        // Validate Token Burn before Release
        bool requiresBurn = (_contractAddress == chargedParticles);
        if (custom_registeredContract[_contractAddress]) {
            // Does Release Require Token Burn first?
            if (custom_releaseRequiresBurn[_contractAddress]) {
                requiresBurn = true;
            }
        }

        if (requiresBurn) {
            uint256 _tokenUuid = getTokenUUID(_contractAddress, _tokenId);
            assetToBeReleased[_tokenUuid] = msg.sender;
            return 0; // Need to call "finalizeRelease" next, in order to prove token-burn
        }

        // Release Particle to Receiver
        return _payoutFull(_contractAddress, _tokenId, _receiver, _assetPairId);
    }

    function finalizeRelease(
        address _receiver,
        address _contractAddress,
        uint256 _tokenId,
        bytes16 _assetPairId
    )
        external
        returns (uint256)
    {
        INonFungible _tokenInterface = INonFungible(_contractAddress);
        uint256 _tokenUuid = getTokenUUID(_contractAddress, _tokenId);
        address releaser = assetToBeReleased[_tokenUuid];

        // Validate Release Operator
        require(releaser == msg.sender, "E322");

        // Validate Token Burn
        address _tokenOwner = _tokenInterface.ownerOf(_tokenId);
        require(_tokenOwner == address(0x0), "E323");

        // Release Particle to Receiver
        assetToBeReleased[_tokenUuid] = address(0x0);
        return _payoutFull(_contractAddress, _tokenId, _receiver, _assetPairId);
    }


    /***********************************|
    |            Only Owner             |
    |__________________________________*/

    /**
     * @dev Setup the Deposit Fee
     */
    function setDepositFee(uint256 _depositFee) public onlyOwner {
        depositFee = _depositFee;
    }

    /**
     * @dev Register the Charged Particles ERC1155 Token Contract
     */
    function registerChargedParticles(address _chargedParticles) public onlyOwner {
        require(_chargedParticles != address(0x0), "E307");
        chargedParticles = _chargedParticles;
    }

    /**
     * @dev Register Contracts for Asset/Interest Pairs
     */
    function registerAssetPair(string memory _assetPairId, address _assetTokenAddress, address _interestTokenAddress) public onlyOwner {
        bytes16 _assetPair = _toBytes16(_assetPairId);
//        require(address(interestToken[_assetPair]) == address(0x0), "Asset-Pair has already been registered");
        require(_assetTokenAddress != address(0x0), "E308");
        require(_interestTokenAddress != address(0x0), "E309");

        // Register Pair
        assetPairs.push(_assetPair);
        assetPairEnabled[_assetPair] = true;
        assetToken[_assetPair] = IERC20(_assetTokenAddress);
        interestToken[_assetPair] = INucleus(_interestTokenAddress);

        // Allow this contract to Tokenize Interest of Asset
        assetToken[_assetPair].approve(_interestTokenAddress, uint(-1));
    }

    /**
     * @dev Enable/Disable a specific Asset-Pair
     */
    function toggleAssetPair(bytes16 _assetPairId, bool _isEnabled) public onlyOwner {
        require(address(interestToken[_assetPairId]) != address(0x0), "E303");
        assetPairEnabled[_assetPairId] = _isEnabled;
    }

    /**
     * @dev Allows contract owner to withdraw any fees earned
     */
    function withdrawFees(address _receiver) public onlyOwner {
        for (uint i = 0; i < assetPairs.length; i++) {
            bytes16 _assetPairId = assetPairs[i];
            uint256 _interestAmount = collectedFees[_assetPairId];
            if (_interestAmount == 0) {
                _withdrawFees(_receiver, _assetPairId, _interestAmount);
            }
        }

        emit ContractFeesWithdrawn(_receiver);
    }

    /***********************************|
    |         Private Functions         |
    |__________________________________*/

    /**
     * @dev Collects the Required Asset Token from the users wallet
     */
    function _collectAssetToken(address _from, bytes16 _assetPairId, uint256 _assetAmount) internal {
        uint256 _userAssetBalance = assetToken[_assetPairId].balanceOf(_from);
        require(_assetAmount <= _userAssetBalance, "E324");
        require(assetToken[_assetPairId].transferFrom(_from, address(this), _assetAmount), "E325"); // Be sure to Approve this Contract to transfer your Asset Token
    }

    /**
     * @dev Calculates the amount of Interest-bearing Tokens are held within a Particle after Fees
     * @return  The actual amount of Interest-bearing Tokens used to fund the Particle minus fees
     */
    function _getMassByDeposit(
        address _contractAddress,
        uint256 _typeId,
        bytes16 _assetPairId,
        uint256 _interestTokenAmount
    )
        internal
        returns (uint256)
    {
        // Internal Fees
        (uint256 _depositFee, uint256 _customFee, uint256 _creatorFee) = getFeesForDeposit(_contractAddress, _typeId, _interestTokenAmount, _assetPairId);
        collectedFees[_assetPairId] = _depositFee.add(collectedFees[_assetPairId]);

        // Custom Fees for External Contract
        if (_customFee > 0) {
            custom_collectedDepositFees[_contractAddress][_assetPairId] = _customFee.add(custom_collectedDepositFees[_contractAddress][_assetPairId]);
        }

        // Fees for Particle Creators
        if (_creatorFee > 0) {
            creator_collectedDepositFees[_typeId][_assetPairId] = _creatorFee.add(creator_collectedDepositFees[_typeId][_assetPairId]);
        }

        // Total Deposit
        return _interestTokenAmount.sub(_depositFee).sub(_customFee).sub(_creatorFee);
    }


    function _tokenizeInterest(
        address _contractAddress,
        uint256 _typeId,
        bytes16 _assetPairId,
        uint256 _assetAmount
    )
        internal
        returns (uint256)
    {
        address _self = address(this);
        INucleus _interestToken = interestToken[_assetPairId];
        uint256 _preBalance = _interestToken.interestBalance(_self);
        _interestToken.depositAsset(_self, _assetAmount);
        uint256 _postBalance = _interestToken.interestBalance(_self);
        return _getMassByDeposit(_contractAddress, _typeId, _assetPairId, _postBalance.sub(_preBalance));
    }

    function _discharge(
        address _receiver,
        address _contractAddress,
        uint256 _tokenId,
        bytes16 _assetPairId,
        uint256 _assetAmount
    )
        internal
        returns (uint256, uint256)
    {
        INonFungible _tokenInterface = INonFungible(_contractAddress);

        // Validate Token Owner/Operator
        address _tokenOwner = _tokenInterface.ownerOf(_tokenId);
        require((_tokenOwner == msg.sender) || _tokenInterface.isApprovedForAll(_tokenOwner, msg.sender), "E310");

        // Validate Discharge Amount
        uint256 _currentCharge = currentParticleCharge(_contractAddress, _tokenId, _assetPairId);
        require(_currentCharge <= _assetAmount, "E326");

        // Discharge Particle to Receiver
        (uint256 _interestAmount, uint256 _receivedAmount) = _payoutCharge(_receiver, _assetPairId, _assetAmount);

        // Track Interest-bearing Token Balance (Mass of each Particle)
        uint256 _tokenUuid = getTokenUUID(_contractAddress, _tokenId);
        uint256 _interestBalance = interestTokenBalance[_tokenUuid][_assetPairId].sub(_interestAmount);
        interestTokenBalance[_tokenUuid][_assetPairId] = _interestBalance;

        emit DischargedParticle(_contractAddress, _tokenId, _receiver, _assetPairId, _receivedAmount, _interestBalance);

        // AmountReceived, Remaining charge
        return (_receivedAmount, _currentCharge.sub(_receivedAmount));
    }

    /**
     * @dev Pays out a specified amount of the Asset Token
     * @param _receiver     The owner address to pay out to
     * @param _assetAmount  The total amount of DAI to pay out
     */
    function _payoutCharge(address _receiver, bytes16 _assetPairId, uint256 _assetAmount) internal returns (uint256, uint256) {
        address _self = address(this);
        IERC20 _assetToken = assetToken[_assetPairId];
        INucleus _interestToken = interestToken[_assetPairId];

        // Collect Interest
        //  contract receives Asset Token,
        //  function call returns amount of Interest-token exchanged
        uint256 _preAssetAmount = _assetToken.balanceOf(_self);
        uint256 _interestAmount = _interestToken.withdrawAsset(_self, _assetAmount);
        uint256 _postAssetAmount = _assetToken.balanceOf(_self);
        uint256 _receivedAmount = _postAssetAmount.sub(_preAssetAmount);

        // Transfer Interest
        require(_assetToken.transferFrom(_self, _receiver, _receivedAmount), "E327");
        return (_interestAmount, _receivedAmount);
    }

    function _payoutFull(address _contractAddress, uint256 _tokenId, address _receiver, bytes16 _assetPairId) internal returns (uint256) {
        address _self = address(this);
        uint256 _tokenUuid = getTokenUUID(_contractAddress, _tokenId);
        IERC20 _assetToken = assetToken[_assetPairId];
        INucleus _interestToken = interestToken[_assetPairId];

        // Get Interest-bearing Token Balance
        uint256 _interestAmount = interestTokenBalance[_tokenUuid][_assetPairId];

        // Collect Asset + Interest
        uint256 _preAssetAmount = _assetToken.balanceOf(_self);
        _interestToken.withdrawInterest(_self, _interestAmount);
        uint256 _postAssetAmount = _assetToken.balanceOf(_self);
        uint256 _receivedAmount = _postAssetAmount.sub(_preAssetAmount);

        // Transfer Asset + Interest
        require(_assetToken.transferFrom(_self, _receiver, _receivedAmount), "E327");

        // Reset Interest-bearing Token Balance (Mass of each Particle)
        interestTokenBalance[_tokenUuid][_assetPairId] = 0;

        emit ReleasedParticle(_contractAddress, _tokenId, _receiver, _assetPairId, _receivedAmount);
        return _receivedAmount;
    }

    function _withdrawFees(address _receiver, bytes16 _assetPairId, uint256 _interestAmount) internal {
        address _self = address(this);
        IERC20 _assetToken = assetToken[_assetPairId];
        INucleus _interestToken = interestToken[_assetPairId];

        // Collect Deposit Fees
        uint256 _preAssetAmount = _assetToken.balanceOf(_self);
        _interestToken.withdrawInterest(_self, _interestAmount);
        uint256 _postAssetAmount = _assetToken.balanceOf(_self);
        uint256 _receivedAmount = _postAssetAmount.sub(_preAssetAmount);

        // Transfer Fees in Asset Tokens
        require(_assetToken.transferFrom(_self, _receiver, _receivedAmount), "E327");
    }

    //
    // This seems rather limiting;
    //   Many (older) tokens don't implement ERC165 (CryptoKitties for one)
    //   Doesn't currently account for ERC998 - composable tokens
    //   Doesn't consider newer token standards
    //
//    function _isNonFungibleToken(address _contractAddress, uint256 _tokenId) internal returns (bool) {
//        // Check Token Interface to ensure compliance
//        IERC165 tokenInterface = IERC165(_contractAddress);
//
//        // ERC721
//        bool is721 = tokenInterface.supportsInterface(INTERFACE_SIGNATURE_ERC721);
//        if (is721) { return true; }
//
//        // Is ERC1155 - Non-Fungible
//        bool is1155 = tokenInterface.supportsInterface(INTERFACE_SIGNATURE_ERC1155);
//        if (!is1155) { return false; }
//        return (_tokenId & TYPE_NF_BIT == TYPE_NF_BIT);
//    }

    function _toBytes16(string memory source) private pure returns (bytes16 result) {
        bytes memory tmp = bytes(source);
        if (tmp.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 16))
        }
    }
}

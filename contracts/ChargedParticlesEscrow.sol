// ChargedParticlesEscrow.sol -- Charged Particles
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
//      328         Access Control: Sender does not have required Role


pragma solidity ^0.5.16;

import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/introspection/IERC165.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "./lib/AccessControl.sol";
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
contract ChargedParticlesEscrow is Initializable, AccessControl, ReentrancyGuard {
    using SafeMath for uint256;

    uint256 constant internal DEPOSIT_FEE_MODIFIER = 1e4;   // 10000  (100%)
    uint256 constant internal MAX_CUSTOM_DEPOSIT_FEE = 5e3; // 5000   (50%)
    uint256 constant internal MIN_DEPOSIT_FEE = 1e6;        // 1000000 (0.000000000001 ETH  or  1000000 WEI)

    uint256 constant internal TYPE_NF_BIT = 1 << 255;                   // ERC1155 Common Non-fungible Token Bit
    uint256 constant internal TYPE_MASK = uint256(uint128(~0)) << 128;  // ERC1155 Common Non-fungible Type Mask

    bytes32 constant public ROLE_DAO_GOV = keccak256("ROLE_DAO_GOV");
    bytes32 constant public ROLE_MAINTAINER = keccak256("ROLE_MAINTAINER");

    bytes4 constant internal INTERFACE_SIGNATURE_ERC721 = 0x80ac58cd;
    bytes4 constant internal INTERFACE_SIGNATURE_ERC1155 = 0xd9b67a26;

    //
    // Particle Terminology
    //
    //   Particle               - Non-fungible Token
    //   Plasma                 - Fungible Token
    //   Mass                   - Underlying Asset of a Token (ex; DAI)
    //   Charge                 - Accrued Interest on the Underlying Asset of a Token
    //   Charged Particle       - A Token that has a Mass and a Positive Charge
    //   Neutral Particle       - A Token that has a Mass and No Charge
    //   Energize / Recharge    - Deposit of an Underlying Asset into a Token
    //   Discharge              - Withdraw the Accrued Interest of a Token leaving the Particle with its initial Mass
    //   Release                - Withdraw the Underlying Asset & Accrued Interest of a Token leaving the Particle with No Mass
    //                              - Released Tokens are either Burned/Destroyed or left in their Original State as an NFT
    //

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

    //      Contract => Deposit Fees to be earned for Contract Owner
    mapping (address => uint256) internal custom_assetDepositFee;

    //      Contract => Allowed Limit of Asset Token [min, max]
    mapping (address => uint256) internal custom_assetDepositMin;
    mapping (address => uint256) internal custom_assetDepositMax;

    /***********************************|
    |         Per Token Settings        |
    |  (specific to Charged Particles)  |
    |__________________________________*/

    //        TypeID => Address that collects the custom fees for a specific type
    mapping (uint256 => address) internal creator_feeCollector;

    //        TypeID => Specific Asset-Pair that is allowed (otherwise, any Asset-Pair is allowed)
    mapping (uint256 => bytes16) internal creator_assetPairId;

    //        TypeID => Deposit Fees to be earned for Type Creator
    mapping (uint256 => uint256) internal creator_assetDepositFee;

    //        TypeID => Allowed Limit of Asset Token [min, max]
    mapping (uint256 => uint256) internal creator_assetDepositMin;
    mapping (uint256 => uint256) internal creator_assetDepositMax;

    /***********************************|
    |     Variables/Events/Modifiers    |
    |__________________________________*/

    // The Charged Particles ERC1155 Token Contract Address
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

    //     TokenUUID => Operator
    mapping (uint256 => address) internal tokenDischargeApprovals;                       // Operator Approval per Token

    //     TokenUUID => Token Release Operator
    mapping (uint256 => address) internal assetToBeReleasedBy;

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
    //    When the particle reaches 100% "Mass" or more it can be "Released" (or burned) to reclaim the underlying
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
    event CreatorFeesWithdrawn(uint256 indexed _typeId, address indexed _creatorAddress);
    event DischargeApproval(address indexed _contractAddress, uint256 indexed _tokenId, address indexed _owner, address _operator);
    event EnergizedParticle(address indexed _contractAddress, uint256 indexed _tokenId, bytes16 _assetPairId, uint256 _assetBalance, uint256 _interestBalance);
    event DischargedParticle(address indexed _contractAddress, uint256 indexed _tokenId, address indexed _receiver, bytes16 _assetPairId, uint256 _receivedAmount, uint256 _interestBalance);
    event ReleasedParticle(address indexed _contractAddress, uint256 indexed _tokenId, address indexed _receiver, bytes16 _assetPairId, uint256 _receivedAmount);
    event ContractFeesWithdrawn(address indexed _receiver);

    /***********************************|
    |          Initialization           |
    |__________________________________*/

    function initialize(address _sender, address _dao, address _maintainer) public initializer {
        ReentrancyGuard.initialize();
        _setupRole(DEFAULT_ADMIN_ROLE, _sender);
        _setupRole(ROLE_DAO_GOV, _dao);
        _setupRole(ROLE_MAINTAINER, _maintainer);
        version = "v0.3.3";
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

    function getAssetMinDeposit(address _contractAddress, uint256 _typeId) public view returns (uint256) {
        if (_contractAddress == chargedParticles) {
            return creator_assetDepositMin[_typeId];
        }
        return custom_assetDepositMin[_contractAddress];
    }

    function getAssetMaxDeposit(address _contractAddress, uint256 _typeId) public view returns (uint256) {
        if (_contractAddress == chargedParticles) {
            return creator_assetDepositMax[_typeId];
        }
        return custom_assetDepositMax[_contractAddress];
    }

    /**
     * @notice Sets an Operator as Approved to Discharge a specific Token
     *    This allows an operator to release the interest-portion only
     * @param _contractAddress  The Address to the Contract of the Token
     * @param _tokenId          The ID of the Token
     * @param _operator         The Address of the Operator to Approve
     */
    function setDischargeApproval(address _contractAddress, uint256 _tokenId, address _operator) public {
        INonFungible _tokenInterface = INonFungible(_contractAddress);
        address _tokenOwner = _tokenInterface.ownerOf(_tokenId);
        require(_operator != _tokenOwner, "310");
        require(msg.sender == _tokenOwner || _tokenInterface.isApprovedForAll(_tokenOwner, msg.sender), "310");

        uint256 _tokenUuid = getTokenUUID(_contractAddress, _tokenId);
        tokenDischargeApprovals[_tokenUuid] = _operator;
        emit DischargeApproval(_contractAddress, _tokenId, _tokenOwner, _operator);
    }

    /**
     * @notice Gets the Approved Discharge-Operator of a specific Token
     * @param _contractAddress  The Address to the Contract of the Token
     * @param _tokenId          The ID of the Token
     * @param _operator         The Address of the Operator to check
     * @return  True if the _operator is Approved
     */
    function isApprovedForDischarge(address _contractAddress, uint256 _tokenId, address _operator) public view returns (bool) {
        uint256 _tokenUuid = getTokenUUID(_contractAddress, _tokenId);
        return tokenDischargeApprovals[_tokenUuid] == _operator;
    }

    /**
     * @notice Calculates the amount of Fees to be paid for a specific deposit amount
     *   Fees are calculated in Interest-Token as they are the type collected for Fees
     * @param _contractAddress      The Address to the Contract of the Token
     * @param _typeId               The Type-ID of the Token
     * @param _interestTokenAmount  The Amount of Interest-Token to calculate Fees on
     * @return  The amount of base fees and the amount of custom/creator fees
     */
    function getFeesForDeposit(
        address _contractAddress,
        uint256 _typeId,
        uint256 _interestTokenAmount
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
            uint256 _creatorFeeSetting = creator_assetDepositFee[_typeId];
            if (_creatorFeeSetting > 0) {
                _creatorFee = _interestTokenAmount.mul(_creatorFeeSetting).div(DEPOSIT_FEE_MODIFIER);
            }
        } else {
            uint256 _customFeeSetting = custom_assetDepositFee[_contractAddress];
            if (_customFeeSetting > 0) {
                _customFee = _interestTokenAmount.mul(_customFeeSetting).div(DEPOSIT_FEE_MODIFIER);
            }
        }

        return (_depositFee, _customFee, _creatorFee);
    }

    /**
     * @notice Calculates the Total Fee to be paid for a specific deposit amount
     *   Fees are calculated in Interest-Token as they are the type collected for Fees
     * @param _contractAddress      The Address to the Contract of the Token
     * @param _typeId               The Type-ID of the Token
     * @param _interestTokenAmount  The Amount of Interest-Token to calculate Fees on
     * @return  The total amount of base fees plus the amount of custom/creator fees
     */
    function getFeeForDeposit(
        address _contractAddress,
        uint256 _typeId,
        uint256 _interestTokenAmount
    )
        public
        view
        returns (uint256)
    {
        (uint256 _depositFee, uint256 _customFee, uint256 _creatorFee) = getFeesForDeposit(_contractAddress, _typeId, _interestTokenAmount);
        return _depositFee.add(_customFee).add(_creatorFee);
    }

    /**
     * @notice Gets the Amount of Asset Tokens that have been Deposited into the Particle
     *    representing the Mass of the Particle.
     * @param _contractAddress  The Address to the External Contract of the Token
     * @param _tokenId          The ID of the Token within the External Contract
     * @param _assetPairId      The Asset-Pair ID to check the Asset balance of
     * @return  The Amount of underlying Assets held within the Token
     */
    function baseParticleMass(address _contractAddress, uint256 _tokenId, bytes16 _assetPairId) public view returns (uint256) {
        uint256 _tokenUuid = getTokenUUID(_contractAddress, _tokenId);
        return assetTokenDeposited[_tokenUuid][_assetPairId];
    }

    /**
     * @notice Gets the amount of Interest that the Particle has generated representing 
     *    the Charge of the Particle
     * @param _contractAddress  The Address to the External Contract of the Token
     * @param _tokenId          The ID of the Token within the External Contract
     * @param _assetPairId      The Asset-Pair ID to check the Asset balance of
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

    /**
     * @notice Checks if an Account is the Owner of a Contract
     *    When Custom Contracts are registered, only the "owner" or operator of the Contract
     *    is allowed to register them and define custom rules for how their tokens are "Charged".
     *    Otherwise, any token can be "Charged" according to the default rules of Charged Particles.
     * @param _account   The Account to check if it is the Owner of the specified Contract
     * @param _contract  The Address to the External Contract to check
     * @return True if the _account is the Owner of the _contract
     */
    function isContractOwner(address _account, address _contract) public view returns (bool) {
        address _contractOwner = IOwnable(_contract).owner();
        return _contractOwner != address(0x0) && _contractOwner == _account;
    }

    /**
     * @notice Registers a external ERC-721 Contract in order to define Custom Rules for Tokens
     * @param _contractAddress  The Address to the External Contract of the Token
     */
    function registerContractType(address _contractAddress) external {
        // Check Token Interface to ensure compliance
        IERC165 _tokenInterface = IERC165(_contractAddress);
        bool _is721 = _tokenInterface.supportsInterface(INTERFACE_SIGNATURE_ERC721);
        bool _is1155 = _tokenInterface.supportsInterface(INTERFACE_SIGNATURE_ERC1155);
        require(_is721 || _is1155, "E312");

        // Check Contract Owner to prevent random people from setting Limits
        require(isContractOwner(msg.sender, _contractAddress), "E305");

        // Contract Registered!
        custom_registeredContract[_contractAddress] = true;

        emit RegisterParticleContract(_contractAddress);
    }

    /**
     * @notice Registers the "Release-Burn" Custom Rule on an external ERC-721 Token Contract
     *   When enabled, tokens that are "Charged" will require the Token to be Burned before
     *   the underlying asset is Released.
     * @param _contractAddress       The Address to the External Contract of the Token
     * @param _releaseRequiresBurn   True if the External Contract requires tokens to be Burned before Release
     */
    function registerContractSetting_ReleaseBurn(address _contractAddress, bool _releaseRequiresBurn) external {
        require(custom_registeredContract[_contractAddress], "E304");
        require(isContractOwner(msg.sender, _contractAddress), "E305");
        require(custom_assetPairId[_contractAddress].length > 0, "E313");

        custom_releaseRequiresBurn[_contractAddress] = _releaseRequiresBurn;
    }

    /**
     * @notice Registers the "Asset-Pair" Custom Rule on an external ERC-721 Token Contract
     *   The Asset-Pair Rule defines which Asset-Token & Interest-bearing Token Pair can be used to
     *   "Charge" the Token.  If not set, any enabled Asset-Pair can be used.
     * @param _contractAddress  The Address to the External Contract of the Token
     * @param _assetPairId      The Asset-Pair required for Energizing a Token; otherwise Any Asset-Pair is allowed
     */
    function registerContractSetting_AssetPair(address _contractAddress, bytes16 _assetPairId) external {
        require(custom_registeredContract[_contractAddress], "E304");
        require(isContractOwner(msg.sender, _contractAddress), "E305");

        if (_assetPairId.length > 0) {
            require(assetPairEnabled[_assetPairId], "E301");
        } else {
            require(custom_releaseRequiresBurn[_contractAddress] != true, "E314");
        }

        custom_assetPairId[_contractAddress] = _assetPairId;
    }

    /**
     * @notice Registers the "Deposit Fee" Custom Rule on an external ERC-721 Token Contract
     *    When set, every Token of the Custom ERC-721 Contract that is "Energized" pays a Fee to the
     *    Contract Owner denominated in the Interest-bearing Token of the Asset-Pair
     * @param _contractAddress  The Address to the External Contract of the Token
     * @param _depositFee       The Deposit Fee as a Percentage represented as 10000 = 100%
     *    A value of "50" would represent a Fee of 0.5% of the Funding Asset ((50 / 10000) * 100)
     *    This allows a fee as low as 0.01%  (value of "1")
     */
    function registerContractSetting_DepositFee(address _contractAddress, uint256 _depositFee) external {
        require(custom_registeredContract[_contractAddress], "E304");
        require(isContractOwner(msg.sender, _contractAddress), "E305");
        require(_depositFee <= MAX_CUSTOM_DEPOSIT_FEE, "E315");

        custom_assetDepositFee[_contractAddress] = _depositFee;
    }

    /**
     * @notice Registers the "Minimum Deposit Amount" Custom Rule on an external ERC-721 Token Contract
     *    When set, every Token of the Custom ERC-721 Contract must be "Energized" with at least this 
     *    amount of Asset Token.
     * @param _contractAddress  The Address to the External Contract of the Token
     * @param _minDeposit       The Minimum Deposit required for a Token
     */
    function registerContractSetting_MinDeposit(address _contractAddress, uint256 _minDeposit) external {
        require(custom_registeredContract[_contractAddress], "E304");
        require(isContractOwner(msg.sender, _contractAddress), "E305");
        require(_minDeposit == 0 || _minDeposit > MIN_DEPOSIT_FEE, "E316");

        custom_assetDepositMin[_contractAddress] = _minDeposit;
    }

    /**
     * @notice Registers the "Maximum Deposit Amount" Custom Rule on an external ERC-721 Token Contract
     *    When set, every Token of the Custom ERC-721 Contract must be "Energized" with at most this 
     *    amount of Asset Token.
     * @param _contractAddress  The Address to the External Contract of the Token
     * @param _maxDeposit       The Maximum Deposit allowed for a Token
     */
    function registerContractSetting_MaxDeposit(address _contractAddress, uint256 _maxDeposit) external {
        require(custom_registeredContract[_contractAddress], "E304");
        require(isContractOwner(msg.sender, _contractAddress), "E305");

        custom_assetDepositMax[_contractAddress] = _maxDeposit;
    }


    /***********************************|
    |     Register Creator Settings     |
    |__________________________________*/

    /**
     * @notice Checks if the Account is the Type Creator of a Particle
     * @param _account  The Address of the Account to check
     * @param _typeId   The Type ID of the Particle to check
     * @return  True if the _account is the _typeId Creator
     */
    function isTypeCreator(address _account, uint256 _typeId) public view returns (bool) {
        if (_account == chargedParticles) { return true; }
        address _typeCreator = IChargedParticles(chargedParticles).getTypeCreator(_typeId);
        return _typeCreator == _account;
    }

    /**
     * @notice Registers the "Fee Collector" Custom Rule on a Particle Type
     *    The Creator of a Particle Type can set a Custom Fee Collector Address
     * @param _typeId         The Type ID of the Token
     * @param _feeCollector   The Address of the Fee Collector
     */
    function registerCreatorSetting_FeeCollector(uint256 _typeId, address _feeCollector) external {
        require(isTypeCreator(msg.sender, _typeId), "E306");
        creator_feeCollector[_typeId] = _feeCollector;
    }

    /**
     * @notice Registers the "Asset-Pair" Custom Rule on a Particle Type
     *   The Asset-Pair Rule defines which Asset-Token & Interest-bearing Token Pair can be used to
     *   "Charge" the Token.  If not set, any enabled Asset-Pair can be used.
     * @param _typeId           The Type ID of the Token
     * @param _assetPairId      The Asset-Pair required for Energizing a Token; otherwise Any Asset-Pair is allowed
     */
    function registerCreatorSetting_AssetPair(uint256 _typeId, bytes16 _assetPairId) external {
        require(isTypeCreator(msg.sender, _typeId), "E306");

        if (_assetPairId.length > 0) {
            require(assetPairEnabled[_assetPairId], "E301");
        }

        creator_assetPairId[_typeId] = _assetPairId;
    }

    /**
     * @notice Registers the "Deposit Fee" Custom Rule on a Particle Type
     *    When set, every Token of this Type that is "Energized" pays a Fee to the
     *    Creator denominated in the Interest-bearing Token of the Asset-Pair
     * @param _typeId           The Type ID of the Token
     * @param _depositFee       The Deposit Fee as a Percentage represented as 10000 = 100%
     *    A value of "50" would represent a Fee of 0.5% of the Funding Asset ((50 / 10000) * 100)
     *    This allows a fee as low as 0.01%  (value of "1")
     */
    function registerCreatorSetting_DepositFee(uint256 _typeId, uint256 _depositFee) external {
        require(isTypeCreator(msg.sender, _typeId), "E306");
        require(_depositFee <= MAX_CUSTOM_DEPOSIT_FEE, "E315");

        creator_assetDepositFee[_typeId] = _depositFee;
    }

    /**
     * @notice Registers the "Minimum Deposit Amount" Custom Rule oa Particle Type
     *    When set, every Token of this Type must be "Energized" with at least this 
     *    amount of Asset Token.
     * @param _typeId           The Type ID of the Token
     * @param _minDeposit       The Minimum Deposit required for a Token
     */
    function registerCreatorSetting_MinDeposit(uint256 _typeId, uint256 _minDeposit) external {
        require(isTypeCreator(msg.sender, _typeId), "E306");
        require(_minDeposit == 0 || _minDeposit > MIN_DEPOSIT_FEE, "E316");

        creator_assetDepositMin[_typeId] = _minDeposit;
    }

    /**
     * @notice Registers the "Maximum Deposit Amount" Custom Rule a Particle Type
     *    When set, every Token of this Type must be "Energized" with at most this 
     *    amount of Asset Token.
     * @param _typeId           The Type ID of the Token
     * @param _maxDeposit       The Maximum Deposit allowed for a Token
     */
    function registerCreatorSetting_MaxDeposit(uint256 _typeId, uint256 _maxDeposit) external {
        require(isTypeCreator(msg.sender, _typeId), "E306");

        creator_assetDepositMax[_typeId] = _maxDeposit;
    }

    /***********************************|
    |           Collect Fees            |
    |__________________________________*/

    /**
     * @notice Allows External Contract Owners to withdraw any Custom Fees earned
     * @param _contractAddress  The Address to the External Contract to withdraw Collected Fees for
     * @param _receiver         The Address of the Receiver of the Collected Fees
     */
    function withdrawContractFees(address _contractAddress, address _receiver) external nonReentrant {
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
     * @notice Allows Particle Type Creators to withdraw any Fees earned
     * @param _typeId  The Type ID to withdraw Collected Fees for
     */
    function withdrawCreatorFees(uint256 _typeId) external nonReentrant {
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
            emit CreatorFeesWithdrawn(_typeId, creator_feeCollector[_typeId]);
        }
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
     * @param _contractAddress  The Address to the Contract of the Token to Energize
     * @param _tokenId          The ID of the Token to Energize
     * @param _assetPairId      The Asset-Pair to Energize the Token with 
     * @param _assetAmount      The Amount of Asset Token to Energize the Token with
     * @return  The amount of Interest-bearing Tokens added to the escrow for the Token
     */
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
        uint256 _typeId = _tokenId;
        if (_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) {
            _typeId = _tokenId & TYPE_MASK;
        }
        uint256 _tokenUuid = getTokenUUID(_contractAddress, _tokenId);
        uint256 _existingBalance = assetTokenDeposited[_tokenUuid][_assetPairId];
        uint256 _newBalance = _assetAmount.add(_existingBalance);

        // Validate Minimum-Required Balance
        require(_newBalance >= MIN_DEPOSIT_FEE, "E319");

        // Validate Type-Creator Settings
        if (_contractAddress == chargedParticles) {
            // Valid Asset-Pair?
            if (creator_assetPairId[_typeId].length > 0) {
                require(_assetPairId == creator_assetPairId[_typeId], "E302");
            }

            // Valid Amount?
            if (creator_assetDepositMin[_typeId] > 0) {
                require(_newBalance >= creator_assetDepositMin[_typeId], "E320");
            }
            if (creator_assetDepositMax[_typeId] > 0) {
                require(_newBalance <= creator_assetDepositMax[_typeId], "E321");
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
                if (custom_assetDepositMin[_contractAddress] > 0) {
                    require(_newBalance >= custom_assetDepositMin[_contractAddress], "E320");
                }
                if (custom_assetDepositMax[_contractAddress] > 0) {
                    require(_newBalance <= custom_assetDepositMax[_contractAddress], "E321");
                }
            }
        }

        // Collect Asset Token (reverts on fail)
        //   Has to be msg.sender, otherwise anyone could energize anyone else's particles,
        //   with the victim's assets, provided the victim has approved this contract in the past.
        //   If contracts wish to energize a particle, they must first collect the asset
        //   from the user, and approve this contract to transfer from the source contract
        _collectAssetToken(msg.sender, _assetPairId, _assetAmount); 

        // Tokenize Interest
        uint256 _interestAmount = _tokenizeInterest(_contractAddress, _typeId, _assetPairId, _assetAmount);

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

    /***********************************|
    |        Discharge Particles        |
    |__________________________________*/

    /**
     * @notice Allows the owner or operator of the Token to collect or transfer the interest generated
     *         from the token without removing the underlying Asset that is held within the token.
     * @param _receiver         The Address to Receive the Discharged Asset Tokens
     * @param _contractAddress  The Address to the Contract of the Token to Discharge
     * @param _tokenId          The ID of the Token to Discharge
     * @param _assetPairId      The Asset-Pair to Discharge from the Token 
     * @return  Two values; 1: Amount of Asset Token Received, 2: Remaining Charge of the Token
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

    /**
     * @notice Allows the owner or operator of the Token to collect or transfer a specific amount the interest
     *         generated from the token without removing the underlying Asset that is held within the token.
     * @param _receiver         The Address to Receive the Discharged Asset Tokens
     * @param _contractAddress  The Address to the Contract of the Token to Discharge
     * @param _tokenId          The ID of the Token to Discharge
     * @param _assetPairId      The Asset-Pair to Discharge from the Token 
     * @param _assetAmount      The specific amount of Asset Token to Discharge from the Token
     * @return  Two values; 1: Amount of Asset Token Received, 2: Remaining Charge of the Token
     */
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
     * @param _contractAddress  The Address to the Contract of the Token to Release
     * @param _tokenId          The ID of the Token to Release
     * @param _assetPairId      The Asset-Pair to Release from the Token 
     * @return  The Total Amount of Asset Token Released including all converted Interest
     */
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
            assetToBeReleasedBy[_tokenUuid] = msg.sender;
            return 0; // Need to call "finalizeRelease" next, in order to prove token-burn
        }

        // Release Particle to Receiver
        return _payoutFull(_contractAddress, _tokenId, _receiver, _assetPairId);
    }

    /**
     * @notice Finalizes the Release of a Particle when that Particle requires Burn before Release
     * @param _receiver         The Address to Receive the Released Asset Tokens
     * @param _contractAddress  The Address to the Contract of the Token to Release
     * @param _tokenId          The ID of the Token to Release
     * @param _assetPairId      The Asset-Pair to Release from the Token 
     * @return  The Total Amount of Asset Token Released including all converted Interest
     */
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
        address releaser = assetToBeReleasedBy[_tokenUuid];

        // Validate Release Operator
        require(releaser == msg.sender, "E322");

        // Validate Token Burn
        address _tokenOwner = _tokenInterface.ownerOf(_tokenId);
        require(_tokenOwner == address(0x0), "E323");

        // Release Particle to Receiver
        assetToBeReleasedBy[_tokenUuid] = address(0x0);
        return _payoutFull(_contractAddress, _tokenId, _receiver, _assetPairId);
    }


    /***********************************|
    |          Only Admin/DAO           |
    |__________________________________*/

    /**
     * @dev Setup the Base Deposit Fee for the Escrow
     */
    function setDepositFee(uint256 _depositFee) external {
        require(hasRole(ROLE_DAO_GOV, msg.sender), "E328");
        depositFee = _depositFee;
    }

    /**
     * @dev Register the Charged Particles ERC1155 Token Contract
     */
    function registerChargedParticles(address _chargedParticles) external {
        require(hasRole(ROLE_DAO_GOV, msg.sender), "E328");
        require(_chargedParticles != address(0x0), "E307");
        chargedParticles = _chargedParticles;
    }

    /**
     * @dev Register Contracts for Asset/Interest Pairs
     */
    function registerAssetPair(string calldata _assetPairId, address _assetTokenAddress, address _interestTokenAddress) external {
        require(hasRole(ROLE_MAINTAINER, msg.sender), "E328");

        bytes16 _assetPair = _toBytes16(_assetPairId);
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
    function toggleAssetPair(bytes16 _assetPairId, bool _isEnabled) external {
        require(hasRole(ROLE_DAO_GOV, msg.sender), "E328");
        require(address(interestToken[_assetPairId]) != address(0x0), "E303");
        assetPairEnabled[_assetPairId] = _isEnabled;
    }

    /**
     * @dev Allows Escrow Contract Owner/DAO to withdraw any fees earned
     */
    function withdrawFees(address _receiver) external {
        require(hasRole(ROLE_DAO_GOV, msg.sender), "E328");

        for (uint i = 0; i < assetPairs.length; i++) {
            bytes16 _assetPairId = assetPairs[i];
            uint256 _interestAmount = collectedFees[_assetPairId];
            if (_interestAmount > 0) {
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
        (uint256 _depositFee, uint256 _customFee, uint256 _creatorFee) = getFeesForDeposit(_contractAddress, _typeId, _interestTokenAmount);
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

    /**
     * @dev Converts an Asset Token to an Interest Token
     */
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

    /**
     * @dev Discharges the Interest from a Token
     */
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
        require((_tokenOwner == msg.sender) || isApprovedForDischarge(_contractAddress, _tokenId, msg.sender), "E310");

        // Validate Discharge Amount
        uint256 _currentCharge = currentParticleCharge(_contractAddress, _tokenId, _assetPairId);
        require(_currentCharge <= _assetAmount, "E326");

        // Precalculate Amount to Discharge to Receiver
        (uint256 _interestAmount, uint256 _receivedAmount) = _siphonAsset(_assetPairId, _assetAmount);

        // Track Interest-bearing Token Balance (Mass of each Particle)
        uint256 _tokenUuid = getTokenUUID(_contractAddress, _tokenId);
        uint256 _interestBalance = interestTokenBalance[_tokenUuid][_assetPairId].sub(_interestAmount);
        interestTokenBalance[_tokenUuid][_assetPairId] = _interestBalance;

        // Transfer Assets to Receiver
        _payoutAssets(_receiver, _assetPairId, _receivedAmount);

        emit DischargedParticle(_contractAddress, _tokenId, _receiver, _assetPairId, _receivedAmount, _interestBalance);

        // AmountReceived, Remaining charge
        return (_receivedAmount, _currentCharge.sub(_receivedAmount));
    }

    /**
     * @dev Collects a Specified Asset Amount of the Asset Token from the Interest Token stored for the Particle 
     */
    function _siphonAsset(bytes16 _assetPairId, uint256 _assetAmount) internal returns (uint256, uint256) {
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
        return (_interestAmount, _receivedAmount);
    }

    /**
     * @dev Collects a Specified Interest Amount of the Asset Token from the Interest Token stored for the Particle 
     */
    function _siphonInterest(bytes16 _assetPairId, uint256 _interestAmount) internal returns (uint256, uint256) {
        address _self = address(this);
        IERC20 _assetToken = assetToken[_assetPairId];
        INucleus _interestToken = interestToken[_assetPairId];

        // Collect Interest
        //  contract receives Asset Token,
        uint256 _preAssetAmount = _assetToken.balanceOf(_self);
        _interestToken.withdrawInterest(_self, _interestAmount);
        uint256 _postAssetAmount = _assetToken.balanceOf(_self);
        uint256 _receivedAmount = _postAssetAmount.sub(_preAssetAmount);

        // Transfer Interest
        return (_interestAmount, _receivedAmount);
    }

    /**
     * @dev Pays out a specified amount of the Asset Token
     */
    function _payoutAssets(address _receiver, bytes16 _assetPairId, uint256 _assetAmount) internal {
        address _self = address(this);
        IERC20 _assetToken = assetToken[_assetPairId];
        require(_assetToken.transferFrom(_self, _receiver, _assetAmount), "E327");
    }

    /**
     * @dev Pays out the full amount of the Asset Token + Interest Token
     */
    function _payoutFull(address _contractAddress, uint256 _tokenId, address _receiver, bytes16 _assetPairId) internal returns (uint256) {
        // Get Interest-bearing Token Balance & Reset
        uint256 _tokenUuid = getTokenUUID(_contractAddress, _tokenId);
        uint256 _interestAmount = interestTokenBalance[_tokenUuid][_assetPairId];
        interestTokenBalance[_tokenUuid][_assetPairId] = 0;

        // Determine Amount of Assets to Transfer to Receiver
        (, uint256 _receivedAmount) = _siphonInterest(_assetPairId, _interestAmount);

        // Transfer Assets to Receiver
        _payoutAssets(_receiver, _assetPairId, _receivedAmount);

        emit ReleasedParticle(_contractAddress, _tokenId, _receiver, _assetPairId, _receivedAmount);
        return _receivedAmount;
    }

    /**
     * @dev Withdraws Fees in the form of Asset Tokens
     */
    function _withdrawFees(address _receiver, bytes16 _assetPairId, uint256 _interestAmount) internal {
        // Determine Amount of Assets to Transfer to Receiver
        (, uint256 _receivedAmount) = _siphonInterest(_assetPairId, _interestAmount);

        // Transfer Assets to Receiver
        _payoutAssets(_receiver, _assetPairId, _receivedAmount);
    }

    //
    // This seems rather limiting;
    //   Many (older) tokens don't implement ERC165 (CryptoKitties for one)
    //   Doesn't currently account for ERC998 - composable tokens
    //   Doesn't consider newer token standards
    //   Could be used to potentially avoid ERC777
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

    /**
     * @dev Converts a string value into a bytes16 value
     */
    function _toBytes16(string memory _source) private pure returns (bytes16 _result) {
        bytes memory _tmp = bytes(_source);
        if (_tmp.length == 0) {
            return 0x0;
        }

        assembly {
            _result := mload(add(_source, 16))
        }
    }
}

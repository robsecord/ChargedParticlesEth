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

import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/introspection/IERC165.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IChargedParticlesEscrowManager.sol";
import "./interfaces/IEscrow.sol";

import "./lib/Common.sol";

interface IOwnable {
    function owner() external view returns (address);
}

interface INonFungible {
    function ownerOf(uint256 _tokenId) external view returns (address);
    function isApprovedForAll(address _owner, address _operator) external view returns (bool);
}

/**
 * @notice Charged Particles Escrow Contract
 */
contract ChargedParticlesEscrowManager is IChargedParticlesEscrowManager, Initializable, AccessControlUpgradeSafe, ReentrancyGuardUpgradeSafe, Common {
    using SafeMath for uint256;

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

    // Asset-Pair-IDs
    bytes16[] internal assetPairs;
    // mapping (bytes16 => bool) internal assetPairEnabled;
    mapping (bytes16 => IEscrow) internal assetPairEscrow;

    //     TokenUUID => Operator Approval per Token
    mapping (uint256 => address) internal tokenDischargeApprovals;

    //     TokenUUID => Token Release Operator
    mapping (uint256 => address) internal assetToBeReleasedBy;

    // Optional Limits set by Owner of External Token Contracts;
    //  - Any user can add any ERC721 or ERC1155 token as a Charged Particle without Limits,
    //    unless the Owner of the ERC721 or ERC1155 token contract registers the token here
    //    and sets the Custom Limits for their token(s)

    //      Contract => Has this contract address been Registered with Custom Limits?
    mapping (address => bool) internal customRegisteredContract;

    //      Contract => Does the Release-Action require the Charged Particle Token to be burned first?
    mapping (address => bool) internal customReleaseRequiresBurn;

    //      Contract => Specific Asset-Pair that is allowed (otherwise, any Asset-Pair is allowed)
    mapping (address => bytes16) internal customAssetPairId;

    //      Contract => Deposit Fees to be earned for Contract Owner
    mapping (address => uint256) internal customAssetDepositFee;

    //      Contract => Allowed Limit of Asset Token [min, max]
    mapping (address => uint256) internal customAssetDepositMin;
    mapping (address => uint256) internal customAssetDepositMax;

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
    // Modifiers
    //

    // Throws if called by any account other than the Charged Particles DAO contract.
    modifier onlyDao() {
        require(hasRole(ROLE_DAO_GOV, msg.sender), "CPEM: INVALID_DAO");
        _;
    }

    // Throws if called by any account other than the Charged Particles Maintainer.
    modifier onlyMaintainer() {
        require(hasRole(ROLE_MAINTAINER, msg.sender), "CPEM: INVALID_MAINTAINER");
        _;
    }

    //
    // Events
    //

    event RegisterParticleContract(
        address indexed _contractAddress
    );
    event DischargeApproval(
        address indexed _contractAddress, 
        uint256 indexed _tokenId, 
        address indexed _owner, 
        address _operator
    );
    event EnergizedParticle(
        address indexed _contractAddress, 
        uint256 indexed _tokenId, 
        bytes16 _assetPairId, 
        uint256 _assetBalance
    );
    event DischargedParticle(
        address indexed _contractAddress, 
        uint256 indexed _tokenId, 
        address indexed _receiver, 
        bytes16 _assetPairId, 
        uint256 _receivedAmount, 
        uint256 _interestBalance
    );
    event ReleasedParticle(
        address indexed _contractAddress, 
        uint256 indexed _tokenId, 
        address indexed _receiver, 
        bytes16 _assetPairId, 
        uint256 _receivedAmount
    );
    event FeesWithdrawn(
        address indexed _contractAddress, 
        address indexed _receiver, 
        bytes16 _assetPairId, 
        uint256 _interestAmoount
    );

    /***********************************|
    |          Initialization           |
    |__________________________________*/

    function initialize() public initializer {
        __ReentrancyGuard_init();
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ROLE_DAO_GOV, msg.sender);
        _setupRole(ROLE_MAINTAINER, msg.sender);
        version = "v0.4.1";
    }

    /***********************************|
    |         Particle Physics          |
    |__________________________________*/

    function isAssetPairEnabled(bytes16 _assetPairId) external override view returns (bool) {
        return _isAssetPairEnabled(_assetPairId);
    }

    function getAssetPairsCount() external override view returns (uint) {
        return assetPairs.length;
    }

    function getAssetPairByIndex(uint _index) external override view returns (bytes16) {
        require(_index >= 0 && _index < assetPairs.length, "CPEM: INVALID_INDEX");
        return assetPairs[_index];
    }

    function getAssetTokenEscrow(bytes16 _assetPairId) external override view returns (address) {
        require(_isAssetPairEnabled(_assetPairId), "CPEM: INVALID_ASSET_PAIR");
        return address(assetPairEscrow[_assetPairId]);
    }

    function getAssetTokenAddress(bytes16 _assetPairId) external override view returns (address) {
        return _getAssetTokenAddress(_assetPairId);
    }

    function getInterestTokenAddress(bytes16 _assetPairId) external override view returns (address) {
        return _getInterestTokenAddress(_assetPairId);
    }

    function getUUID(address _contractAddress, uint256 _id) external override pure returns (uint256) {
        return _getUUID(_contractAddress, _id);
    }

    function getAssetMinDeposit(address _contractAddress) external override view returns (uint256) {
        return customAssetDepositMin[_contractAddress];
    }

    function getAssetMaxDeposit(address _contractAddress) external override view returns (uint256) {
        return customAssetDepositMax[_contractAddress];
    }

    /**
     * @notice Sets an Operator as Approved to Discharge a specific Token
     *    This allows an operator to release the interest-portion only
     * @param _contractAddress  The Address to the Contract of the Token
     * @param _tokenId          The ID of the Token
     * @param _operator         The Address of the Operator to Approve
     */
    function setDischargeApproval(address _contractAddress, uint256 _tokenId, address _operator) external override {
        INonFungible _tokenInterface = INonFungible(_contractAddress);
        address _tokenOwner = _tokenInterface.ownerOf(_tokenId);
        require(_operator != _tokenOwner, "CPEM: CANNOT_BE_SELF");
        require(msg.sender == _tokenOwner || _tokenInterface.isApprovedForAll(_tokenOwner, msg.sender), "CPEM: NOT_OPERATOR");

        uint256 _tokenUuid = _getUUID(_contractAddress, _tokenId);
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
    function isApprovedForDischarge(address _contractAddress, uint256 _tokenId, address _operator) external override view returns (bool) {
        uint256 _tokenUuid = _getUUID(_contractAddress, _tokenId);
        return tokenDischargeApprovals[_tokenUuid] == _operator;
    }

    /**
     * @notice Calculates the amount of Fees to be paid for a specific deposit amount
     *   Fees are calculated in Interest-Token as they are the type collected for Fees
     * @param _contractAddress      The Address to the Contract of the Token
     * @param _interestTokenAmount  The Amount of Interest-Token to calculate Fees on
     * @return  The amount of base fees and the amount of custom/creator fees
     */
    function getFeesForDeposit(
        address _contractAddress,
        uint256 _interestTokenAmount
    )
        external
        override 
        view
        returns (uint256, uint256)
    {
        return _getFeesForDeposit(_contractAddress, _interestTokenAmount);
    }

    /**
     * @notice Calculates the Total Fee to be paid for a specific deposit amount
     *   Fees are calculated in Interest-Token as they are the type collected for Fees
     * @param _contractAddress      The Address to the Contract of the Token
     * @param _interestTokenAmount  The Amount of Interest-Token to calculate Fees on
     * @return  The total amount of base fees plus the amount of custom/creator fees
     */
    function getFeeForDeposit(
        address _contractAddress,
        uint256 _interestTokenAmount
    )
        external
        override 
        view
        returns (uint256)
    {
        (uint256 _depositFee, uint256 _customFee) = _getFeesForDeposit(_contractAddress, _interestTokenAmount);
        return _depositFee.add(_customFee);
    }

    /**
     * @notice Gets the Amount of Asset Tokens that have been Deposited into the Particle
     *    representing the Mass of the Particle.
     * @param _contractAddress  The Address to the External Contract of the Token
     * @param _tokenId          The ID of the Token within the External Contract
     * @param _assetPairId      The Asset-Pair ID to check the Asset balance of
     * @return  The Amount of underlying Assets held within the Token
     */
    function baseParticleMass(address _contractAddress, uint256 _tokenId, bytes16 _assetPairId) external override view returns (uint256) {
        return _baseParticleMass(_contractAddress, _tokenId, _assetPairId);
    }

    /**
     * @notice Gets the amount of Interest that the Particle has generated representing 
     *    the Charge of the Particle
     * @param _contractAddress  The Address to the External Contract of the Token
     * @param _tokenId          The ID of the Token within the External Contract
     * @param _assetPairId      The Asset-Pair ID to check the Asset balance of
     * @return  The amount of interest the Token has generated (in Asset Token)
     */
    function currentParticleCharge(address _contractAddress, uint256 _tokenId, bytes16 _assetPairId) external override returns (uint256) {
        return _currentParticleCharge(_contractAddress, _tokenId, _assetPairId);
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
    function isContractOwner(address _account, address _contract) external override view returns (bool) {
        return _isContractOwner(_account, _contract);
    }

    /**
     * @notice Registers a external ERC-721 Contract in order to define Custom Rules for Tokens
     * @param _contractAddress  The Address to the External Contract of the Token
     */
    function registerContractType(address _contractAddress) external override {
        // Check Token Interface to ensure compliance
        IERC165 _tokenInterface = IERC165(_contractAddress);
        bool _is721 = _tokenInterface.supportsInterface(INTERFACE_SIGNATURE_ERC721);
        bool _is1155 = _tokenInterface.supportsInterface(INTERFACE_SIGNATURE_ERC1155);
        require(_is721 || _is1155, "CPEM: INVALID_INTERFACE");

        // Check Contract Owner to prevent random people from setting Limits
        require(_isContractOwner(msg.sender, _contractAddress), "CPEM: NOT_OWNER");

        // Contract Registered!
        customRegisteredContract[_contractAddress] = true;

        emit RegisterParticleContract(_contractAddress);
    }

    /**
     * @notice Registers the "Release-Burn" Custom Rule on an external ERC-721 Token Contract
     *   When enabled, tokens that are "Charged" will require the Token to be Burned before
     *   the underlying asset is Released.
     * @param _contractAddress       The Address to the External Contract of the Token
     * @param _releaseRequiresBurn   True if the External Contract requires tokens to be Burned before Release
     */
    function registerContractSettingReleaseBurn(address _contractAddress, bool _releaseRequiresBurn) external override {
        require(customRegisteredContract[_contractAddress], "CPEM: UNREGISTERED");
        require(_isContractOwner(msg.sender, _contractAddress), "CPEM: NOT_OWNER");
        require(customAssetPairId[_contractAddress].length > 0, "CPEM: REQUIRES_SINGLE_ASSET_PAIR");

        customReleaseRequiresBurn[_contractAddress] = _releaseRequiresBurn;
    }

    /**
     * @notice Registers the "Asset-Pair" Custom Rule on an external ERC-721 Token Contract
     *   The Asset-Pair Rule defines which Asset-Token & Interest-bearing Token Pair can be used to
     *   "Charge" the Token.  If not set, any enabled Asset-Pair can be used.
     * @param _contractAddress  The Address to the External Contract of the Token
     * @param _assetPairId      The Asset-Pair required for Energizing a Token; otherwise Any Asset-Pair is allowed
     */
    function registerContractSettingAssetPair(address _contractAddress, bytes16 _assetPairId) external override {
        require(customRegisteredContract[_contractAddress], "CPEM: UNREGISTERED");
        require(_isContractOwner(msg.sender, _contractAddress), "CPEM: NOT_OWNER");

        if (_assetPairId.length > 0) {
            require(_isAssetPairEnabled(_assetPairId), "CPEM: INVALID_ASSET_PAIR");
        } else {
            require(customReleaseRequiresBurn[_contractAddress] != true, "CPEM: CANNOT_REQUIRE_RELEASE_BURN");
        }

        customAssetPairId[_contractAddress] = _assetPairId;
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
    function registerContractSettingDepositFee(address _contractAddress, uint256 _depositFee) external override {
        require(customRegisteredContract[_contractAddress], "CPEM: UNREGISTERED");
        require(_isContractOwner(msg.sender, _contractAddress), "CPEM: NOT_OWNER");
        require(_depositFee <= MAX_CUSTOM_DEPOSIT_FEE, "CPEM: AMOUNT_INVALID");

        customAssetDepositFee[_contractAddress] = _depositFee;
    }

    /**
     * @notice Registers the "Minimum Deposit Amount" Custom Rule on an external ERC-721 Token Contract
     *    When set, every Token of the Custom ERC-721 Contract must be "Energized" with at least this 
     *    amount of Asset Token.
     * @param _contractAddress  The Address to the External Contract of the Token
     * @param _minDeposit       The Minimum Deposit required for a Token
     */
    function registerContractSettingMinDeposit(address _contractAddress, uint256 _minDeposit) external override {
        require(customRegisteredContract[_contractAddress], "CPEM: UNREGISTERED");
        require(_isContractOwner(msg.sender, _contractAddress), "CPEM: NOT_OWNER");
        require(_minDeposit == 0 || _minDeposit > MIN_DEPOSIT_FEE, "CPEM: AMOUNT_INVALID");

        customAssetDepositMin[_contractAddress] = _minDeposit;
    }

    /**
     * @notice Registers the "Maximum Deposit Amount" Custom Rule on an external ERC-721 Token Contract
     *    When set, every Token of the Custom ERC-721 Contract must be "Energized" with at most this 
     *    amount of Asset Token.
     * @param _contractAddress  The Address to the External Contract of the Token
     * @param _maxDeposit       The Maximum Deposit allowed for a Token
     */
    function registerContractSettingMaxDeposit(address _contractAddress, uint256 _maxDeposit) external override {
        require(customRegisteredContract[_contractAddress], "CPEM: UNREGISTERED");
        require(_isContractOwner(msg.sender, _contractAddress), "CPEM: NOT_OWNER");

        customAssetDepositMax[_contractAddress] = _maxDeposit;
    }


    /***********************************|
    |           Collect Fees            |
    |__________________________________*/

    /**
     * @notice Allows External Contract Owners to withdraw any Custom Fees earned
     * @param _contractAddress  The Address to the External Contract to withdraw Collected Fees for
     * @param _receiver         The Address of the Receiver of the Collected Fees
     * @param _assetPairId      The Asset-Pair ID to Withdraw Fees for
     */
    function withdrawContractFees(address _contractAddress, address _receiver, bytes16 _assetPairId) external override nonReentrant {
        require(customRegisteredContract[_contractAddress], "CPEM: UNREGISTERED");

        // Validate Contract Owner
        address _contractOwner = IOwnable(_contractAddress).owner();
        require(_contractOwner == msg.sender, "CPEM: NOT_OWNER");

        require(_isAssetPairEnabled(_assetPairId), "CPEM: INVALID_ASSET_PAIR");
        uint256 _interestAmount = assetPairEscrow[_assetPairId].withdrawFees(_contractAddress, _receiver);
        emit FeesWithdrawn(_contractAddress, _receiver, _assetPairId, _interestAmount);
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
        override 
        nonReentrant
        returns (uint256)
    {
//        require(_isNonFungibleToken(_contractAddress, _tokenId), "CPEM: INVALID_TYPE");
        require(_isAssetPairEnabled(_assetPairId), "CPEM: INVALID_ASSET_PAIR");
        require(customRegisteredContract[_contractAddress], "CPEM: UNREGISTERED");

        // Get Escrow for Asset
        IEscrow _assetPairEscrow = assetPairEscrow[_assetPairId];

        // Get Token UUID & Balance
        uint256 _typeId = _tokenId;
        if (_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) {
            _typeId = _tokenId & TYPE_MASK;
        }
        uint256 _tokenUuid = _getUUID(_contractAddress, _tokenId);
        uint256 _existingBalance = _assetPairEscrow.baseParticleMass(_tokenUuid);
        uint256 _newBalance = _assetAmount.add(_existingBalance);

        // Validate Custom Contract Settings
        // Valid Asset-Pair?
        if (customAssetPairId[_contractAddress].length > 0) {
            require(_assetPairId == customAssetPairId[_contractAddress], "CPEM: INVALID_ASSET_PAIR");
        }

        // Valid Amount?
        if (customAssetDepositMin[_contractAddress] > 0) {
            require(_newBalance >= customAssetDepositMin[_contractAddress], "CPEM: INSUFF_DEPOSIT");
        }
        if (customAssetDepositMax[_contractAddress] > 0) {
            require(_newBalance <= customAssetDepositMax[_contractAddress], "CPEM: INSUFF_DEPOSIT");
        }

        // Transfer Asset Token from Caller to Contract
        _collectAssetToken(msg.sender, _assetPairId, _assetAmount);

        // Collect Asset Token (reverts on fail)
        uint256 _interestAmount = _assetPairEscrow.energizeParticle(_contractAddress, _tokenUuid, _assetAmount);

        emit EnergizedParticle(_contractAddress, _tokenId, _assetPairId, _newBalance);

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
        override 
        nonReentrant
        returns (uint256, uint256)
    {
        uint256 _tokenUuid = _getUUID(_contractAddress, _tokenId);
        return assetPairEscrow[_assetPairId].dischargeParticle(_receiver, _tokenUuid);
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
    function dischargeParticleAmount(
        address _receiver,
        address _contractAddress,
        uint256 _tokenId,
        bytes16 _assetPairId,
        uint256 _assetAmount
    )
        external
        override 
        nonReentrant
        returns (uint256, uint256)
    {
        uint256 _tokenUuid = _getUUID(_contractAddress, _tokenId);
        return assetPairEscrow[_assetPairId].dischargeParticleAmount(_receiver, _tokenUuid, _assetAmount);
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
        override 
        nonReentrant
        returns (uint256)
    {
        require(_isAssetPairEnabled(_assetPairId), "CPEM: INVALID_ASSET_PAIR");
        require(_baseParticleMass(_contractAddress, _tokenId, _assetPairId) > 0, "CPEM: INSUFF_MASS");
        INonFungible _tokenInterface = INonFungible(_contractAddress);

        // Validate Token Owner/Operator
        address _tokenOwner = _tokenInterface.ownerOf(_tokenId);
        require((_tokenOwner == msg.sender) || _tokenInterface.isApprovedForAll(_tokenOwner, msg.sender), "CPEM: NOT_OPERATOR");

        // Validate Token Burn before Release
        bool requiresBurn;
        if (customRegisteredContract[_contractAddress]) {
            // Does Release Require Token Burn first?
            if (customReleaseRequiresBurn[_contractAddress]) {
                requiresBurn = true;
            }
        }

        uint256 _tokenUuid = _getUUID(_contractAddress, _tokenId);
        if (requiresBurn) {
            assetToBeReleasedBy[_tokenUuid] = msg.sender;
            return 0; // Need to call "finalizeRelease" next, in order to prove token-burn
        }

        // Release Particle to Receiver
        return assetPairEscrow[_assetPairId].releaseParticle(_receiver, _tokenUuid);
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
        override 
        returns (uint256)
    {
        INonFungible _tokenInterface = INonFungible(_contractAddress);
        uint256 _tokenUuid = _getUUID(_contractAddress, _tokenId);
        address releaser = assetToBeReleasedBy[_tokenUuid];

        // Validate Release Operator
        require(releaser == msg.sender, "CPEM: NOT_RELEASE_OPERATOR");

        // Validate Token Burn
        address _tokenOwner = _tokenInterface.ownerOf(_tokenId);
        require(_tokenOwner == address(0x0), "CPEM: INVALID_BURN");

        // Release Particle to Receiver
        assetToBeReleasedBy[_tokenUuid] = address(0x0);
        return assetPairEscrow[_assetPairId].releaseParticle(_receiver, _tokenUuid);
    }


    /***********************************|
    |          Only Admin/DAO           |
    |__________________________________*/

    /**
     * @dev Setup the Base Deposit Fee for the Escrow
     */
    function setDepositFee(uint256 _depositFee) external onlyDao {
        depositFee = _depositFee;
    }

    /**
     * @dev Register Contracts for Asset/Interest Pairs
     */
    function registerAssetPair(string calldata _assetPair, address _escrow) external onlyMaintainer {
        // Validate Escrow
        bytes16 _assetPairId = _toBytes16(_assetPair);
        IEscrow _newEscrow = IEscrow(_escrow);
        require(_newEscrow.isPaused() != true, "CPEM: INVALID_ESCROW");

        // Register Pair
        assetPairs.push(_assetPairId);
        assetPairEscrow[_assetPairId] = _newEscrow;
    }

    /**
     * @dev Disable a specific Asset-Pair
     */
    function disableAssetPair(bytes16 _assetPairId) external onlyDao {
        require(_isAssetPairEnabled(_assetPairId), "CPEM: INVALID_ASSET_PAIR");

        assetPairEscrow[_assetPairId] = IEscrow(address(0x0));
    }

    /**
     * @dev Allows Escrow Contract Owner/DAO to withdraw any fees earned
     */
    function withdrawFees(address _receiver, string calldata _assetPair) external onlyDao {
        address _self = address(this);
        bytes16 _assetPairId = _toBytes16(_assetPair);
        require(_isAssetPairEnabled(_assetPairId), "CPEM: INVALID_ASSET_PAIR");
        uint256 _interestAmount = assetPairEscrow[_assetPairId].withdrawFees(_self, _receiver);
        emit FeesWithdrawn(_self, _receiver, _assetPairId, _interestAmount);
    }

    function enableDao(address _dao) external onlyDao {
        require(_dao != msg.sender, "CPEM: INVALID_NEW_DAO");

        grantRole(ROLE_DAO_GOV, _dao);
        // DAO must assign a Maintainer

        if (hasRole(ROLE_DAO_GOV, msg.sender)) {
            renounceRole(ROLE_DAO_GOV, msg.sender);
        }
        if (hasRole(ROLE_MAINTAINER, msg.sender)) {
            renounceRole(ROLE_MAINTAINER, msg.sender);
        }
        if (hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            renounceRole(DEFAULT_ADMIN_ROLE, msg.sender);
        }
    }

    /***********************************|
    |         Private Functions         |
    |__________________________________*/

    function _isAssetPairEnabled(bytes16 _assetPairId) internal view returns (bool) {
        return (address(assetPairEscrow[_assetPairId]) != address(0x0));
    }
    function _getAssetTokenAddress(bytes16 _assetPairId) internal view returns (address) {
        require(_isAssetPairEnabled(_assetPairId), "CPEM: INVALID_ASSET_PAIR");
        return assetPairEscrow[_assetPairId].getAssetTokenAddress();
    }

    function _getInterestTokenAddress(bytes16 _assetPairId) internal view returns (address) {
        require(_isAssetPairEnabled(_assetPairId), "CPEM: INVALID_ASSET_PAIR");
        return assetPairEscrow[_assetPairId].getInterestTokenAddress();
    }

    function _getUUID(address _contractAddress, uint256 _id) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_contractAddress, _id)));
    }

    /**
     * @notice Checks if an Account is the Owner of a Contract
     *    When Custom Contracts are registered, only the "owner" or operator of the Contract
     *    is allowed to register them and define custom rules for how their tokens are "Charged".
     *    Otherwise, any token can be "Charged" according to the default rules of Charged Particles.
     * @param _account   The Account to check if it is the Owner of the specified Contract
     * @param _contract  The Address to the External Contract to check
     * @return True if the _account is the Owner of the _contract
     */
    function _isContractOwner(address _account, address _contract) internal view returns (bool) {
        address _contractOwner = IOwnable(_contract).owner();
        return _contractOwner != address(0x0) && _contractOwner == _account;
    }

    /**
     * @dev Calculates the amount of Fees to be paid for a specific deposit amount
     *   Fees are calculated in Interest-Token as they are the type collected for Fees
     * @param _contractAddress      The Address to the Contract of the Token
     * @param _interestTokenAmount  The Amount of Interest-Token to calculate Fees on
     * @return  The amount of base fees and the amount of custom/creator fees
     */
    function _getFeesForDeposit(
        address _contractAddress,
        uint256 _interestTokenAmount
    )
        internal
        view
        returns (uint256, uint256)
    {
        uint256 _depositFee;
        uint256 _customFee;

        if (depositFee > 0) {
            _depositFee = _interestTokenAmount.mul(depositFee).div(DEPOSIT_FEE_MODIFIER);
        }

        uint256 _customFeeSetting = customAssetDepositFee[_contractAddress];
        if (_customFeeSetting > 0) {
            _customFee = _interestTokenAmount.mul(_customFeeSetting).div(DEPOSIT_FEE_MODIFIER);
        }

        return (_depositFee, _customFee);
    }

    /**
     * @dev Collects the Required Asset Token from the users wallet
     * @param _from         The owner address to collect the Assets from
     * @param _assetPairId  The ID of the Asset-Pair that the Particle will use for the Underlying Assets
     * @param _assetAmount  The Amount of Asset Tokens to Collect
     */
    function _collectAssetToken(address _from, bytes16 _assetPairId, uint256 _assetAmount) internal {
        address _assetTokenAddress = _getAssetTokenAddress(_assetPairId);
        IERC20 _assetToken = IERC20(_assetTokenAddress);

        uint256 _userAssetBalance = _assetToken.balanceOf(_from);
        require(_assetAmount <= _userAssetBalance, "CPEM: INSUFF_ASSETS");
        // Be sure to Approve this Contract to transfer your Asset Token
        require(_assetToken.transferFrom(_from, address(this), _assetAmount), "CPEM: TRANSFER_FAILED");
    }

    /**
     * @dev Gets the Amount of Asset Tokens that have been Deposited into the Particle
     *    representing the Mass of the Particle.
     * @param _contractAddress  The Address to the External Contract of the Token
     * @param _tokenId          The ID of the Token within the External Contract
     * @param _assetPairId      The Asset-Pair ID to check the Asset balance of
     * @return  The Amount of underlying Assets held within the Token
     */
    function _baseParticleMass(address _contractAddress, uint256 _tokenId, bytes16 _assetPairId) internal view returns (uint256) {
        require(_isAssetPairEnabled(_assetPairId), "CPEM: INVALID_ASSET_PAIR");

        uint256 _tokenUuid = _getUUID(_contractAddress, _tokenId);
        return assetPairEscrow[_assetPairId].baseParticleMass(_tokenUuid);
    }

    /**
     * @dev Gets the amount of Interest that the Particle has generated representing 
     *    the Charge of the Particle
     * @param _contractAddress  The Address to the External Contract of the Token
     * @param _tokenId          The ID of the Token within the External Contract
     * @param _assetPairId      The Asset-Pair ID to check the Asset balance of
     * @return  The amount of interest the Token has generated (in Asset Token)
     */
    function _currentParticleCharge(address _contractAddress, uint256 _tokenId, bytes16 _assetPairId) internal returns (uint256) {
        require(_isAssetPairEnabled(_assetPairId), "CPEM: INVALID_ASSET_PAIR");

        uint256 _tokenUuid = _getUUID(_contractAddress, _tokenId);
        return assetPairEscrow[_assetPairId].currentParticleCharge(_tokenUuid);
    }

    /**
     * @dev Converts a string value into a bytes16 value
     */
    function _toBytes16(string memory _source) private pure returns (bytes16 _result) {
        bytes memory _tmp = bytes(_source);
        if (_tmp.length == 0) {
            return 0x0;
        }

        // solhint-disable-next-line
        assembly {
            _result := mload(add(_source, 16))
        }
    }
}

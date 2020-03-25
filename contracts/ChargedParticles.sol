// ChargedParticles.sol -- Interest-bearing NFTs
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
//  400:        ChargedParticles
//      401         Invalid Method
//      402         Unregistered Type
//      403         Particle has no Charge
//      404         Insufficient ETH Balance
//      405         Insufficient DAI Balance
//      406         Invalid value for "requiredDai" parameter
//      407         No access to Mint (Private Type)
//      408         Transfer Failed
//      409         Particle has insufficient charge
//      410         Particle must be non-fungible to hold a charge
//      411         Unregistered Asset Pairing
//      412         Invalid Pairing Token Address
//      413         Creator Mint Fee is too high
//      414         Asset-Pair ID does not exist
//      415         Asset-Pair not enabled in Escrow
//      416         ION Token already created
//      417         Contract paused
//      418         Insufficient Asset Token funds
//      419         Failed to transfer Asset Token

pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "./lib/BridgedERC1155.sol";
import "./assets/INucleus.sol";
import "./IChargedParticlesEscrow.sol";


/**
 * @notice Charged Particles Contract - Interest-Bearing NFTs
 */
contract ChargedParticles is Initializable, Ownable, ReentrancyGuard, BridgedERC1155 {
    using SafeMath for uint256;
    using Address for address payable;

    /***********************************|
    |        Variables and Events       |
    |__________________________________*/

    uint256 constant internal DEPOSIT_FEE_MODIFIER = 1e4;   // 10000  (100%)
    uint256 constant internal MAX_CUSTOM_DEPOSIT_FEE = 2e3; // 2000   (20%)
    uint32 constant internal ION_SPECIAL_BIT = 1073741824;  // 31st BIT

    IChargedParticlesEscrow escrow;

    // Particles come in many "Types" created by Public Users.
    //   Each "Type" of Particle has a "Creator", who can set certain parameters
    //   for the Particle upon Creation.
    //   Fungible Tokens (ERC20) are called "Plasma" and all tokens are the same in value.
    //     - These tokens CAN NOT hold a charge, and do not require an underlying asset when minting.
    //   Non-Fungible Tokens (ERC721) are called "Particles" and all tokens are unique in value.
    //     - These particles CAN hold a charge, and require a deposit of the underlying asset when minting.
    //   Particle Creators can also set restrictions on who can "mint" their particles, the max supply and
    //     how much of the underlying asset is required to mint a particle (1 DAI maybe?).
    //   These values are all optional, and can be left at 0 (zero) to specify no-limits.
    // Non-Fungible Tokens can be either a Series or a Collection.
    //   A series is a Single, Unique Item with Multiple Copies. NFTs that minted of this type are numbered
    //     in series, and use the same metadata as the Original Item.
    //   A collection is a group of Unique Items with only one copy of each.  NFTs that are minted of this type
    //     are Unique and require their own metadata for each.

    //        TypeID => Access Type (BITS: 1=Public, 2=Private, 4=Series, 8=Collection)
    mapping (uint256 => uint8) internal registeredTypes;

    //        TypeID => Type Creator
    mapping (uint256 => address) internal typeCreator;

    //        TypeID => Max Supply
    mapping (uint256 => uint256) internal typeSupply;

    //        TypeID => Eth Price for Minting set by Type Creator
    mapping (uint256 => uint256) internal mintFee;

    //        TypeID => Specific Asset-Pair to be used for this Type
    mapping (uint256 => bytes16) internal typeAssetPairId;

    //        TypeID => Special bit-markings for this Type
    mapping (uint256 => uint32) internal typeSpecialBits;

    //        TypeID => Token-Bridge for ERC20/ERC721
    mapping (uint256 => address) internal typeTokenBridge;

    // Allowed Asset-Pairs
    mapping (bytes16 => bool) internal assetPairEnabled;

    // Owner/Creator => ETH Fees earned by Creator
    mapping (address => uint256) internal collectedFees;

    // To Create "Types" (Fungible or Non-Fungible) there is a Fee.
    //  The Fee can be paid in ETH or in IONs.
    //  IONs are a custom ERC20 token minted within this contract.
    //  ETH paid upon minting is stored in contract, withdrawn by contract owner.
    //  IONs paid upon minting are burned.
    //  These values are completely optional and can be set to 0 to specify No Fee.
    uint256 internal createFeeEth;
    uint256 internal createFeeIon;

    // Internal ERC20 Token used for Creating Types;
    // needs to be created as a private ERC20 type within this contract
    uint256 internal ionTokenId;

    // Contract Version
    bytes16 public version;

    // Contract State
    bool isPaused;

    //
    // Modifiers
    //

    modifier whenNotPaused() {
        require(!isPaused, "E417");
        _;
    }

    //
    // Events
    //

    event ParticleTypeUpdated(uint256 indexed _particleTypeId, string indexed _symbol, bool indexed _isPrivate, bool _isSeries, string _assetPairId, uint256 _energizeFee, string _uri); // find latest in logs for full record
    event PlasmaTypeUpdated(uint256 indexed _plasmaTypeId, string indexed _symbol, bool indexed _isPrivate, uint256 _initialMint, string _uri);
    event ParticleMinted(address indexed _sender, address indexed _receiver, uint256 indexed _tokenId, string _uri);
    event ParticleBurned(address indexed _from, uint256 indexed _tokenId);
    event PlasmaMinted(address indexed _sender, address indexed _receiver, uint256 indexed _typeId, uint256 _amount);
    event PlasmaBurned(address indexed _from, uint256 indexed _typeId, uint256 _amount);
    event CreatorFeesWithdrawn(address indexed _sender, address indexed _receiver, uint256 _amount);
    event ContractFeesWithdrawn(address indexed _sender, address indexed _receiver, uint256 _amount);

    /***********************************|
    |          Initialization           |
    |__________________________________*/

    function initialize(address sender) public initializer {
        Ownable.initialize(sender);
        ReentrancyGuard.initialize();
        BridgedERC1155.initialize();
        version = "v0.2.4";
    }

    /***********************************|
    |            Public Read            |
    |__________________________________*/

    /**
     * @notice Gets the Creator of a Token Type
     * @param _typeId     The Type ID of the Token
     * @return  The Creator Address
     */
    function getTypeCreator(uint256 _typeId) public view returns (address) {
        return typeCreator[_typeId];
    }

    /**
     * @notice Gets the Compatibility Bridge for the Token
     * @param _typeId     The Token ID or the Type ID of the Token
     * @return  The Token-Bridge Address
     */
    function getTypeTokenBridge(uint256 _typeId) public view returns (address) {
        if (_typeId & TYPE_NF_BIT == TYPE_NF_BIT) {
            _typeId = _typeId & TYPE_MASK;
        }
        return typeTokenBridge[_typeId];
    }

    /**
     * @notice Checks if a user is allowed to mint a Token by Type ID
     * @param _typeId     The Type ID of the Token
     * @param _amount   The amount of tokens to mint
     * @return  True if the user can mint the token type
     */
    function canMint(uint256 _typeId, uint256 _amount) public view returns (bool) {
        // Public
        if (registeredTypes[_typeId] & 1 == 1) {
            // Has Max
            if (typeSupply[_typeId] > 0) {
                return maxIndex[_typeId].add(_amount) <= typeSupply[_typeId];
            }
            // No Max
            return true;
        }
        // Private
        if (typeCreator[_typeId] != msg.sender) {
            return false;
        }
        // Has Max
        if (typeSupply[_typeId] > 0) {
            return maxIndex[_typeId].add(_amount) <= typeSupply[_typeId];
        }
        // No Max
        return true;
    }

    /**
     * @notice Gets the ETH price to create a Token Type
     * @param _isNF     True if the Type of Token to Create is a Non-Fungible Token
     * @return  The ETH price to create a type
     */
    function getCreationPrice(bool _isNF) public view returns (uint256 eth, uint256 ion) {
        eth = _isNF ? (createFeeEth.mul(2)) : createFeeEth;
        ion = _isNF ? (createFeeIon.mul(2)) : createFeeIon;
    }

    /**
     * @notice Gets the Number of this Particle in the Series/Collection
     */
    function getSeriesNumber(uint256 _tokenId) public pure returns (uint256) {
        return _tokenId & NF_INDEX_MASK;
    }

    /**
     * @notice Gets the ETH price to mint a Token of a specific Type
     * @param _typeId     The Token ID or the Type ID of the Token
     * @return  The ETH price to mint the Token
     */
    function getMintingFee(uint256 _typeId) public view returns (uint256) {
        if (_typeId & TYPE_NF_BIT == TYPE_NF_BIT) {
            _typeId = _typeId & TYPE_MASK;
        }
        return mintFee[_typeId];
    }

    /**
     * @notice Gets the Max-Supply of the Particle Type (0 for infinite)
     * @param _typeId   The Token ID or the Type ID of the Token
     */
    function getMaxSupply(uint256 _typeId) public view returns (uint256) {
        if (_typeId & TYPE_NF_BIT == TYPE_NF_BIT) {
            _typeId = _typeId & TYPE_MASK;
        }
        return typeSupply[_typeId];
    }

    /**
     * @notice Gets the Number of Minted Particles
     * @param _typeId   The Token ID or the Type ID of the Token
     */
    function getTotalMinted(uint256 _typeId) public view returns (uint256) {
        if (_typeId & TYPE_NF_BIT == TYPE_NF_BIT) {
            _typeId = _typeId & TYPE_MASK;
        }
        return maxIndex[_typeId];
    }

    /***********************************|
    |         Particle Physics          |
    |__________________________________*/

    /**
     * @notice Gets the Amount of Base DAI held in the Token (amount token was minted with)
     */
    function baseParticleMass(uint256 _tokenId) public view returns (uint256) {
        uint256 _typeId = _tokenId & TYPE_MASK;
        bytes16 _assetPairId = typeAssetPairId[_typeId];
        return escrow.baseParticleMass(address(this), _tokenId, _assetPairId);
    }

    /**
     * @notice Gets the amount of Charge the Particle has generated (it's accumulated interest)
     */
    function currentParticleCharge(uint256 _tokenId) public returns (uint256) {
        uint256 _typeId = _tokenId & TYPE_MASK;
        require(registeredTypes[_typeId] > 0, "E402");
        require(_tokenId & TYPE_NF_BIT == TYPE_NF_BIT, "E402");

        bytes16 _assetPairId = typeAssetPairId[_typeId];
        return escrow.currentParticleCharge(address(this), _tokenId, _assetPairId);
    }

    /***********************************|
    |        Public Create Types        |
    |__________________________________*/

    /**
     * @notice Creates a new Particle Type (NFT/ERC721) which can later be minted/burned
     *         NOTE: Requires payment in ETH or IONs
     @ @dev see _createParticle()
     */
    function createParticle(
        string memory _name,
        string memory _uri,
        string memory _symbol,
        uint8 _accessType,
        string memory _assetPairId,
        uint256 _maxSupply,
        uint256 _mintFee,
        uint256 _energizeFee,
        bool _payWithIons
    )
        public
        payable
        whenNotPaused
        returns (uint256 _particleTypeId)
    {
        address contractOwner = owner();
        (uint256 ethPrice, uint256 ionPrice) = getCreationPrice(true);

        if (_payWithIons) {
            _collectIons(msg.sender, ionPrice);
            ethPrice = 0;
        } else {
            require(msg.value >= ethPrice, "E404");
        }

        // Create Particle Type
        _particleTypeId = _createParticle(
            _name,          // Token Name
            _uri,           // Token Metadata URI
            _symbol,        // Token Symbol
            _accessType,    // Token Access Type
            _assetPairId,   // Asset Pair for Type
            _maxSupply,     // Max Supply
            _mintFee,       // Price-per-Token in ETH
            _energizeFee    // Energize Fee for Creator
        );

        // Mark ION-Generated Particles
        if (_payWithIons) {
            typeSpecialBits[_particleTypeId] = typeSpecialBits[_particleTypeId] | ION_SPECIAL_BIT;
        }

        // Collect Fees
        else {
            collectedFees[contractOwner] = ethPrice.add(collectedFees[contractOwner]);
        }

        // Refund over-payment
        uint256 overage = msg.value.sub(ethPrice);
        if (overage > 0) {
            msg.sender.sendValue(overage);
        }
    }

    /**`
     * @notice Creates a new Plasma Type (FT/ERC20) which can later be minted/burned
     *         NOTE: Requires payment in ETH or IONs
     @ @dev see _createPlasma()
     */
    function createPlasma(
        string memory _name,
        string memory _uri,
        string memory _symbol,
        bool _isPrivate,
        uint256 _maxSupply,
        uint256 _mintFee,
        uint256 _initialMint,
        bool _payWithIons
    )
        public
        payable
        whenNotPaused
        returns (uint256 _plasmaTypeId)
    {
        address contractOwner = owner();
        (uint256 ethPrice, uint256 ionPrice) = getCreationPrice(false);

        if (_payWithIons) {
            _collectIons(msg.sender, ionPrice);
            ethPrice = 0;
        } else {
            require(msg.value >= ethPrice, "E404");
        }

        // Create Plasma Type
        _plasmaTypeId = _createPlasma(
            _name,          // Token Name
            _uri,           // Token Metadata URI
            _symbol,        // Token Symbol
            _isPrivate,     // is Private?
            _maxSupply,     // Max Supply
            _mintFee,       // Price per Token in ETH
            _initialMint    // Initial Amount to Mint
        );

        // Mark ION-Generated Particles
        if (_payWithIons) {
            typeSpecialBits[_plasmaTypeId] = typeSpecialBits[_plasmaTypeId] | ION_SPECIAL_BIT;
        }

        // Collect Fees
        else {
            collectedFees[contractOwner] = ethPrice.add(collectedFees[contractOwner]);
        }

        // Refund over-payment
        uint256 overage = msg.value.sub(ethPrice);
        if (overage > 0) {
            msg.sender.sendValue(overage);
        }
    }

    /***********************************|
    |            Public Mint            |
    |__________________________________*/

    /**
     * @notice Mints a new Particle of the specified Type
     *          Note: Requires Asset-Token to mint
     * @param _to           The owner address to assign the new token to
     * @param _typeId         The Type ID of the new token to mint
     * @param _assetAmount  The amount of Asset-Tokens to deposit
     * @param _uri          The Unique URI to the Token Metadata
     * @param _data         Custom data used for transferring tokens into contracts
     * @return  The ID of the newly minted token
     *
     * NOTE: Must approve THIS contract to TRANSFER your Asset-Token on your behalf
     */
    function mintParticle(
        address _to,
        uint256 _typeId,
        uint256 _assetAmount,
        string memory _uri,
        bytes memory _data
    )
        public
        whenNotPaused
        payable
        returns (uint256)
    {
        require((_typeId & TYPE_NF_BIT == TYPE_NF_BIT) && (_typeId & NF_INDEX_MASK == 0), "E304");
        require(canMint(_typeId, 1), "E407");

        address creator = typeCreator[_typeId];
        uint256 ethPerToken;

        // Check Token Price
        if (msg.sender != creator) {
            ethPerToken = mintFee[_typeId];
            require(msg.value >= ethPerToken, "E404");
        }

        // Series-Particles use the Metadata of their Type
        if (registeredTypes[_typeId] & 4 == 4) {
            _uri = tokenUri[_typeId];
        }

        // Mint Token
        uint256 _tokenId = _mint(_to, _typeId, 1, _uri, _data);
//        typeCreator[_tokenId] = msg.sender;    // This is the TOKEN creator, not TYPE

        // Energize NFT Particles
        energizeParticle(_tokenId, _assetAmount);

        // Log Event
        emit ParticleMinted(msg.sender, _to, _tokenId, _uri);

        // Track Collected Fees
        if (msg.sender != creator) {
            collectedFees[creator] = ethPerToken.add(collectedFees[creator]);
        }

        // Refund overpayment
        uint256 overage = msg.value.sub(ethPerToken);
        if (overage > 0) {
            msg.sender.sendValue(overage);
        }
        return _tokenId;
    }

    /**
     * @notice Mints new Plasma of the specified Type
     * @param _to      The owner address to assign the new tokens to
     * @param _typeId    The Type ID of the tokens to mint
     * @param _amount  The amount of tokens to mint
     * @param _data    Custom data used for transferring tokens into contracts
     */
    function mintPlasma(
        address _to,
        uint256 _typeId,
        uint256 _amount,
        bytes memory _data
    )
        public
        whenNotPaused
        payable
    {
        require(_typeId & TYPE_NF_BIT == 0, "E304");
        require(canMint(_typeId, _amount), "E407");

        address creator = (_typeId == ionTokenId) ? owner() : typeCreator[_typeId];
        uint256 totalEth;
        uint256 ethPerToken;

        // Check Token Price
        if (msg.sender != creator) {
            ethPerToken = mintFee[_typeId];
            totalEth = _amount.mul(ethPerToken);
            require(msg.value >= totalEth, "E404");
        }

        // Mint Token
        _mint(_to, _typeId, _amount, "", _data);
        emit PlasmaMinted(msg.sender, _to, _typeId, _amount);

        if (msg.sender != creator) {
            // Track Collected Fees
            collectedFees[creator] = totalEth.add(collectedFees[creator]);
        }

        // Refund overpayment
        uint256 overage = msg.value.sub(totalEth);
        if (overage > 0) {
            msg.sender.sendValue(overage);
        }
    }

    /***********************************|
    |            Public Burn            |
    |__________________________________*/

    /**
     * @notice Destroys a Particle and releases the underlying Asset + Interest (Mass + Charge)
     * @param _tokenId  The ID of the token to burn
     */
    function burnParticle(uint256 _tokenId) public {
        address _self = address(this);
        address _tokenOwner;
        bytes16 _assetPairId;

        // Verify Token
        require((_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) && (_tokenId & NF_INDEX_MASK == 0), "E304");
        uint256 _typeId = _tokenId & TYPE_MASK;
        require(registeredTypes[_typeId] > 0, "E402");

        // Prepare Particle Release
        _tokenOwner = ownerOf(_tokenId);
        _assetPairId = typeAssetPairId[_typeId];
        escrow.releaseParticle(_tokenOwner, _self, _tokenId, _assetPairId);

        // Burn Token
        _burn(msg.sender, _tokenId, 1);

        // Release Particle (Payout Asset + Interest)
        escrow.finalizeRelease(_tokenOwner, _self, _tokenId, _assetPairId);

        emit ParticleBurned(msg.sender, _tokenId);
    }

    /**
     * @notice Destroys Plasma
     * @param _typeId   The type of token to burn
     * @param _amount   The amount of tokens to burn
     */
    function burnPlasma(uint256 _typeId, uint256 _amount) public {
        // Verify Token
        require(_typeId & TYPE_NF_BIT == 0, "E304");
        require(registeredTypes[_typeId] > 0, "E402");

        // Burn Token
        _burn(msg.sender, _typeId, _amount);

        emit PlasmaBurned(msg.sender, _typeId, _amount);
    }

    /***********************************|
    |        Energize Particle          |
    |__________________________________*/

    /**
     * @notice Allows the owner/operator of the Particle to add additional Asset Tokens
     */
    function energizeParticle(uint256 _tokenId, uint256 _assetAmount)
        public
        whenNotPaused
        returns (uint256)
    {
        uint256 _typeId = _tokenId & TYPE_MASK;
        bytes16 _assetPairId = typeAssetPairId[_typeId];
        require((_tokenId & TYPE_NF_BIT == TYPE_NF_BIT) && (_tokenId & NF_INDEX_MASK == 0), "E304");

        // Transfer Asset Token from User to Contract
        _collectAssetToken(msg.sender, _assetPairId, _assetAmount);

        // Energize Particle
        return escrow.energizeParticle(address(this), _tokenId, _assetPairId, _assetAmount);
    }

    /***********************************|
    |        Discharge Particle         |
    |__________________________________*/

    /**
     * @notice Allows the owner/operator of the Particle to collect/transfer the interest generated
     *  from the token without removing the underlying Asset that is held in the token
     */
    function dischargeParticle(address _receiver, uint256 _tokenId) public returns (uint256, uint256) {
        uint256 _typeId = _tokenId & TYPE_MASK;
        bytes16 _assetPairId = typeAssetPairId[_typeId];
        return escrow.dischargeParticle(_receiver, address(this), _tokenId, _assetPairId);
    }

    /**
     * @notice Allows the owner/operator of the Particle to collect/transfer a specific amount of
     *  the interest generated from the token without removing the underlying Asset that is held in the token
     */
    function dischargeParticle(address _receiver, uint256 _tokenId, uint256 _assetAmount) public returns (uint256, uint256) {
        uint256 _typeId = _tokenId & TYPE_MASK;
        bytes16 _assetPairId = typeAssetPairId[_typeId];
        return escrow.dischargeParticle(_receiver, address(this), _tokenId, _assetPairId, _assetAmount);
    }


    /***********************************|
    |           Type Creator            |
    |__________________________________*/

    /**
     * @dev Allows contract owner to withdraw any fees earned
     */
    function withdrawCreatorFees(address payable _receiver, uint256 _typeId) public {
        address creator = typeCreator[_typeId];
        require(msg.sender == creator, "E305");

        // Withdraw Particle Deposit Fees from Escrow
        escrow.withdrawCreatorFees(creator, _typeId);

        // Withdraw Plasma Minting Fees (ETH)
        uint256 _amount = collectedFees[creator];
        if (_amount > 0) {
            _receiver.sendValue(_amount);
        }
        emit CreatorFeesWithdrawn(msg.sender, _receiver, _amount);
    }

    /***********************************|
    |            Only Owner             |
    |__________________________________*/

    /**
     * @dev Setup the Creation/Minting Fees
     */
    function setupFees(uint256 _createFeeEth, uint256 _createFeeIon) public onlyOwner {
        createFeeEth = _createFeeEth;
        createFeeIon = _createFeeIon;
    }

    /**
     * @dev Toggle the "Paused" state of the contract
     */
    function setPausedState(bool _paused) public onlyOwner {
        isPaused = _paused;
    }

    /**
     * @dev Register the address of the escrow contract
     */
    function registerEscrow(address _escrowAddress) public onlyOwner {
        require(_escrowAddress != address(0x0), "E412");
        escrow = IChargedParticlesEscrow(_escrowAddress);
    }

    /**
     * @dev Register valid asset pairs (needs to mirror escrow)
     */
    function registerAssetPair(string memory _assetPairId) public onlyOwner {
        bytes16 _assetPair = _toBytes16(_assetPairId);
        require(escrow.isAssetPairEnabled(_assetPair), "E415");

        // Allow Escrow to Transfer Assets from this Contract
        address _assetTokenAddress = escrow.getAssetTokenAddress(_assetPair);
        IERC20(_assetTokenAddress).approve(address(escrow), uint(-1));
        assetPairEnabled[_assetPair] = true;
    }

    /**
     * @dev Toggle an Asset Pair
     */
    function disableAssetPair(string memory _assetPairId) public onlyOwner {
        bytes16 _assetPair = _toBytes16(_assetPairId);
        assetPairEnabled[_assetPair] = false;
    }

    /**
     * @dev Setup internal ION Token
     */
    function mintIons(string memory _uri, uint256 _maxSupply, uint256 _amount, uint256 _mintFee) public onlyOwner returns (uint256) {
        require(ionTokenId == 0, "E416");

        // Create ION Token Type;
        //  ERC20, Private, Limited
        ionTokenId = _createPlasma(
            "Charged Atoms", // Token Name
            _uri,            // Token Metadata URI
            "ION",           // Token Symbol
            false,           // is Private?
            _maxSupply,      // Max Supply
            _mintFee,        // Price per Token in ETH
            _amount          // Initial amount to mint
        );

        return ionTokenId;
    }

    /**
     * @dev Allows contract owner to withdraw any ETH fees earned
     *      Interest-token Fees are collected in Escrow, withdraw from there
     */
    function withdrawFees(address payable _receiver) public onlyOwner {
        require(_receiver != address(0x0), "E412");

        address contractOwner = owner();
        uint256 _amount = collectedFees[contractOwner];
        if (_amount > 0) {
            _receiver.sendValue(_amount);
        }
        emit ContractFeesWithdrawn(msg.sender, _receiver, _amount);
    }

    /***********************************|
    |         Private Functions         |
    |__________________________________*/

    /**
     * @notice Creates a new Particle Type (NFT) which can later be minted/burned
     * @param _name             The Name of the Particle
     * @param _uri              A unique URI for the Token Type which will serve the JSON metadata
     * @param _accessType       A bit indicating the Access Type; Private/Public, Series/Collection
     * @param _assetPairId      The ID of the Asset-Pair that the Particle will use for the Underlying Assets
     * @param _maxSupply        The Max Supply of Tokens that can be minted
     *                          Provide a value of 0 for no limit
     * @param _mintFee          The "Mint" Fee that is collected for each Particle and paid to the Particle Type Creator
     * @param _energizeFee      The "Energize" Fee that is collected upon Asset Deposit for each Particle and paid to the Particle Type Creator
     *                          Collected when the Particle is Energized
     * @return The ID of the newly created Particle Type
     *         Use this ID when Minting Particles of this Type
     */
    function _createParticle(
        string memory _name,
        string memory _uri,
        string memory _symbol,
        uint8 _accessType,
        string memory _assetPairId,
        uint256 _maxSupply,
        uint256 _mintFee,
        uint256 _energizeFee
    )
        internal
        returns (uint256 _particleTypeId)
    {
        bytes16 _assetPair = _toBytes16(_assetPairId);
        require(_energizeFee <= MAX_CUSTOM_DEPOSIT_FEE, "E413");
        require(assetPairEnabled[_assetPair], "E414");

        // Create Type
        _particleTypeId = _createType(_uri, true); // ERC-1155 Non-Fungible

        // Create Token-Bridge
        typeTokenBridge[_particleTypeId] = _createErc721Bridge(_particleTypeId, _name, _symbol);

        // Type Access (Public or Private, Series or Collection)
        registeredTypes[_particleTypeId] = _accessType; // (_isPrivate ? 2 : 1) & (_isSeries ? 4 : 8);

        // Max Supply of Token; 0 = No Max
        typeSupply[_particleTypeId] = _maxSupply;

        // The Eth-per-Token Fee for Minting
        mintFee[_particleTypeId] = _mintFee;

        // Creator of Type
        typeCreator[_particleTypeId] = msg.sender;
        escrow.registerCreatorSetting_FeeCollector(_particleTypeId, msg.sender);

        // Type Asset-Pair
        typeAssetPairId[_particleTypeId] = _assetPair;
        escrow.registerCreatorSetting_AssetPair(_particleTypeId, _assetPair);

        // The Deposit Fee for Creators
        escrow.registerCreatorSetting_DepositFee(_particleTypeId, _assetPair, _energizeFee);

        emit ParticleTypeUpdated(
            _particleTypeId,
            _symbol,
            (_accessType & 2 == 2),     // isPrivate
            (_accessType & 4 == 4),     // isSeries
            _assetPairId,
            _energizeFee,
            _uri
        );
    }

    /**
     * @notice Creates a new Plasma Type (FT) which can later be minted/burned
     * @param _name             The Name of the Particle
     * @param _uri              A unique URI for the Token Type which will serve the JSON metadata
     * @param _isPrivate        True if the Type is Private and can only be minted by the creator; otherwise anyone can mint
     * @param _maxSupply        The Max Supply of Tokens that can be minted
     *                          Provide a value of 0 for no limit
     * @param _mintFee          The ETH Price of each Token when sold to public
     * @param _initialMint      The amount of tokens to initially mint
     * @return The ID of the newly created Plasma Type
     *         Use this ID when Minting Plasma of this Type
     */
    function _createPlasma(
        string memory _name,
        string memory _uri,
        string memory _symbol,
        bool _isPrivate,
        uint256 _maxSupply,
        uint256 _mintFee,
        uint256 _initialMint
    )
        internal
        returns (uint256 _plasmaTypeId)
    {
        // Create Type
        _plasmaTypeId = _createType(_uri, false); // ERC-1155 Fungible

        // Create Token-Bridge
        typeTokenBridge[_plasmaTypeId] = _createErc20Bridge(_plasmaTypeId, _name, _symbol, 18);

        // Type Access (Public or Private minting)
        registeredTypes[_plasmaTypeId] = _isPrivate ? 2 : 1;

        // Creator of Type
        typeCreator[_plasmaTypeId] = msg.sender;

        // Max Supply of Token; 0 = No Max
        typeSupply[_plasmaTypeId] = _maxSupply;

        // The Eth-per-Token Fee for Minting
        mintFee[_plasmaTypeId] = _mintFee;

        // Mint Initial Tokens
        if (_initialMint > 0) {
            _mint(msg.sender, _plasmaTypeId, _initialMint, "", "");
        }

        emit PlasmaTypeUpdated(_plasmaTypeId, _symbol, _isPrivate, _initialMint, _uri);
    }

    /**
     * @dev Collects the Required IONs from the users wallet during Type Creation and Burns them
     * @param _from  The owner address to collect the IONs from
     * @param _ions  The amount of IONs to collect from the user
     */
    function _collectIons(address _from, uint256 _ions) internal {
        // Burn IONs from User
        _burn(_from, ionTokenId, _ions);
    }

    /**
     * @dev Collects the Required Asset Token from the users wallet
     */
    function _collectAssetToken(address _from, bytes16 _assetPairId, uint256 _assetAmount) internal {
        address _assetTokenAddress = escrow.getAssetTokenAddress(_assetPairId);
        IERC20 _assetToken = IERC20(_assetTokenAddress);

        uint256 _userAssetBalance = _assetToken.balanceOf(_from);
        require(_assetAmount <= _userAssetBalance, "E418");
        require(_assetToken.transferFrom(_from, address(this), _assetAmount), "E419"); // Be sure to Approve this Contract to transfer your Asset Token
    }

    /**
     * @dev Convert a string to Bytes16
     */
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

pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import "./interfaces/ChaiInterface.sol";
import "./lib/ERC1155MetaMixedFungible.sol";
import "multi-token-standard/contracts/utils/SafeMath.sol";
import "multi-token-standard/contracts/utils/Ownable.sol";
import "multi-token-standard/contracts/interfaces/IERC20.sol";
import "multi-token-standard/contracts/tokens/ERC1155/ERC1155Metadata.sol";


contract ChargedParticles is ERC1155Metadata, ERC1155MetaMixedFungible, Ownable {
    using SafeMath for uint256;

    uint256 constant internal DAI_UNIT = 1e18;
    uint256 constant internal MIN_DAI = 1e6;
    uint16 constant internal FEE_BASE = 1e4;
    uint8 constant internal TYPE_PUBLIC = 1;
    uint8 constant internal TYPE_PRIVATE = 2;

    //       TypeID => Access Type (Public/Private)
    mapping(uint256 => uint8) internal registeredTypes;

    //       TypeID => Type Creator
    mapping(uint256 => address) internal registeredTypeCreators;

    //       TypeID => Required DAI
    mapping(uint256 => uint256) internal requiredFundingByType;   // Amount of Dai to deposit when minting

    //      TokenID => Balance
    mapping(uint256 => uint256) internal chaiBalanceByTokenId;    // Amount of Chai minted from Dai deposited

    uint256 internal creationPriceFT;
    uint256 internal creationPriceNFT;
    uint256 internal mintingFee;
    uint256 internal totalMintingFees;

    address public daiAddress;
    address public chaiAddress;

    IERC20 internal dai;
    IChai internal chai;

    //
    // Initialization
    //

    constructor() public {
        creationPriceFT = 35 szabo;     //  0.000035 ETH  (~ USD $0.005)
        creationPriceNFT = 70 szabo;    //  0.00007 ETH  (~ USD $0.01)
        mintingFee = 50;                //  0.5% of Chai from deposited Dai
    }


    //
    // Public View
    //

    function isRegisteredType(uint256 _type) public view returns (bool) {
        return registeredTypes[_type] > 0;
    }

    function isPublicType(uint256 _type) public view returns (bool) {
        return registeredTypes[_type] == TYPE_PUBLIC;
    }

    function creatorOfType(uint256 _type) public view returns (address) {
        return registeredTypeCreators[_type];
    }

    function canMint(uint256 _type) public view returns (bool) {
        if (registeredTypes[_type] == TYPE_PUBLIC) { return true; }
        return (registeredTypeCreators[_type] == msg.sender);
    }

    function getCreationPriceFT() public view returns (uint256) {
        return creationPriceFT;
    }

    function getCreationPriceNFT() public view returns (uint256) {
        return creationPriceNFT;
    }

    function getMintingFee() public view returns (uint256) {
        return mintingFee;
    }

    function getDaiContractBalance() public returns (uint256) {
        return chai.dai(address(this));
    }

    function getChaiContractBalance() public returns (uint256) {
        return chai.balanceOf(address(this));
    }

    function logURIs(uint256[] memory _tokenIds) public {
        super._logURIs(_tokenIds);
    }

    // view current amount of base-Dai held in particle
    function baseParticleMass(uint256 _tokenId) public view returns (uint256) {
        uint256 _type = _tokenId & TYPE_MASK;
        return requiredFundingByType[_type];
    }

    // view current amount of interest earned by a particle
    function currentParticleCharge(uint256 _tokenId) public returns (uint256) {
        uint256 _type = _tokenId & TYPE_MASK;
        uint256 currentCharge = chai.dai(chaiBalanceByTokenId[_tokenId]);
        uint256 originalCharge = requiredFundingByType[_type];
        if (originalCharge >= currentCharge) { return 0; }
        return currentCharge.sub(originalCharge);
    }


    //
    // Public Actionable
    //

    // collect current interest from particle
    function dischargeParticle(uint256 _tokenId) public {
        address owner = ownerOf(_tokenId);
        require((owner == msg.sender) || isApprovedForAll(owner, msg.sender), "Must be Particle Owner or Operator");

        uint256 _type = _tokenId & TYPE_MASK;
        require(isRegisteredType(_type), "Invalid Particle Type");
        require(requiredFundingByType[_type] > 0, "Invalid Particle Type");

        uint256 _currentCharge = currentParticleCharge(_tokenId);
        require(_currentCharge > 0, "Particle has no charge");

        _payoutChargedDai(msg.sender, _currentCharge);
    }


    //
    // Public Payable
    //

    function createParticle(string memory _uri, bool _isNF, bool _isPrivate, uint256 _requiredDai) public payable returns (uint256 _particleTypeId) {
        require((!_isNF && msg.value >= creationPriceFT) || (_isNF && msg.value >= creationPriceNFT), "Insufficient payment for Particle creation");
        require(!_isNF || (_isNF && _requiredDai >= MIN_DAI), "Non-Fungible Particles must have a requiredDai amount greater than 1000000 WEI");

        // Create Type
        _particleTypeId = _createType(_uri, _isNF);

        // Type Access (Public or Private minting)
        registeredTypes[_particleTypeId] = _isPrivate ? TYPE_PRIVATE : TYPE_PUBLIC;

        // Creator of Type
        registeredTypeCreators[_particleTypeId] = msg.sender;

        // Required Funding for NFTs
        requiredFundingByType[_particleTypeId] = _isNF ? _requiredDai : 0;

        // Refund over-payment
        uint256 overage = msg.value.sub(_isNF ? creationPriceNFT : creationPriceFT);
        if (overage > 0) {
            msg.sender.transfer(overage);
        }
    }


    //
    // Public Mint - Fungible (ERC20)
    //

    function mintCommon(address _to, uint256 _type, uint256 _amount, bytes memory _data) public {
        require(canMint(_type), "Must have access to specified type");
        _mintFungible(_to, _type, _amount, _data);
    }

    function mintCommonBatch(address _to, uint256[] memory _types, uint256[] memory _amounts, bytes memory _data) public {
        for (uint256 i = 0; i < _types.length; ++i) {
            require(canMint(_types[i]), "Must have access to all specified types");
        }
        _mintFungibleBatch(_to, _types, _amounts, _data);
    }

    //
    // Public Mint - Non-Fungible (ERC721)
    //

    function mintUnique(address _to, uint256 _type, bytes memory _data) public returns (uint256 _tokenId) {
        require(canMint(_type), "Must have access to specified type");

        address _self = address(this);

        // Transfer DAI from User to Contract
        uint256 _requiredDai = requiredFundingByType[_type];
        _collectRequiredDai(msg.sender, _requiredDai);

        // Mint NFT
        _tokenId = _mintNonFungible(_to, _type, _data);

        // Tokenize Interest
        uint256 _preBalance = chai.balanceOf(_self);
        chai.join(_self, _requiredDai);
        uint256 _postBalance = chai.balanceOf(_self);

        // Track Chai in each Token
        chaiBalanceByTokenId[_tokenId] = _totalChaiForToken(_postBalance.sub(_preBalance));
    }

    function mintUniqueBatch(address _to, uint256[] memory _types, bytes memory _data) public returns (uint256[] memory _tokenIds) {
        address _self = address(this);
        uint256 i;
        uint256 _totalDai;
        uint256 _requiredDai;

        for (i = 0; i < _types.length; ++i) {
            require(canMint(_types[i]), "Must have access to all specified types");
            _requiredDai = requiredFundingByType[_types[i]];
            _totalDai = _requiredDai.add(_totalDai);
        }

        // Transfer DAI from User to Contract
        _collectRequiredDai(msg.sender, _totalDai);

        // Mint NFTs
        _tokenIds = _mintNonFungibleBatch(_to, _types, _data);

        uint256 _balance = chai.balanceOf(_self);
        for (i = 0; i < _types.length; ++i) {
            _requiredDai = requiredFundingByType[_types[i]];

            // Tokenize Interest
            chai.join(_self, _requiredDai);

            // Track Chai in each Token
            chaiBalanceByTokenId[_tokenIds[i]] = _totalChaiForToken(chai.balanceOf(_self).sub(_balance));
            _balance = chai.balanceOf(_self);
        }
    }


    //
    // Public Burn - Fungible (ERC20)
    //

    function burnCommon(uint256 _type, uint256 _amount) public {
        require(isRegisteredType(_type), "Unregistered type supplied");
        _burnFungible(msg.sender, _type, _amount);
    }

    function burnCommonBatch(uint256[] memory _types, uint256[] memory _amounts) public {
        for (uint256 i = 0; i < _types.length; ++i) {
            require(isRegisteredType(_types[i]), "Unregistered type encountered");
        }
        _burnFungibleBatch(msg.sender, _types, _amounts);
    }


    //
    // Public Burn - Non-Fungible (ERC721)
    //

    function burnUnique(uint256 _tokenId) public {
        uint256 _type = _tokenId & TYPE_MASK;
        require(isRegisteredType(_type), "Unregistered token supplied");

        uint256 _tokenChai = chaiBalanceByTokenId[_tokenId];
        chaiBalanceByTokenId[_tokenId] = 0;

        // Burn NFT
        _burnNonFungible(msg.sender, _tokenId);

        // Payout Dai + Interest
        _payoutFundedDai(msg.sender, _tokenChai);
    }

    function burnUniqueBatch(uint256[] memory _tokenIds) public {
        uint256 i;
        uint256 _tokenId;
        uint256 _totalChai;
        for (i = 0; i < _tokenIds.length; ++i) {
            _tokenId = _tokenIds[i];
            require(isRegisteredType(_tokenId & TYPE_MASK), "Unregistered token encountered");
            _totalChai = chaiBalanceByTokenId[_tokenId].add(_totalChai);
            chaiBalanceByTokenId[_tokenId] = 0;
        }

        // Burn NFTs
        _burnNonFungibleBatch(msg.sender, _tokenIds);

        // Payout Dai + Interest
        _payoutFundedDai(msg.sender, _totalChai);
    }


    //
    // Only Owner
    //

    function withdrawCreationFees() public onlyOwner {
        uint256 _balance = address(this).balance;
        require(_balance > 0, "No creation fees currently in contract");
        msg.sender.transfer(_balance);
    }

    function withdrawMintingFees() public onlyOwner {
        require(totalMintingFees > 0, "No minting fees currently in contract");
         _payoutFundedDai(msg.sender, totalMintingFees);
        totalMintingFees = 0;
    }

    function setBaseMetadataURI(string memory _newBaseMetadataURI) public onlyOwner {
        super._setBaseMetadataURI(_newBaseMetadataURI);
    }

    function setCreationPriceFT(uint256 _price) public onlyOwner {
        creationPriceFT = _price;
    }

    function setCreationPriceNFT(uint256 _price) public onlyOwner {
        creationPriceNFT = _price;
    }

    function setMintingFee(uint256 _fee) public onlyOwner {
        mintingFee = _fee;
    }

    function setupDai(address _daiAddress, address _chaiAddress) public onlyOwner {
        // Check for existing funds in contract
        if (chaiAddress != address(0)) {
            uint256 _oldTokenBalance = chai.dai(address(this));
            require(_oldTokenBalance == 0, "Contract has an existing Chai balance");
        }

        // Set DAI as Funding Token
        daiAddress = _daiAddress;
        dai = IERC20(daiAddress);

        // Setup Chai to Tokenize DAI Interest
        chaiAddress = _chaiAddress;
        chai = IChai(chaiAddress);
        dai.approve(chaiAddress, uint(-1));
    }


    //
    // Private
    //

    function _collectRequiredDai(address _from, uint256 _requiredDai) internal {
        // Transfer DAI from User to Contract
        uint256 _userDaiBalance = dai.balanceOf(_from);
        require(_requiredDai <= _userDaiBalance, "Insufficient Dai for deposit");
        require(dai.transferFrom(_from, address(this), _requiredDai), "Failed to deposit Dai into Contract");
    }

    function _payoutFundedDai(address _to, uint256 _totalChai) internal {
        address _self = address(this);

        // Exit Chai and collect Dai + Interest
        chai.exit(_self, _totalChai);

        // Transfer Dai + Interest
        uint256 _receivedDai = dai.balanceOf(_self);
        require(dai.transferFrom(_self, _to, _receivedDai), "Failed to transfer Dai to User");
    }

    function _payoutChargedDai(address _to, uint256 _totalDai) internal {
        address _self = address(this);

        // Collect Interest
        chai.draw(_self, _totalDai);

        // Transfer Interest
        uint256 _receivedDai = dai.balanceOf(_self);
        require(dai.transferFrom(_self, _to, _receivedDai), "Failed to transfer Dai to User");
    }

    function _totalChaiForToken(uint256 _tokenChai) internal returns (uint256) {
        if (mintingFee == 0) { return _tokenChai; }
        uint256 _mintFee = (_tokenChai * mintingFee) / FEE_BASE;
        totalMintingFees = totalMintingFees.add(_mintFee);
        return _tokenChai.sub(_mintFee);
    }


    //
    // Unsupported Functions
    //

    function () external {
        revert("ChargedParticles: INVALID_METHOD");
    }
}

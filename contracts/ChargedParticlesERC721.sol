// ChargedParticlesERC721.sol -- Interest-bearing NFTs based on the DAI Savings Token
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
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

// ERROR CODES:
//  100:        ADDRESS, OWNER, OPERATOR
//      101         Invalid Address
//      102         Sender is not owner
//      103         Sender is not operator
//  200:        MATH
//      201         Underflow
//      202         Overflow
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

/**
 * @title Chai.money interface
 * @dev https://github.com/dapphub/chai
 */
contract IChai {
    function transfer(address dst, uint wad) external returns (bool);
    // like transferFrom but dai-denominated
    function move(address src, address dst, uint wad) external returns (bool);
    function transferFrom(address src, address dst, uint wad) public returns (bool);
    function approve(address usr, uint wad) external returns (bool);
    function balanceOf(address usr) external returns (uint);

    // Approve by signature
    function permit(address holder, address spender, uint256 nonce, uint256 expiry, bool allowed, uint8 v, bytes32 r, bytes32 s) external;

    function dai(address usr) external returns (uint wad);
    function dai(uint chai) external returns (uint wad);

    // wad is denominated in dai
    function join(address dst, uint wad) external;

    // wad is denominated in (1/chi) * dai
    function exit(address src, uint wad) public;

    // wad is denominated in dai
    function draw(address src, uint wad) external returns (uint chai);
}

/**
 * @title ERC165
 * @dev https://github.com/ethereum/EIPs/blob/master/EIPS/eip-165.md
 */
interface IERC165 {
    function supportsInterface(bytes4 _interfaceId) external view returns (bool);
}

/**
 * @title ERC20 interface
 * @dev see https://eips.ethereum.org/EIPS/eip-20
 */
interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function totalSupply() external view returns (uint256);
    function balanceOf(address who) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
 * @title ERC721 interface
 * @dev see https://eips.ethereum.org/EIPS/eip-721
 */
contract IERC721 {
    function balanceOf(address owner) public view returns (uint256 balance);
    function ownerOf(uint256 tokenId) public view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 tokenId) public;
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public;
    function transferFrom(address from, address to, uint256 tokenId) public;
    function approve(address to, uint256 tokenId) public;
    function getApproved(uint256 tokenId) public view returns (address operator);
    function setApprovalForAll(address operator, bool approved) public;
    function isApprovedForAll(address owner, address operator) public view returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
}

/**
 * @title ERC721 token receiver interface
 * @dev Interface for any contract that wants to support safeTransfers
 * from ERC721 asset contracts.
 */
contract IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes memory data) public returns (bytes4);
}

/**
 * @title SafeMath
 * @dev Unsigned math operations with safety checks that revert on error
 */
library SafeMath {

    function sub(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require(b <= a, "E201");
        c = a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a + b;
        require(c >= a, "E202");
    }
}

/**
 * @title Counters
 * @author Matt Condon (@shrugs)
 * @dev Provides counters that can only be incremented or decremented by one. This can be used e.g. to track the number
 * of elements in a mapping, issuing ERC721 ids, or counting request ids.
 */
library Counters {
    using SafeMath for uint256;

    struct Counter {
        // This variable should never be directly accessed by users of the library: interactions must be restricted to
        // the library's function. As of Solidity v0.5.2, this cannot be enforced, though there is a proposal to add
        // this feature: see https://github.com/ethereum/solidity/issues/4637
        uint256 _value; // default: 0
    }

    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    function increment(Counter storage counter) internal {
        counter._value += 1;
    }

    function decrement(Counter storage counter) internal {
        counter._value = counter._value.sub(1);
    }
}

/**
 * @title Implementation of ERC721 Non-Fungible Token Standard
 * @dev see node_modules/openzeppelin-solidity/contracts/token/ERC721/ERC721.sol
 */
contract ERC721 is IERC165, IERC721 {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    bytes4 constant internal INTERFACE_SIGNATURE_ERC165 = 0x01ffc9a7;
    bytes4 private constant INTERFACE_SIGNATURE_ERC721 = 0x80ac58cd;
    bytes4 private constant INTERFACE_SIGNATURE_ERC721_METADATA = 0x5b5e139f;
    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;
    bytes32 constant internal ACCOUNT_HASH = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;

    string private _name;
    string private _symbol;
    mapping(uint256 => string) private _tokenURIs;
    mapping (uint256 => address) private _tokenOwner;
    mapping (uint256 => address) private _tokenApprovals;
    mapping (address => Counters.Counter) private _ownedTokensCount;
    mapping (address => mapping (address => bool)) private _operatorApprovals;


    constructor (string memory name, string memory symbol) public {
        _name = name;
        _symbol = symbol;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "E303");
        return _tokenURIs[tokenId];
    }

    function supportsInterface(bytes4 _interfaceID) external view returns (bool) {
        if (_interfaceID == INTERFACE_SIGNATURE_ERC165 ||
            _interfaceID == INTERFACE_SIGNATURE_ERC721 ||
            _interfaceID == INTERFACE_SIGNATURE_ERC721_METADATA) {
            return true;
        }
        return false;
    }

    function balanceOf(address owner) public view returns (uint256) {
        require(owner != address(0), "E101");
        return _ownedTokensCount[owner].current();
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _tokenOwner[tokenId];
        require(owner != address(0), "E303");
        return owner;
    }

    function approve(address to, uint256 tokenId) public {
        address owner = ownerOf(tokenId);
        require(to != owner, "E301");

        require(msg.sender == owner || isApprovedForAll(owner, msg.sender), "E304");

        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        require(_exists(tokenId), "E303");
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address to, bool approved) public {
        require(to != msg.sender, "E301");
        _operatorApprovals[msg.sender][to] = approved;
        emit ApprovalForAll(msg.sender, to, approved);
    }

    function isApprovedForAll(address owner, address operator) public view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_isApprovedOrOwner(msg.sender, tokenId), "E304");
        _transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public {
        require(_isApprovedOrOwner(msg.sender, tokenId), "E304");
        _safeTransferFrom(from, to, tokenId, _data);
    }

    function _safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) internal {
        _transferFrom(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, _data), "E302");
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        address owner = _tokenOwner[tokenId];
        return owner != address(0);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        require(_exists(tokenId), "E303");
        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    function _safeMint(address to, uint256 tokenId, bytes memory _data) internal {
        _mint(to, tokenId);
        require(_checkOnERC721Received(address(0), to, tokenId, _data), "E302");
    }

    function _mint(address to, uint256 tokenId) internal {
        require(to != address(0), "E301");
        require(!_exists(tokenId), "E305");

        _tokenOwner[tokenId] = to;
        _ownedTokensCount[to].increment();

        emit Transfer(address(0), to, tokenId);
    }

    function _burn(address owner, uint256 tokenId) internal {
        require(ownerOf(tokenId) == owner, "E304");

        _clearApproval(tokenId);

        _ownedTokensCount[owner].decrement();
        _tokenOwner[tokenId] = address(0);

        // Clear metadata (if any)
        if (bytes(_tokenURIs[tokenId]).length != 0) {
            delete _tokenURIs[tokenId];
        }

        emit Transfer(owner, address(0), tokenId);
    }

    function _transferFrom(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from, "E304");
        require(to != address(0), "E301");

        _clearApproval(tokenId);

        _ownedTokensCount[from].decrement();
        _ownedTokensCount[to].increment();

        _tokenOwner[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory _data)
    internal returns (bool)
    {
        if (!_isContract(to)) {
            return true;
        }

        bytes4 retval = IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, _data);
        return (retval == _ERC721_RECEIVED);
    }

    function _clearApproval(uint256 tokenId) private {
        if (_tokenApprovals[tokenId] != address(0)) {
            _tokenApprovals[tokenId] = address(0);
        }
    }

    function _setTokenURI(uint256 tokenId, string memory uri) internal {
        require(_exists(tokenId), "E303");
        _tokenURIs[tokenId] = uri;
    }

    function _isContract(address _address) internal view returns (bool) {
        bytes32 codehash;
        assembly { codehash := extcodehash(_address) }
        return (codehash != 0x0 && codehash != ACCOUNT_HASH);
    }
}


/**
 * @notice Charged Particles Contract - Interest-Bearing NFTs
 *  -- ERC-721 Edition
 */
contract ChargedParticlesERC721 is ERC721 {
    using SafeMath for uint256;

    /***********************************|
    |        Variables and Events       |
    |__________________________________*/

    IERC20 internal dai;
    IChai internal chai;

    mapping(uint256 => uint256) internal chaiBalanceByTokenId;    // Amount of Chai minted from Dai deposited

    uint256 internal totalMintedTokens;
    uint256 internal mintFee;
    uint256 internal collectedFees;
    uint256 internal requiredFunding;   // Amount of Dai to deposit when minting

    address private owner; // To be assigned to a DAO

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

    constructor() ERC721("ChargedParticles", "IONS") public {
//        requiredFunding = 1e18;
//        mintFee = 50;    //  0.5% of Chai from deposited Dai

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
        chaiBalanceByTokenId[_tokenId] = chaiBalanceByTokenId[_tokenId] - _paidChai;

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

            _tokenId = (totalMintedTokens + i + 1);
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
     * @dev Calculates the amount of DAI held within a token during minting
     *      Note: Accounts for any contract fees
     * @param _tokenChai    The total amount of DAI used to fund the token
     * @return  The actual amount of DAI to fund the token - fees
     */
    function _totalChaiForToken(uint256 _tokenChai) internal returns (uint256) {
        if (mintFee == 0) { return _tokenChai; }
        uint256 _mintFee = (_tokenChai * mintFee) / 1e4;
        collectedFees = collectedFees.add(_mintFee);
        return _tokenChai.sub(_mintFee);
    }
}

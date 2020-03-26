// ChaiNucleus.sol -- Charged Particles
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


// [original] chai.sol -- a dai savings token
// Copyright (C) 2017, 2018, 2019 dbrock, rain, mrchico, lucasvo, livnev

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.


// Modified for use in Charged Particles by @robsecord <robsecord.eth>;
//   added functions to read interest by specific amount rather than entire user balance
//   removed permit since this Chai should only be controlled
//   via the ChargedParticles contract


// Resources:
// ~~~~~~~~~~
// https://github.com/dapphub/chai/blob/master/src/chai.sol
// https://github.com/makerdao/developerguides/blob/master/dai/dsr-integration-guide/dsr-integration-guide-01.md#smart-contract-addresses-and-abis
//
// Contract Addresses/ABI:
//   https://changelog.makerdao.com/releases/mainnet/1.0.0/index.html
//   https://changelog.makerdao.com/releases/kovan/0.2.17/index.html


pragma solidity 0.5.16;

import "../INucleus.sol";

contract VatLike {
    function hope(address) external;
}

contract PotLike {
    function chi() external returns (uint256);
    function rho() external returns (uint256);
    function drip() external returns (uint256);
    function join(uint256) external;
    function exit(uint256) external;
}

contract JoinLike {
    function join(address, uint) external;
    function exit(address, uint) external;
}

contract GemLike {
    function transferFrom(address,address,uint) external returns (bool);
    function approve(address,uint) external returns (bool);
}

contract ChaiNucleus is INucleus {
    // --- Data ---
    VatLike  public vat;
    PotLike  public pot;
    JoinLike public daiJoin;
    GemLike  public daiToken;

    // --- ERC20 Data ---
    string  public constant name     = "ParticleChai";
    string  public constant symbol   = "PCHAI";
    string  public constant version  = "1";
    uint8   public constant decimals = 18;
    uint256 public totalSupply;

    mapping (address => uint) private balanceOf;

    event Approval(address indexed src, address indexed guy, uint wad);
    event Transfer(address indexed src, address indexed dst, uint wad);

    // --- Math ---
    uint constant RAY = 10 ** 27;
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function rmul(uint x, uint y) internal pure returns (uint z) {
        // always rounds down
        z = mul(x, y) / RAY;
    }
    function rdiv(uint x, uint y) internal pure returns (uint z) {
        // always rounds down
        z = mul(x, RAY) / y;
    }
    function rdivup(uint x, uint y) internal pure returns (uint z) {
        // always rounds up
        z = add(mul(x, RAY), sub(y, 1)) / y;
    }

    function initialize() public {
        vat.hope(address(daiJoin));
        vat.hope(address(pot));

        daiToken.approve(address(daiJoin), uint(-1));
    }

    function initRopsten() public {
        vat = VatLike(0xA85B3d84f54Fb238Ef257158da99FdfCe905C7aA);           // Deployed copy of: contracts/assets/dai/DaiVat.sol
        pot = PotLike(0x47563186A46Aa3EBbEA5D294c8514f0ED49f2e2c);           // Deployed copy of: contracts/assets/dai/DaiPot.sol
        daiJoin = JoinLike(0x298cb5798c0F0af4850d1a380E28E25C02FF087A);      // Deployed copy of: contracts/assets/dai/DaiJoin.sol
        daiToken = GemLike(0x8B7f1E7F3412331F1Cd317EAE5040DfE5eaAdAe6);      // Deployed copy of: contracts/assets/dai/DaiGem.sol

        initialize();
    }

    function initKovan() public {
        vat = VatLike(0xbA987bDB501d131f766fEe8180Da5d81b34b69d9);         // MCD_VAT
        pot = PotLike(0xEA190DBDC7adF265260ec4dA6e9675Fd4f5A78bb);         // MCD_POT
        daiJoin = JoinLike(0x5AA71a3ae1C0bd6ac27A1f28e1415fFFB6F15B8c);    // MCD_JOIN_DAI
        daiToken = GemLike(0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa);    // MCD_DAI

        initialize();
    }

    function initMainnet() public {
        vat = VatLike(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);         // MCD_VAT
        pot = PotLike(0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7);         // MCD_POT
        daiJoin = JoinLike(0x9759A6Ac90977b93B58547b4A71c78317f391A28);    // MCD_JOIN_DAI
        daiToken = GemLike(0x6B175474E89094C44Da98b954EedeAC495271d0F);    // MCD_DAI

        initialize();
    }

    /**
     * @dev Balance in Interest-bearing Token
     */
    //    function balanceOf(address _account) external returns (uint);
    function interestBalance(address _account) external returns (uint) {
        return balanceOf[_account];
    }

    /**
     * @dev Balance in Asset Token
     */
    //    function dai(address usr) external returns (uint wad);
    function assetBalance(address _account) external returns (uint) {
        uint chi = (now > pot.rho()) ? pot.drip() : pot.chi();
        return rmul(chi, balanceOf[_account]);
    }

    /**
     * @dev Get amount of Asset Token equivalent to Interest Token
     */
    //    function dai(uint chai) external returns (uint wad); // Added
    function toAsset(uint _interestAmount) external returns (uint) {
        uint chi = (now > pot.rho()) ? pot.drip() : pot.chi();
        return rmul(chi, _interestAmount);
    }

    /**
     * @dev Get amount of Interest Token equivalent to Asset Token
     */
    //    function chai(uint _dai) external returns (uint pie); // Added
    function toInterest(uint _assetAmount) external returns (uint) {
        uint chi = (now > pot.rho()) ? pot.drip() : pot.chi();
        // rounding up ensures usr gets at least _assetAmount dai
        return rdivup(_assetAmount, chi);
    }

    /**
     * @dev Deposit Asset Token and receive Interest-bearing Token
     */
    //    function join(address dst, uint wad) external;
    function depositAsset(address _account, uint _assetAmount) external {
        uint chi = (now > pot.rho()) ? pot.drip() : pot.chi();
        uint pie = rdiv(_assetAmount, chi);
        balanceOf[_account] = add(balanceOf[_account], pie);
        totalSupply = add(totalSupply, pie);

        daiToken.transferFrom(msg.sender, address(this), _assetAmount);
        daiJoin.join(address(this), _assetAmount);
        pot.join(pie);

        emit Transfer(address(0), _account, pie);
    }

    /**
     * @dev Withdraw amount specified in Interest-bearing Token
     */
    //    function exit(address src, uint wad) public;
    function withdrawInterest(address _account, uint _interestAmount) public {
        require(_account == msg.sender, "pchai/insufficient-allowance");
        require(balanceOf[_account] >= _interestAmount, "pchai/insufficient-balance");

        balanceOf[_account] = sub(balanceOf[_account], _interestAmount);
        totalSupply = sub(totalSupply, _interestAmount);

        uint chi = (now > pot.rho()) ? pot.drip() : pot.chi();
        pot.exit(_interestAmount);
        daiJoin.exit(msg.sender, rmul(chi, _interestAmount));
        emit Transfer(_account, address(0), _interestAmount);
    }

    /**
     * @dev Withdraw amount specified in Asset Token
     */
    //    function draw(address src, uint wad) external returns (uint _chai);
    function withdrawAsset(address _account, uint _assetAmount) external returns (uint) {
        uint chi = (now > pot.rho()) ? pot.drip() : pot.chi();
        // rounding up ensures usr gets at least _assetAmount dai
        uint _chai = rdivup(_assetAmount, chi);
        withdrawInterest(_account, _chai);
        return _chai;
    }
}

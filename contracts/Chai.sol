// chai.sol -- a dai savings token
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


// Updated by @robsecord <robsecord.eth>;
//   added function to read interest by wad rather than entire user balance
//     - function dai(uint chai) external returns (uint wad)
//   removed permit since this Chai should only be controlled
//   via the ChargedParticles contract


// Resources:
// ~~~~~~~~~~
// https://github.com/dapphub/chai/blob/master/src/chai.sol
// https://github.com/makerdao/developerguides/blob/master/dai/dsr-integration-guide/dsr-integration-guide-01.md#smart-contract-addresses-and-abis
// https://github.com/mattlockyer/composables-998/blob/master/contracts/ComposableTopDown.sol
// https://kauri.io/gamifying-crypto-assets-with-the-erc998-composables-token-standard/436178ce670d4a9e9ffbd9cb7a8476fd/a
//
// Contract Addresses/ABI:
//   https://changelog.makerdao.com/releases/mainnet/1.0.0/index.html
//   https://changelog.makerdao.com/releases/kovan/0.2.17/index.html

pragma solidity 0.5.13;

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

contract Chai {
    // --- Data ---
    // Mainnet:
    // VatLike  public vat = VatLike( 0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);         // MCD_VAT
    // PotLike  public pot = PotLike( 0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7);         // MCD_POT
    // JoinLike public daiJoin = JoinLike( 0x9759A6Ac90977b93B58547b4A71c78317f391A28);    // MCD_JOIN_DAI
    // GemLike  public daiToken = GemLike( 0x6B175474E89094C44Da98b954EedeAC495271d0F);    // MCD_DAI

    // Kovan:
    VatLike  public vat = VatLike( 0xbA987bDB501d131f766fEe8180Da5d81b34b69d9);         // MCD_VAT
    PotLike  public pot = PotLike( 0xEA190DBDC7adF265260ec4dA6e9675Fd4f5A78bb);         // MCD_POT
    JoinLike public daiJoin = JoinLike( 0x5AA71a3ae1C0bd6ac27A1f28e1415fFFB6F15B8c);    // MCD_JOIN_DAI
    GemLike  public daiToken = GemLike( 0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa);    // MCD_DAI

    // --- ERC20 Data ---
    string  public constant name     = "ParticleChai";
    string  public constant symbol   = "PCHAI";
    string  public constant version  = "1";
    uint8   public constant decimals = 18;
    uint256 public totalSupply;

    mapping (address => uint)                      public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;
    mapping (address => uint)                      public nonces;

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

    constructor() public {
        vat.hope(address(daiJoin));
        vat.hope(address(pot));

        daiToken.approve(address(daiJoin), uint(-1));
    }

    // --- Token ---
    function transfer(address dst, uint wad) external returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }
    // like transferFrom but dai-denominated
    function move(address src, address dst, uint wad) external returns (bool) {
        uint chi = (now > pot.rho()) ? pot.drip() : pot.chi();
        // rounding up ensures dst gets at least wad dai
        return transferFrom(src, dst, rdivup(wad, chi));
    }
    function transferFrom(address src, address dst, uint wad) public returns (bool) {
        require(balanceOf[src] >= wad, "chai/insufficient-balance");
        if (src != msg.sender && allowance[src][msg.sender] != uint(-1)) {
            require(allowance[src][msg.sender] >= wad, "chai/insufficient-allowance");
            allowance[src][msg.sender] = sub(allowance[src][msg.sender], wad);
        }
        balanceOf[src] = sub(balanceOf[src], wad);
        balanceOf[dst] = add(balanceOf[dst], wad);
        emit Transfer(src, dst, wad);
        return true;
    }
    function approve(address usr, uint wad) external returns (bool) {
        allowance[msg.sender][usr] = wad;
        emit Approval(msg.sender, usr, wad);
        return true;
    }

    function dai(address usr) external returns (uint wad) {
        uint chi = (now > pot.rho()) ? pot.drip() : pot.chi();
        wad = rmul(chi, balanceOf[usr]);
    }

    function dai(uint chai) external returns (uint wad) {
        uint chi = (now > pot.rho()) ? pot.drip() : pot.chi();
        wad = rmul(chi, chai);
    }

    // wad is denominated in dai
    function join(address dst, uint wad) external {
        uint chi = (now > pot.rho()) ? pot.drip() : pot.chi();
        uint pie = rdiv(wad, chi);
        balanceOf[dst] = add(balanceOf[dst], pie);
        totalSupply    = add(totalSupply, pie);

        daiToken.transferFrom(msg.sender, address(this), wad);
        daiJoin.join(address(this), wad);
        pot.join(pie);
        emit Transfer(address(0), dst, pie);
    }

    // wad is denominated in (1/chi) * dai
    function exit(address src, uint wad) public {
        require(balanceOf[src] >= wad, "chai/insufficient-balance");
        if (src != msg.sender && allowance[src][msg.sender] != uint(-1)) {
            require(allowance[src][msg.sender] >= wad, "chai/insufficient-allowance");
            allowance[src][msg.sender] = sub(allowance[src][msg.sender], wad);
        }
        balanceOf[src] = sub(balanceOf[src], wad);
        totalSupply    = sub(totalSupply, wad);

        uint chi = (now > pot.rho()) ? pot.drip() : pot.chi();
        pot.exit(wad);
        daiJoin.exit(msg.sender, rmul(chi, wad));
        emit Transfer(src, address(0), wad);
    }

    // wad is denominated in dai
    function draw(address src, uint wad) external returns (uint chai) {
        uint chi = (now > pot.rho()) ? pot.drip() : pot.chi();
        // rounding up ensures usr gets at least wad dai
        chai = rdivup(wad, chi);
        exit(src, chai);
    }
}

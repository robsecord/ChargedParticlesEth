
pragma solidity 0.5.13;

contract DevChai {
    // --- ERC20 Data ---
    string  public constant name     = "DevChai";
    string  public constant symbol   = "DCHAI";
    string  public constant version  = "1";
    uint8   public constant decimals = 18;

    uint256 public totalSupply;
    mapping (address => uint) public balanceOf;

    constructor() public {
    }

    function dai(uint chai) external pure returns (uint wad) {
        wad = chai + 1;
    }

    // wad is denominated in dai
    function join(address dst, uint wad) external {
        balanceOf[dst] = balanceOf[dst] + wad;
        totalSupply    = totalSupply + wad;
    }

    // wad is denominated in (1/chi) * dai
    function exit(address src, uint wad) public {
        require(balanceOf[src] >= wad, "chai/insufficient-balance");
        balanceOf[src] = balanceOf[src] - wad;
        totalSupply    = totalSupply - wad;
    }

    // wad is denominated in dai
    function draw(address src, uint wad) external returns (uint chai) {
        chai = wad;
        exit(src, chai);
    }
}

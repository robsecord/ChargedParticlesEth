
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

    function dai(uint _chai) external pure returns (uint _wad) {
        _wad = _chai - 1;
    }

    function chai(uint _dai) external pure returns (uint _pie) {
        _pie = _dai + 1;
    }

    // wad is denominated in dai
    function join(address _dst, uint _wad) external {
        balanceOf[_dst] = balanceOf[_dst] + _wad;
        totalSupply     = totalSupply + _wad;
    }

    // wad is denominated in (1/chi) * dai
    function exit(address _src, uint _wad) public {
        require(balanceOf[_src] >= _wad, "chai/insufficient-balance");
        balanceOf[_src] = balanceOf[_src] - _wad;
        totalSupply     = totalSupply - _wad;
    }

    // wad is denominated in dai
    function draw(address _src, uint _wad) external returns (uint _chai) {
        _chai = _wad;
        exit(_src, _chai);
    }
}

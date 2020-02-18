pragma solidity 0.5.16;

contract RopstenDaiPot {
    event Joined(uint256 wad);
    event Exited(uint256 wad);

    function chi() external returns (uint256) {
        return 1;
    }
    function rho() external returns (uint256) {
        return 1;
    }
    function drip() external returns (uint256) {
        return 1;
    }
    function join(uint256 wad) external {
        emit Joined(wad);
    }
    function exit(uint256 wad) external {
        emit Exited(wad);
    }
}

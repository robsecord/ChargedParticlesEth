pragma solidity 0.5.16;

contract DaiJoin {
    event Joined(address who, uint wad);
    event Exited(address who, uint wad);

    function join(address who, uint wad) external {
        emit Joined(who, wad);
    }
    function exit(address who, uint wad) external {
        emit Exited(who, wad);
    }
}

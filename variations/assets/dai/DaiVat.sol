pragma solidity 0.5.16;

contract DaiVat {
    event Hoped(address who);

    function hope(address who) external {
        emit Hoped(who);
    }
}

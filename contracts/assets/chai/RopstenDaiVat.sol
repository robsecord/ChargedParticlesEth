pragma solidity 0.5.16;

contract RopstenDaiVat {
    event Hoped(address who);

    function hope(address who) external {
        emit Hoped(who);
    }
}

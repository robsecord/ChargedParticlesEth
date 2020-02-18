pragma solidity 0.5.16;

contract RopstenDaiGem {
    event Transfer(address indexed from, address to, uint amount);
    event Approve(address indexed spender, uint amount);

    function transferFrom(address from, address to, uint amount) external returns (bool) {
        emit Transfer(from, to, amount);
        return true;
    }
    function approve(address spender, uint amount) external returns (bool) {
        emit Approve(spender, amount);
        return true;
    }
}

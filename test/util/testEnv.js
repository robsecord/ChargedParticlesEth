const buidler = require('@nomiclabs/buidler');
const { deployContract } = require('ethereum-waffle');
const { ethers } = require('ethers');
const { expect } = require('chai');

const presets = {
    txOverrides: { gasLimit: 20000000 }
};

const toWei = ethers.utils.parseEther;
const toStr = (val) => ethers.utils.toUtf8String(val).replace(/\0/g, '');

buidler.ethers.errors.setLogLevel('error');

module.exports = {
    buidler,
    ethers,
    expect,
    deployContract,
    presets,
    toWei,
    toStr,
};


'use strict';

const _ = require('lodash');

const Lib = {};

Lib.network = '';

Lib.promisify = (fn) => (...args) => new Promise((resolve, reject) => {
    fn(...args, (err, result) => {
        if (err) {
            reject(err);
        } else {
            resolve(result);
        }
    });
});

Lib.fromFinneyToWei = (value) => web3.utils.toWei(value.toString(), 'finney');
Lib.fromWeiToGwei = (value) => web3.utils.fromWei(value.toString(), 'gwei');
Lib.fromWeiToEther = (value) => web3.utils.fromWei(value.toString(), 'ether');
Lib.fromFinneyToEther = (value) => web3.utils.fromWei(Lib.fromFinneyToWei(value), 'ether');

Lib.ethTxCount = Lib.promisify(web3.eth.getTransactionCount);
Lib.getTxCount = (owner) => Lib.ethTxCount(owner);

Lib.log = ({msg, indent = 0, spacer = false, separator = false}) => {
    const msgArr = [];
    if (indent > 0) {
        const indentLevel = _.times(indent, _.constant('--')).join('');
        msgArr.push(' ', indentLevel);
    } else if (spacer) {
        msgArr.push(' ');
    } else if (separator) {
        msgArr.push('~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
    } else {
        msgArr.push('[Deployer]')
    }
    if (!spacer && !separator) {
        msgArr.push(msg);
    }
    console.log(msgArr.join(' '));
};

Lib.logTxResult = (result) => {
    if (result.receipt) {
        Lib.log({msg: `TX hash:      ${result.tx}`, indent: 2});
        Lib.log({msg: `TX status:    ${result.receipt.status}`, indent: 2});
        Lib.log({msg: `TX gas used:  ${result.receipt.gasUsed}`, indent: 2});
    } else if (result.gasUsed) {
        Lib.log({msg: `TX gas used:  ${result.gasUsed}`, indent: 2});
    }
    Lib.log({spacer: true});
};

Lib.delay = (timeout) => new Promise((resolve) => {
    setTimeout(() => { resolve(); }, timeout);
});

Lib.getContractInstance = (contract, contractAddress) => {
    // Dirty hack for web3@1.0.0 support for localhost testrpc,
    // see https://github.com/trufflesuite/truffle-contract/issues/56#issuecomment-331084530
    if (typeof contract.currentProvider.sendAsync !== "function") {
        contract.currentProvider.sendAsync = function () {
            return contract.currentProvider.send.apply(contract.currentProvider, arguments);
        };
    }
    return contract.at(contractAddress);
};

module.exports = { Lib };


'use strict';

// Required by zos-lib when running from truffle
global.artifacts = artifacts;
global.web3 = web3;

const { Lib } = require('./common');
const {
    networkOptions,
} = require('../config');
const _ = require('lodash');

const Chai = artifacts.require('Chai');
const ChargedParticles = artifacts.require('ChargedParticles');


module.exports = async function(deployer, network, accounts) {
    let nonce = 0;

    Lib.network = (network || '').replace('-fork', '');
    if (_.isUndefined(networkOptions[Lib.network])) {
        Lib.network = 'local';
    }

    const owner = accounts[0];
    const options = networkOptions[Lib.network];

    const _getTxOptions = (opts = {}) => {
        const gasPrice = options.gasPrice;
        return _.assignIn({from: owner, nonce: nonce++, gasPrice}, opts);
    };

    Lib.log({msg: `Network:   ${Lib.network}`});
    Lib.log({msg: `Web3:      ${web3.version}`});
    Lib.log({msg: `Gas Price: ${Lib.fromWeiToGwei(options.gasPrice)} GWEI`});
    Lib.log({msg: `Owner:     ${owner}`});
    Lib.log({separator: true});

    try {
        let receipt;

        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // Get Transaction Nonce
        nonce = (await Lib.getTxCount(owner)) || 0;
        Lib.log({msg: `Starting at Nonce: ${nonce}`});
        Lib.log({separator: true});
        Lib.log({spacer: true});
        Lib.log({spacer: true});

        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // Deploy Contracts
        Lib.log({spacer: true});
        Lib.log({msg: '-- Chai --'});
        const chai = await deployer.deploy(Chai, _getTxOptions());
        Lib.log({msg: '-- ChargedParticles --'});
        const chargedParticles = await deployer.deploy(ChargedParticles, _getTxOptions());

        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // Deploy Complete
        Lib.log({separator: true});
        Lib.log({separator: true});

        Lib.log({spacer: true});
        Lib.log({spacer: true});

        Lib.log({msg: 'Contract Addresses:'});
        Lib.log({msg: `Chai: ${chai.address}`, indent: 1});
        Lib.log({msg: `ChargedParticles: ${chargedParticles.address}`, indent: 1});
    }
    catch (err) {
        console.log(err);
    }
};

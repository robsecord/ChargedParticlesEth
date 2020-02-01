
'use strict';
//
// import Web3 from 'web3';
// const web3 = new Web3();

// Required by zos-lib when running from truffle
global.artifacts = artifacts;
global.web3 = web3;

const { Lib } = require('./common');
const {
    networkOptions,
} = require('../config');
const _ = require('lodash');

const Chai = artifacts.require('Chai');
const ChargedParticlesERC721 = artifacts.require('ChargedParticlesERC721');
const ChargedParticlesERC1155 = artifacts.require('ChargedParticlesERC1155');


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
        let chargedParticlesERC721;
        let chargedParticlesERC1155;
        let chai;
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
        if (Lib.network !== 'local') {
            Lib.log({msg: '-- Chai --'});
            chai = await deployer.deploy(Chai, _getTxOptions());
        }
        Lib.log({msg: '-- ChargedParticlesERC721 --'});
        chargedParticlesERC721 = await deployer.deploy(ChargedParticlesERC721, _getTxOptions());
        Lib.log({msg: '-- chargedParticlesERC1155 --'});
        chargedParticlesERC1155 = await deployer.deploy(ChargedParticlesERC1155, _getTxOptions());

        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // Deploy Complete
        Lib.log({separator: true});
        Lib.log({separator: true});

        Lib.log({spacer: true});
        Lib.log({spacer: true});

        Lib.log({msg: 'Contract Addresses:'});
        if (Lib.network !== 'local') {
            Lib.log({msg: `Chai: ${chai.address}`, indent: 1});
        }
        Lib.log({msg: `ChargedParticlesERC721: ${chargedParticlesERC721.address}`, indent: 1});
        Lib.log({msg: `ChargedParticlesERC1155: ${chargedParticlesERC1155.address}`, indent: 1});
    }
    catch (err) {
        console.log(err);
    }
};

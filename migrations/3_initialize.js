
'use strict';

// Required by zos-lib when running from truffle
global.artifacts = artifacts;
global.web3 = web3;

const { Lib } = require('./common');
const {
    daiAddress,
    networkOptions,
    baseMetadataUri,
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
    const daiToken = daiAddress[Lib.network];
    const baseUri = baseMetadataUri[Lib.network];

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
        const chai = await Chai.deployed();
        const chargedParticles = await ChargedParticles.deployed();
        let receipt;

        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // Get Transaction Nonce
        nonce = (await Lib.getTxCount(owner)) || 0;
        Lib.log({msg: `Starting at Nonce: ${nonce}`});
        Lib.log({separator: true});
        Lib.log({spacer: true});
        Lib.log({spacer: true});

        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // Set contract addresses
        Lib.log({spacer: true});
        Lib.log({msg: '-- Set Dai/Chai Addresses --'});
        Lib.log({msg: `DAI: ${daiToken}`, indent: 1});
        Lib.log({msg: `CHAI: ${chai.address}`, indent: 1});
        receipt = await chargedParticles.setupDai(daiToken, chai.address, _getTxOptions());
        Lib.logTxResult(receipt);

        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // Set Base Metadata URI
        if (!_.isEmpty(baseUri)) {
            Lib.log({spacer: true});
            Lib.log({msg: '-- Set Base Metadata URI --'});
            Lib.log({msg: `URI: ${baseUri}`, indent: 1});
            receipt = await chargedParticles.setBaseMetadataURI(baseUri, _getTxOptions());
            Lib.logTxResult(receipt);
        }

        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // Initializations Complete
        Lib.log({separator: true});
        Lib.log({separator: true});
    }
    catch (err) {
        console.log(err);
    }
};

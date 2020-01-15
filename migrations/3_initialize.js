
'use strict';

// Required by zos-lib when running from truffle
global.artifacts = artifacts;
global.web3 = web3;

const { Lib } = require('./common');
const {
    daiAddress,
    networkOptions,
    tokenSetupData,
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
    const daiToken = daiAddress[Lib.network];
    const tokenSetup = tokenSetupData[Lib.network];

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
        let chai = {address: '0x06af07097c9eeb7fd685c692751d5c66db49c215'};
        if (Lib.network !== 'local') {
            chai = await Chai.deployed();
        }
        const chargedParticlesERC721 = await ChargedParticlesERC721.deployed();
        const chargedParticlesERC1155 = await ChargedParticlesERC1155.deployed();
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
        Lib.log({msg: '-- Setup ChargedParticlesERC721 --'});
        Lib.log({msg: `Dai: ${daiToken}`, indent: 1});
        Lib.log({msg: `Chai: ${chai.address}`, indent: 1});
        Lib.log({msg: `MintFee: ${tokenSetup.mintFee}`, indent: 1});
        Lib.log({msg: `RequireFunds: ${tokenSetup.requiredFundsErc721}`, indent: 1});
        receipt = await chargedParticlesERC721.setup(daiToken, chai.address, tokenSetup.mintFee, tokenSetup.requiredFundsErc721,  _getTxOptions());
        Lib.logTxResult(receipt);

        Lib.log({spacer: true});
        Lib.log({msg: '-- Setup ChargedParticlesERC1155 --'});
        Lib.log({msg: `Dai: ${daiToken}`, indent: 1});
        Lib.log({msg: `Chai: ${chai.address}`, indent: 1});
        Lib.log({msg: `CreateFee: ${tokenSetup.createFee}`, indent: 1});
        Lib.log({msg: `MintFee: ${tokenSetup.mintFee}`, indent: 1});
        receipt = await chargedParticlesERC1155.setup(daiToken, chai.address, tokenSetup.createFee, tokenSetup.mintFee, _getTxOptions());
        Lib.logTxResult(receipt);

        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // Initializations Complete
        Lib.log({separator: true});
        Lib.log({separator: true});
    }
    catch (err) {
        console.log(err);
    }
};

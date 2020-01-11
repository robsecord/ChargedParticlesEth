
require('dotenv').config();

const HDWalletProvider = require("truffle-hdwallet-provider");
const { infura, wallets, networkOptions } = require('./config');

module.exports = {
    // See <http://truffleframework.com/docs/advanced/configuration>
    // to customize your Truffle configuration!
    networks: {
        local: {
            host          : '127.0.0.1',
            port          : 7545,
            network_id    : '5777',                             // Ganache
            gas           : networkOptions.local.gas,
            gasPrice      : networkOptions.local.gasPrice,
            confirmations : 0,                                  // # of confs to wait between deployments. (default: 0)
            timeoutBlocks : 50,                                 // # of blocks before a deployment times out  (minimum/default: 50)
            skipDryRun    : true                                // Skip dry run before migrations? (default: false for public nets)
        },
        kovan: {
            provider      : new HDWalletProvider(wallets.kovan.mnemonic, infura.endpoint, wallets.kovan.accountIndex), //, 1, true, "m/44'/1'/0'/0/"),
            network_id    : '42',                               // Kovan Testnet
            gas           : networkOptions.kovan.gas,           // https://kovan.etherscan.io/blocks
            gasPrice      : networkOptions.kovan.gasPrice,      // https://kovan.etherscan.io/gastracker
            confirmations : 0,                                  // # of confs to wait between deployments. (default: 0)
            timeoutBlocks : 50,                                 // # of blocks before a deployment times out  (minimum/default: 50)
            skipDryRun    : true                                // Skip dry run before migrations? (default: false for public nets)
        },
        mainnet: {
            provider      : new HDWalletProvider(wallets.mainnet.mnemonic, infura.endpoint, wallets.mainnet.accountIndex), //, 1, true, "m/44'/1'/0'/0/"),
            network_id    : '1',                                // Mainnet
            gas           : networkOptions.mainnet.gas,         // https://etherscan.io/blocks
            gasPrice      : networkOptions.mainnet.gasPrice,    // https://etherscan.io/gastracker
            confirmations : 1,                                  // # of confs to wait between deployments. (default: 0)
            timeoutBlocks : 200,                                // # of blocks before a deployment times out  (minimum/default: 50)
            skipDryRun    : true                                // Skip dry run before migrations? (default: false for public nets)
        }
    },
    compilers: {
        solc: {
            version: '0.5.13',
            settings: {
                optimizer: {
                    enabled: false,
                    runs: 200
                },
                // evmVersion: 'petersburg' // Important, see https://github.com/trufflesuite/truffle/issues/2416
            }
        }
    }
};

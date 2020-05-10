
require('dotenv').config();

const HDWalletProvider = require("@truffle/hdwallet-provider");
const walletMnemonic = process.env.WALLET_TEST_MNEMONIC.replace(/_/g, ' ');

module.exports = {
    networks: {
        development: {
            provider: function() {
                return new HDWalletProvider(walletMnemonic, "http://127.0.0.1:8545/");
            },
            network_id: '*',
        },
    },
    compilers: {
        solc: {
            version: '0.5.16',
            optimizer: {
                enabled: true,
                runs: 200
            }
        }
    },
    plugins: ["solidity-coverage"],
  };

const HDWalletProvider = require('@truffle/hdwallet-provider');

require('dotenv').config();

const mnemonic = {
  kovan: process.env.KOVAN_WALLET_MNEMONIC,
  mainnet: process.env.MAINNET_WALLET_MNEMONIC,
};

module.exports = {
  networks: {
    development: {
      protocol: 'http',
      host: 'localhost',
      port: 8545,
      gas: 5000000,
      gasPrice: 5e9,
      networkId: '*',
    },
    kovan: {
      provider: () => new HDWalletProvider(
        mnemonic.kovan, `https://kovan.infura.io/v3/${process.env.INFURA_API_KEY}`
      ),
      networkId: 42,
      gasPrice: 10e9
    }
  },
};

const HDWalletProvider = require('@truffle/hdwallet-provider');

require('dotenv').config();

const mnemonic = {
  // PROXY
  // kovan: process.env.KOVAN_PROXY_MNEMONIC,
  // ropsten: process.env.ROPSTEN_PROXY_MNEMONIC,
  // mainnet: process.env.MAINNET_PROXY_MNEMONIC,

  // OWNER
  kovan: process.env.KOVAN_OWNER_MNEMONIC,
  ropsten: process.env.ROPSTEN_OWNER_MNEMONIC,
  mainnet: process.env.MAINNET_OWNER_MNEMONIC,
};

module.exports = {
  networks: {
    development: {
      protocol: 'http',
      host: 'localhost',
      port: 8545,
      gas: 6000000,
      gasPrice: 1e9,
      networkId: '*',
    },
    kovan: {
      provider: () => new HDWalletProvider(
        mnemonic.kovan, `https://kovan.infura.io/v3/${process.env.INFURA_API_KEY}`
      ),
      networkId: 42,
      gasPrice: 10e9
    },
    ropsten: {
      provider: () => new HDWalletProvider(
          mnemonic.kovan, `https://ropsten.infura.io/v3/${process.env.INFURA_API_KEY}`
      ),
      networkId: 3,
      gasPrice: 10e9
    }
  },
};

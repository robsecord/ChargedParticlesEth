const HDWalletProvider = require('@truffle/hdwallet-provider');
const maxGas = 20000000;

require('dotenv').config();

const mnemonic = {
  // PROXY
  // kovan: `${process.env.KOVAN_PROXY_MNEMONIC}`.replace(/_/g, ' '),
  // ropsten: `${process.env.ROPSTEN_PROXY_MNEMONIC}`.replace(/_/g, ' '),
  // mainnet: `${process.env.MAINNET_PROXY_MNEMONIC}`.replace(/_/g, ' '),

  // OWNER
  kovan: `${process.env.KOVAN_OWNER_MNEMONIC}`.replace(/_/g, ' '),
  ropsten: `${process.env.ROPSTEN_OWNER_MNEMONIC}`.replace(/_/g, ' '),
  mainnet: `${process.env.MAINNET_OWNER_MNEMONIC}`.replace(/_/g, ' '),
};

module.exports = {
  networks: {
    local: {
      host: 'localhost',
      port: '8545',
      gas: maxGas,
      gasPrice: 1 * 1000000000,
      network_id: '*'
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
        mnemonic.ropsten, `https://ropsten.infura.io/v3/${process.env.INFURA_API_KEY}`
      ),
      networkId: 3,
      gasPrice: 10e9
    }
  },
};

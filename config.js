
const config = {
    infura: {
        endpoint: {
            kovan: `https://kovan.infura.io/v3/${process.env.INFURA_API_KEY}`,
            mainnet: `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`,
        }
    },

    etherscan: {
        apiKey: process.env.ETHERSCAN_API_KEY
    },

    tokenSetupData: {
        local: {
            requiredFundsErc721 : '1000000000000000000',
            createFeeEth        : '35000000000000',                 // 0.000035 ETH
            createFeeIon        : '100000000000000000000',          // 100 ION
            mintFee             : '50',
            ionTokenUrl         : 'https://ion.particles.network/token_data/',
            ionTokenSupply      : '1000000000000000000000000',      // 1 million ION
        },
        kovan: {
            requiredFundsErc721 : '1000000000000000000',
            createFeeEth        : '35000000000000',                 // 0.000035 ETH
            createFeeIon        : '100000000000000000000',          // 100 ION
            mintFee             : '50',
            ionTokenUrl         : 'https://ion.particles.network/token_data/',
            ionTokenSupply      : '1000000000000000000000000',      // 1 million ION
        },
        mainnet: {
            requiredFundsErc721 : '1000000000000000000',
            createFeeEth        : '35000000000000',                 // 0.000035 ETH
            createFeeIon        : '100000000000000000000',          // 100 ION
            mintFee             : '50',
            ionTokenUrl         : 'https://ion.particles.network/token_data/',
            ionTokenSupply      : '1000000000000000000000000',      // 1 million ION
        }
    },

    daiAddress: {
        local   : '0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa',
        kovan   : '0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa',
        mainnet : '0x6B175474E89094C44Da98b954EedeAC495271d0F'
    },

    wallets: {
        local: {
            owner        : process.env.LOCAL_OWNER_ACCOUNT,
            mnemonic     : process.env.LOCAL_WALLET_MNEMONIC,
            accountIndex : 0
        },
        kovan: {
            owner        : process.env.KOVAN_OWNER_ACCOUNT,
            mnemonic     : process.env.KOVAN_WALLET_MNEMONIC,
            accountIndex : 2
        },
        mainnet: {
            owner        : process.env.MAINNET_OWNER_ACCOUNT,
            mnemonic     : process.env.MAINNET_WALLET_MNEMONIC,
            accountIndex : 2
        }
    },

    networkOptions: {
        local: {
            gas      : 6721975,
            gasPrice : 20e9
        },
        kovan: {
            // For contract deployments
            gas      : 6000000,             // https://kovan.etherscan.io/blocks
            // For contract interactions
            // gas      : 1000000,
            gasPrice : 20e9                 // https://kovan.etherscan.io/gastracker
        },
        mainnet: {
            // For contract deployments
            // gas     : 6500000,           // https://etherscan.io/blocks
            // For contract interactions
            gas      : 1000000,             // https://etherscan.io/blocks
            gasPrice : 21e9                 // https://etherscan.io/gastracker
        }
    }
};

config.wallets['kovan-fork'] = config.wallets['kovan'];
config.networkOptions['kovan-fork'] = config.networkOptions['kovan'];

module.exports = config;

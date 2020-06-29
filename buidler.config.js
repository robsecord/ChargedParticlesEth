const {TASK_COMPILE_GET_COMPILER_INPUT} = require('@nomiclabs/buidler/builtin-tasks/task-names');

task(TASK_COMPILE_GET_COMPILER_INPUT).setAction(async (_, __, runSuper) => {
    const input = await runSuper();
    input.settings.metadata.useLiteralContent = false;
    return input;
});

require('dotenv').config();

usePlugin('@nomiclabs/buidler-waffle');
usePlugin('@nomiclabs/buidler-etherscan');
usePlugin('buidler-gas-reporter');
usePlugin('solidity-coverage');
usePlugin('buidler-deploy');

const mnemonic = {
    proxyAdmin: {
        kovan:   `${process.env.KOVAN_PROXY_MNEMONIC}`.replace(/_/g, ' '),
        ropsten: `${process.env.ROPSTEN_PROXY_MNEMONIC}`.replace(/_/g, ' '),
        mainnet: `${process.env.MAINNET_PROXY_MNEMONIC}`.replace(/_/g, ' '),
    },
    owner: {
        kovan:   `${process.env.KOVAN_OWNER_MNEMONIC}`.replace(/_/g, ' '),
        ropsten: `${process.env.ROPSTEN_OWNER_MNEMONIC}`.replace(/_/g, ' '),
        mainnet: `${process.env.MAINNET_OWNER_MNEMONIC}`.replace(/_/g, ' '),
    }
};

module.exports = {
    solc: {
        version: '0.6.10',
        optimizer: {
            enabled: true,
            runs: 200
        },
        evmVersion: 'istanbul'
    },
    paths: {
        artifacts: './build',
        deploy: './deploy',
        deployments: './deployments'
    },
    networks: {
        buidlerevm: {
            blockGasLimit: 200000000,
            allowUnlimitedContractSize: true,
            gasPrice: 8e9
        },
        coverage: {
            url: 'http://127.0.0.1:8555',
            blockGasLimit: 200000000,
            allowUnlimitedContractSize: true
        },
        local: {
            url: 'http://127.0.0.1:8545',
            blockGasLimit: 200000000
        },
        kovan: {
            url: `https://kovan.infura.io/v3/${process.env.INFURA_API_KEY}`,
            gasPrice: 10e9,
            accounts: {
                mnemonic: mnemonic.owner.kovan,
                initialIndex: 0,
                count: 3,
            }
        },
        ropsten: {
            url: `https://ropsten.infura.io/v3/${process.env.INFURA_API_KEY}`,
            gasPrice: 10e9,
            accounts: {
                mnemonic: mnemonic.owner.ropsten,
                initialIndex: 0,
                count: 3,
            }
        }
    },
    gasReporter: {
        currency: 'USD',
        gasPrice: 1,
        enabled: (process.env.REPORT_GAS) ? true : false
    },
    namedAccounts: {
        deployer: {
            default: 0,
        },
        trustedForwarder: {
            default: 7, // Account 8
            1: '0x1337c0d31337c0D31337C0d31337c0d31337C0d3', // mainnet
            3: '0x1337c0d31337c0D31337C0d31337c0d31337C0d3', // ropsten
            42: '0x1337c0d31337c0D31337C0d31337c0d31337C0d3', // kovan
        },
        dai: {
            default: 0, // local; to be deployed by deployer
            1: '0x6B175474E89094C44Da98b954EedeAC495271d0F', // mainnet
            3: '0x31F42841c2db5173425b5223809CF3A38FEde360', // ropsten
            42: '0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa', // kovan
        }
    }
};

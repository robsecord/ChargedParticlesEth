const { ethers } = require('ethers')

const toWei = ethers.utils.parseEther
const toEth = ethers.utils.formatEther
const toStr = (val) => ethers.utils.toUtf8String(val).replace(/\0/g, '')

const txOverrides = (options = {}) => ({gas: 4000000, ...options})

const chainName = (chainId) => {
    switch (chainId) {
        case 1: return 'Mainnet'
        case 3: return 'Ropsten'
        case 42: return 'Kovan'
        case 31337: return 'BuidlerEVM'
        default: return 'Unknown'
    }
}

const presets = {
    ChargedParticles: {
        fees: {
            eth: toWei('0.001'),
            ion: toWei('1'),
        },
        ionToken: {
            URI: 'https://ipfs.io/ipfs/QmbNDYSzPUuEKa8ppv1W11fVJVZdGBUku2ZDKBqmUmyQdT',
            maxSupply: toWei('2000000'),
            mintFee: toWei('0.0001'),
            initialMint: toWei('20')
        }
    },
    EscrowManager: {
        fees: {
            deposit: 50, // 0.5%
        }
    }
}

const _getDeployedContract = async (bre, deployer, contractName, contractArgs = []) => {
    const {deployments} = bre
    const {deployIfDifferent, log} = deployments;
    const overrides = txOverrides({from: deployer})

    let contract = await deployments.getOrNull(contractName)
    if (!contract) {
        log(`  Deploying ${contractName}...`)
        const deployResult = await deployIfDifferent(['data'], contractName, overrides, contractName, ...contractArgs)
        contract = await deployments.get(contractName)
        if (deployResult.newlyDeployed) {
            log(`  - deployed at ${contract.address} for ${deployResult.receipt.gasUsed} WEI`)
        }
    }
    return contract
}

// Used in deployment initialization scripts and unit-tests
const contractManager = (bre) => async (contractName, contractArgs = []) => {
    const [ deployer ] = await bre.ethers.getSigners()

    //  Return an Ethers Contract instance with the "deployer" as Signer
    const contract = await _getDeployedContract(bre, deployer._address, contractName, contractArgs)
    return new bre.ethers.Contract(contract.address, contract.abi, deployer)
}

// Used in deployment scripts run by buidler-deploy
const contractDeployer = (contractName, contractArgs = []) => async (bre) => {
    const {getNamedAccounts} = bre
    const namedAccounts = await getNamedAccounts()
    return await _getDeployedContract(bre, namedAccounts.deployer, contractName, contractArgs)
}


module.exports = {
  txOverrides,
  chainName,
  contractDeployer,
  contractManager,
  presets,
  toWei,
  toEth,
  toStr,
}
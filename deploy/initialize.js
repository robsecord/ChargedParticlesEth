// using plugin: buidler-deploy
// reference: https://buidler.dev/plugins/buidler-deploy.html

const {
    contractManager,
    chainName,
    presets,
} = require('../js-utils/deploy-helpers')

module.exports = async (bre) => {
    const { ethers, getNamedAccounts, deployments } = bre
    const { log } = deployments
    const network = await ethers.provider.getNetwork()
    const _getDeployedContract = contractManager(bre)

    // Named accounts, defined in buidler.config.js:
    const { deployer, trustedForwarder, dai } = await getNamedAccounts()
  
    log("\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
    log("Charged Particles - Contract Initialization");
    log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n");
  
    // const signers = await ethers.getSigners()
    // log({signers})
  
    log("  Using Network: ", chainName(network.chainId))
    log("  Using Accounts:")
    log("  - Deployer:  ", deployer)
    log(" ")
  
    const ChaiEscrow                    = await _getDeployedContract('ChaiEscrow')
    const ChaiNucleus                   = await _getDeployedContract('ChaiNucleus')
    const ChargedParticles              = await _getDeployedContract('ChargedParticles')
    const ChargedParticlesEscrowManager = await _getDeployedContract('ChargedParticlesEscrowManager')
    const ChargedParticlesTokenManager  = await _getDeployedContract('ChargedParticlesTokenManager')
  
    let Dai = {address: dai}
    if (dai === deployer) {
        Dai = await _getDeployedContract('Dai')
    } else {
        log("\n  Using Dai at: ", dai)
    }

    log("\n  Initializing ChaiNucleus...")
    if (network.chainId === 1) {
        await ChaiNucleus.initMainnet()
    } else if (network.chainId === 3) {
        await ChaiNucleus.initRopsten()
    } else if (network.chainId === 42) {
        await ChaiNucleus.initKovan()
    }

    log("\n  Initializing ChaiEscrow...")
    await ChaiEscrow.initialize()
    log("  Initializing ChargedParticlesEscrowManager...")
    await ChargedParticlesEscrowManager.initialize()
    log("  Initializing ChargedParticlesTokenManager...")
    await ChargedParticlesTokenManager.initialize()
    log("  Initializing ChargedParticles...")
    await ChargedParticles.initialize()
  
    log("\n  Preparing ChaiEscrow...")
    await ChaiEscrow.setEscrowManager(ChargedParticlesEscrowManager.address)
    await ChaiEscrow.registerAssetPair(Dai.address, ChaiNucleus.address)
  
    log("  Preparing ChargedParticlesEscrowManager...")
    await ChargedParticlesEscrowManager.setDepositFee(presets.EscrowManager.fees.deposit)
    await ChargedParticlesEscrowManager.registerAssetPair("chai", ChaiEscrow.address)
  
    log("  Preparing ChargedParticlesTokenManager...")
    await ChargedParticlesTokenManager.setFusedParticleState(ChargedParticles.address, true)

    log("  Preparing ChargedParticles...")
    await ChargedParticles.setTrustedForwarder(trustedForwarder)
    await ChargedParticles.registerTokenManager(ChargedParticlesTokenManager.address)
    await ChargedParticles.registerEscrowManager(ChargedParticlesEscrowManager.address)
    await ChargedParticles.setupFees(presets.ChargedParticles.fees.eth, presets.ChargedParticles.fees.ion)

    log("\n  Enabling Contracts...")
    await ChaiEscrow.setPausedState(false)
    await ChargedParticles.setPausedState(false)

    // log("\n  Minting ION Tokens...")
    // const ionToken = presets.ChargedParticles.ionToken
    // await ChargedParticles.mintIons(ionToken.URI, ionToken.maxSupply, ionToken.mintFee)

    // Display Contract Addresses
    log("\n  Contract Deployments Complete!\n\n  Contracts:")
    log("  - ChaiEscrow:                    ", ChaiEscrow.address)
    log("  - ChaiNucleus:                   ", ChaiNucleus.address)
    log("  - ChargedParticles:              ", ChargedParticles.address)
    log("  - ChargedParticlesEscrowManager: ", ChargedParticlesEscrowManager.address)
    log("  - ChargedParticlesTokenManager:  ", ChargedParticlesTokenManager.address)
  
    log("\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n")
}
module.exports.runAtTheEnd = true;

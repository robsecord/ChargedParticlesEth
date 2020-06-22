const { ethers } = require('@nomiclabs/buidler');
const fs = require('fs');

require('dotenv').config();

const _deploymentsFile = `${__dirname}/../deployments.json`;

const _addDeployData = (deployData, contractName, contractInstance) => {
    const chainId = contractInstance.provider._network.chainId;
    deployData[chainId] = deployData[chainId] || {};
    deployData[chainId][contractName] = {
        txHash:     contractInstance.deployTransaction.hash,
        address:    contractInstance.address,
        chainId:    chainId,
        abi:        contractInstance.interface.abi,
    };
};

const _readDeploymentsFile = () => {
    let raw = fs.readFileSync(_deploymentsFile, {encoding: 'utf8', flag: 'a+'});
    raw = Buffer.from(raw).toString();
    if (!raw.length) { raw = '{}'; }
    return JSON.parse(raw);
};

const _writeDeploymentsFile = (deployData) => {
    fs.writeFileSync(_deploymentsFile, JSON.stringify(deployData, null, '\t'), {encoding: 'utf8', flag: 'w+'});
};

async function main() {
  // Get Contract Artifacts
  const ChaiEscrow = await ethers.getContractFactory('ChaiEscrow');
  const ChaiNucleus = await ethers.getContractFactory('ChaiNucleus');

  const ChargedParticles = await ethers.getContractFactory('ChargedParticles');
  const ChargedParticlesEscrowManager = await ethers.getContractFactory('ChargedParticlesEscrowManager');
  const ChargedParticlesTokenManager = await ethers.getContractFactory('ChargedParticlesTokenManager');

  console.log("\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
  console.log("Charged Particles - Contract Deploy Script");
  console.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n");

  // Deploy ChaiEscrow
  console.log("Deploying ChaiEscrow...");
  const chaiEscrow = await ChaiEscrow.deploy();
  await chaiEscrow.deployed();

  // Deploy ChaiNucleus
  console.log("Deploying ChaiNucleus...");
  const chaiNucleus = await ChaiNucleus.deploy();
  await chaiNucleus.deployed();

  // Deploy ChargedParticles
  console.log("Deploying ChargedParticles...");
  const chargedParticles = await ChargedParticles.deploy();
  await chargedParticles.deployed();

  // Deploy ChargedParticlesEscrowManager
  console.log("Deploying ChargedParticlesEscrowManager...");
  const chargedParticlesEscrowManager = await ChargedParticlesEscrowManager.deploy();
  await chargedParticlesEscrowManager.deployed();

  // Deploy ChargedParticlesTokenManager
  console.log("Deploying ChargedParticlesTokenManager...");
  const chargedParticlesTokenManager = await ChargedParticlesTokenManager.deploy();
  await chargedParticlesTokenManager.deployed();

  // Display Contract Addresses
  console.log("\nContract Deployments Complete!\nAdresses:\n");
  console.log("ChaiEscrow:                      ", chaiEscrow.address);
  console.log("ChaiNucleus:                     ", chaiNucleus.address);
  console.log("ChargedParticles:                ", chargedParticles.address);
  console.log("ChargedParticlesEscrowManager:   ", chargedParticlesEscrowManager.address);
  console.log("ChargedParticlesTokenManager:    ", chargedParticlesTokenManager.address);
  console.log("\n\n");

  // Output Deployments file preserving existing data
  let deployData = _readDeploymentsFile();
  _addDeployData(deployData, 'ChaiEscrow', chaiEscrow);
  _addDeployData(deployData, 'ChaiNucleus', chaiNucleus);
  _addDeployData(deployData, 'ChargedParticles', chargedParticles);
  _addDeployData(deployData, 'ChargedParticlesEscrowManager', chargedParticlesEscrowManager);
  _addDeployData(deployData, 'ChargedParticlesTokenManager', chargedParticlesTokenManager);
  _writeDeploymentsFile(deployData);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  });
  
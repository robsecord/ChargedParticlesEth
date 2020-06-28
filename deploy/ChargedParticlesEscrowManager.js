
const { contractDeployer } = require('../js-utils/deploy-helpers')
const contractName = 'ChargedParticlesEscrowManager';

module.exports = contractDeployer(contractName);
module.exports.tags = [contractName];

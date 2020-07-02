
const { contractDeployer } = require('../js-utils/deploy-helpers')
const contractName = 'ChargedParticlesTokenManager';

module.exports = contractDeployer(contractName);
module.exports.tags = [contractName];

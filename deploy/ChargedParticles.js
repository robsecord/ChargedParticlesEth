
const { contractDeployer } = require('../js-utils/deploy-helpers')
const contractName = 'ChargedParticles';

module.exports = contractDeployer(contractName);
module.exports.tags = [contractName];


const { contractDeployer } = require('../js-utils/deploy-helpers')
const contractName = 'ChaiEscrow';

module.exports = contractDeployer(contractName);
module.exports.tags = [contractName];

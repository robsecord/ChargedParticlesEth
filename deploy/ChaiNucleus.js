
const { contractDeployer } = require('../js-utils/deploy-helpers')
const contractName = 'ChaiNucleus';

module.exports = contractDeployer(contractName);
module.exports.tags = [contractName];

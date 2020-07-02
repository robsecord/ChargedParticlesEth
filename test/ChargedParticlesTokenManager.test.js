const {
    buidler,
    deployments,
    ethers,
    expect,
    EMPTY_STR,
    ZERO_ADDRESS,
} = require('./util/testEnv');

const {
    contractManager,
    toWei,
    toEth,
    toStr,
} = require('../js-utils/deploy-helpers');

const debug = require('debug')('ChargedParticlesTokenManager.test');

describe('ChargedParticlesTokenManager Contract', function () {
    let deployer;
    let primaryWallet;
    let secondaryWallet;

    let chargedParticlesTokenManager;

    const _getDeployedContract = contractManager(buidler);

    beforeEach(async () => {
        [deployer, primaryWallet, secondaryWallet] = await buidler.ethers.getSigners();

        await deployments.fixture();
        chargedParticlesTokenManager  = await _getDeployedContract('ChargedParticlesTokenManager');
    });

    it('maintains correct versioning', async () => {
        expect(toStr(await chargedParticlesTokenManager.version())).to.equal('v0.4.2');
    });

});

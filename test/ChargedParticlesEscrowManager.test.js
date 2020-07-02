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

const debug = require('debug')('ChargedParticlesEscrowManager.test');

describe('ChargedParticlesEscrowManager Contract', function () {
    let deployer;
    let primaryWallet;
    let secondaryWallet;

    let chargedParticlesEscrowManager;

    const _getDeployedContract = contractManager(buidler);

    beforeEach(async () => {
        [deployer, primaryWallet, secondaryWallet] = await buidler.ethers.getSigners();

        await deployments.fixture();
        chargedParticlesEscrowManager  = await _getDeployedContract('ChargedParticlesEscrowManager');
    });

    it('maintains correct versioning', async () => {
        expect(toStr(await chargedParticlesEscrowManager.version())).to.equal('v0.4.2');
    });

});

const {
    buidler,
    ethers,
    expect,
    deployContract,
    presets,
    toWei,
    toStr,
} = require('./util/testEnv');

const debug = require('debug')('ChargedParticlesEscrowManager.test');

const ChargedParticlesEscrowManager = require('../build/ChargedParticlesEscrowManager.json')


describe('ChargedParticles Contract', function () {
  let primaryWallet;
  let secondaryWallet;

  let escrowMgr;

  beforeEach(async () => {
    [primaryWallet, secondaryWallet] = await buidler.ethers.getSigners();

    debug('deploying ChargedParticlesEscrowManager...');
    escrowMgr = await deployContract(primaryWallet, ChargedParticlesEscrowManager, [], presets.txOverrides);

    debug('initializing ChargedParticlesEscrowManager...');
    await escrowMgr.initialize();
  });

  it('maintains correct versioning', async () => {
    expect(toStr(await escrowMgr.version())).to.equal('v0.4.1');
  });

});

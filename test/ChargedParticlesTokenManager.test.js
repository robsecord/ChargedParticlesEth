const {
    buidler,
    ethers,
    expect,
    deployContract,
    presets,
    toWei,
    toStr,
} = require('./util/testEnv');

const debug = require('debug')('ChargedParticlesTokenManager.test');

const ChargedParticlesTokenManager = require('../build/ChargedParticlesTokenManager.json')


describe('ChargedParticlesTokenManager Contract', function () {
  let primaryWallet;
  let secondaryWallet;

  let tokenMgr;

  beforeEach(async () => {
    [primaryWallet, secondaryWallet] = await buidler.ethers.getSigners();

    debug('deploying ChargedParticlesTokenManager...');
    tokenMgr = await deployContract(primaryWallet, ChargedParticlesTokenManager, [], presets.txOverrides);

    debug('initializing ChargedParticlesTokenManager...');
    await tokenMgr.initialize();
  });

  it('maintains correct versioning', async () => {
    expect(toStr(await tokenMgr.version())).to.equal('v0.4.1');
  });

});

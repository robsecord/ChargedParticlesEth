const { accounts, provider } = require('@openzeppelin/test-environment');
const { TestHelper } = require('@openzeppelin/cli');
const { Contracts, ZWeb3 } = require('@openzeppelin/upgrades');

ZWeb3.initialize(provider);
const { web3 } = ZWeb3;

const ChargedParticles = Contracts.getFromLocal('ChargedParticles');

describe('ChargedParticles', () => {
  let [owner] = accounts;
  let contractInstance;
  let helper;

  beforeEach(async () => {
    helper = await TestHelper();
  });

  test('initializer', async () => {
    contractInstance = await helper.createProxy(ChargedParticles, { initMethod: 'initialize', initArgs: [owner] });
    const version = await contractInstance.methods.version().call({ from: owner });
    expect(web3.utils.hexToAscii(version)).toMatch("v0.3.5");
  });
});

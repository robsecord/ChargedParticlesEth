const { accounts, provider } = require('@openzeppelin/test-environment');
const { TestHelper } = require('@openzeppelin/cli');
const { expectRevert } = require('@openzeppelin/test-helpers');
const { Contracts, ZWeb3 } = require('@openzeppelin/upgrades');

ZWeb3.initialize(provider);
const { web3 } = ZWeb3;

const ChargedParticles = Contracts.getFromLocal('ChargedParticles');

describe('ChargedParticles', () => {
  let [owner, nonOwner] = accounts;
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

  describe('only Admin/DAO', () => {
    beforeEach(async () => {
      contractInstance = await helper.createProxy(ChargedParticles, { initMethod: 'initialize', initArgs: [owner] });
    });

    test('setupFees', async () => {
      const toWei = (amnt) => web3.utils.toWei(amnt, 'ether');
      const fromWei = (amnt) => web3.utils.fromWei(amnt, 'ether');

      await expectRevert(
        contractInstance.methods.setupFees(toWei('0.5'), toWei('0.3')).send({ from: nonOwner }),
        "Ownable: caller is not the owner"
      );
      await contractInstance.methods.setupFees(toWei('0.5'), toWei('0.3')).send({ from: owner });
      
      const { 0: createFeeEth, 1: createFeeIon } = await contractInstance.methods.getCreationPrice(false).call({ from: owner });
      expect(fromWei(createFeeEth)).toBe('0.5');
      expect(fromWei(createFeeIon)).toBe('0.3');
      
      const { 0: createFeeEthForNFT, 1: createFeeIonForNFT } = await contractInstance.methods.getCreationPrice(true).call({ from: owner });
      expect(fromWei(createFeeEthForNFT)).toBe("1");
      expect(fromWei(createFeeIonForNFT)).toBe("0.6");
    });
  });
});

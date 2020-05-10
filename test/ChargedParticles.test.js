const { accounts, provider } = require('@openzeppelin/test-environment');
const { TestHelper } = require('@openzeppelin/cli');
const { constants, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');
const { Contracts, ZWeb3 } = require('@openzeppelin/upgrades');

ZWeb3.initialize(provider);
const { web3 } = ZWeb3;

const ChargedParticles = Contracts.getFromLocal('ChargedParticles');
const ChargedParticlesERC1155 = Contracts.getFromLocal('ChargedParticlesERC1155');

describe('ChargedParticles', () => {
  let [owner, nonOwner, ionHodler] = accounts;
  let contractInstance;
  let tokenManagerInstance;
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

    test('setPausedState', async () => {
      let isPaused = await contractInstance.methods.isPaused().call({ from: nonOwner });
      expect(isPaused).toBe(false);

      await expectRevert(
        contractInstance.methods.setPausedState(false).send({ from: nonOwner }),
        "Ownable: caller is not the owner"
      );

      await contractInstance.methods.setPausedState(true).send({ from: owner });

      isPaused = await contractInstance.methods.isPaused().call({ from: nonOwner });
      expect(isPaused).toBe(true);

      await contractInstance.methods.setPausedState(false).send({ from: owner });

      isPaused = await contractInstance.methods.isPaused().call({ from: owner });
      expect(isPaused).toBe(false);
    });
  });

  describe('with Token manager', () => {
    beforeEach(async () => {
      contractInstance = await helper.createProxy(ChargedParticles, { initMethod: 'initialize', initArgs: [owner] });
      tokenManagerInstance = await helper.createProxy(ChargedParticlesERC1155, { initMethod: 'initialize', initArgs: [owner] });
    });

    test('registerTokenManager', async () => {
      await expectRevert(
        contractInstance.methods.registerTokenManager(tokenManagerInstance.address).send({ from: nonOwner }),
        "Ownable: caller is not the owner"
      );
      
      await expectRevert(
        contractInstance.methods.registerTokenManager(constants.ZERO_ADDRESS).send({ from: owner }),
        "E412"
      );
    });

    test('mintIons', async () => {
      const mintFee = web3.utils.toWei('1', 'ether')

      await contractInstance.methods.registerTokenManager(tokenManagerInstance.address).send({ from: owner });
      await tokenManagerInstance.methods.setChargedParticles(contractInstance.address).send({ from: owner });
      await expectRevert(
        contractInstance.methods.mintIons('https://www.example.com', 1337, 42, mintFee).send({ from: nonOwner }),
        "Ownable: caller is not the owner"
      );
      await expectRevert(
        contractInstance.methods.mintIons('', 1337, 42, mintFee).send({ from: owner }),
        "E107"
      );

      const receipt = await contractInstance.methods.mintIons('https://www.example.com', 1337, 42, mintFee).send({ from: owner, gas: 5e6 });
      expectEvent(receipt, 'PlasmaTypeUpdated', {
        _symbol: web3.utils.keccak256('ION'),
        _isPrivate: false,
        _initialMint: '42',
        _uri: 'https://www.example.com'
      });

      await expectRevert(
        contractInstance.methods.mintIons('https://www.example.com', 1337, 42, mintFee).send({ from: owner }),
        "E416"
      );
    });

    describe('Public Read of Ion token', () => {
      let ionTokenId;

      beforeEach(async () => {
        await contractInstance.methods.registerTokenManager(tokenManagerInstance.address).send({ from: owner });
        await tokenManagerInstance.methods.setChargedParticles(contractInstance.address).send({ from: owner });
        const receipt = await contractInstance.methods.mintIons(
          'https://www.example.com',
          1337,
          42,
          web3.utils.toWei('1', 'ether')
        ).send({ from: owner, gas: 5e6 });
        ionTokenId = receipt.events['PlasmaTypeUpdated'].returnValues['_plasmaTypeId'];
      });

      test('uri', async () => {
        const uri = await contractInstance.methods.uri(ionTokenId).call({ from: nonOwner });
        expect(uri).toBe('https://www.example.com');
      });

      test('getTypeCreator', async () => {
        const typeCreator = await contractInstance.methods.getTypeCreator(ionTokenId).call({ from: nonOwner });
        expect(typeCreator).toBe(owner);
      });

      test('getTypeTokenBridge', async () => {
        const bridgeAddress = await contractInstance.methods.getTypeTokenBridge(ionTokenId).call({ from: nonOwner });
        expect(bridgeAddress).not.toBe(owner);
        expect(bridgeAddress).not.toBe(nonOwner);
        expect(bridgeAddress).not.toBe(ionHodler);
        expect(bridgeAddress).not.toBe(contractInstance.address);
        expect(bridgeAddress).not.toBe(tokenManagerInstance.address);
      });

      test('canMint', async () => {
        let canMint = await contractInstance.methods.canMint(ionTokenId, 1).call({ from: nonOwner });
        expect(canMint).toBe(true);
        canMint = await contractInstance.methods.canMint(ionTokenId, 2000).call({ from: nonOwner });
        expect(canMint).toBe(false);
      });

      test('getSeriesNumber', async () => {
        const seriesNumber = await contractInstance.methods.getSeriesNumber(ionTokenId).call({ from: nonOwner });
        expect(seriesNumber).toBe('0');
      });

      test('getMintingFee', async () => {
        const mintFee = await contractInstance.methods.getMintingFee(ionTokenId).call({ from: nonOwner });
        expect(web3.utils.fromWei(mintFee, 'ether')).toBe('1');
      });

      test('getMaxSupply', async () => {
        const maxSupply = await contractInstance.methods.getMaxSupply(ionTokenId).call({ from: nonOwner });
        expect(maxSupply).toBe('1337');
      });

      test('getTotalMinted', async () => {
        const totalMinted = await contractInstance.methods.getTotalMinted(ionTokenId).call({ from: nonOwner });
        expect(totalMinted).toBe('42');
      });
    });

    describe('Operations on Ion token', () => {
      let ionTokenId;

      beforeEach(async () => {
        await contractInstance.methods.registerTokenManager(tokenManagerInstance.address).send({ from: owner });
        await tokenManagerInstance.methods.setChargedParticles(contractInstance.address).send({ from: owner });
        const receipt = await contractInstance.methods.mintIons(
          'https://www.example.com',
          1337,
          42,
          web3.utils.toWei('1', 'ether')
        ).send({ from: owner, gas: 5e6 });
        ionTokenId = receipt.events['PlasmaTypeUpdated'].returnValues['_plasmaTypeId'];
      });

      test('mintParticle', async () => {
        await contractInstance.methods.setPausedState(true).send({ from: owner });
        await expectRevert(
          contractInstance.methods.mintParticle(ionHodler, ionTokenId, 10, '', []).send({ from: owner }),
          "E417"
        );
        await contractInstance.methods.setPausedState(false).send({ from: owner });

        await expectRevert(
          contractInstance.methods.mintParticle(ionHodler, ionTokenId, 10, '', []).send({ from: owner }),
          "E104"
        );
      });

      test('burnParticle', async () => {
        expectRevert(
          contractInstance.methods.burnParticle(ionTokenId).send({ from: owner }),
          "E104"
        );
      });

      test('energizeParticle', async () => {
        expectRevert(
          contractInstance.methods.energizeParticle(ionTokenId, 10).send({ from: owner }),
          "E104"
        );
      });

      test('mintPlasma from creator', async () => {
        await contractInstance.methods.setPausedState(true).send({ from: owner });
        await expectRevert(
          contractInstance.methods.mintPlasma(ionHodler, ionTokenId, 10, []).send({ from: owner }),
          "E417"
        );
        await contractInstance.methods.setPausedState(false).send({ from: owner });

        // Mint amount exceends limit
        await expectRevert(
          contractInstance.methods.mintPlasma(ionHodler, ionTokenId, 9999, []).send({ from: owner }),
          "E407"
        );

        const receipt = await contractInstance.methods.mintPlasma(ionHodler, ionTokenId, 3, []).send({ from: owner, gas: 5e6 });
        expectEvent(receipt, 'PlasmaMinted', {
          _sender: owner,
          _receiver: ionHodler,
          _typeId: ionTokenId,
          _amount: '3'
        });
        expect(await tokenManagerInstance.methods.balanceOf(ionHodler, ionTokenId).call()).toBe('3');
      });

      test('mintPlasma from non-creator', async () => {
        // Mint amount exceends limit
        await expectRevert(
          contractInstance.methods.mintPlasma(ionHodler, ionTokenId, 9999, []).send({ from: nonOwner }),
          "E407"
        );

        // Not including the minting fee with the transaction
        await expectRevert(
          contractInstance.methods.mintPlasma(ionHodler, ionTokenId, 10, []).send({ from: nonOwner, gas: 5e6 }),
          "E404"
        );

        const receipt = await contractInstance.methods
          .mintPlasma(ionHodler, ionTokenId, 3, [])
          .send({ from: nonOwner, gas: 5e6, value: web3.utils.toWei('5', 'ether') });

        expectEvent(receipt, 'PlasmaMinted', {
          _sender: nonOwner,
          _receiver: ionHodler,
          _typeId: ionTokenId,
          _amount: '3'
        });

        const balance = await tokenManagerInstance.methods.balanceOf(ionHodler, ionTokenId).call({ from: ionHodler });
        expect(balance).toBe('3');
      });

      test('withdrawFees', async () => {
        await contractInstance.methods.mintPlasma(ionHodler, ionTokenId, 3, []).send({ from: nonOwner, gas: 5e6, value: web3.utils.toWei('5', 'ether') });

        expectRevert(
          contractInstance.methods.withdrawFees(ionHodler).send({ from: nonOwner, gas: 5e6 }),
          "Ownable: caller is not the owner"
        );

        expectRevert(
          contractInstance.methods.withdrawFees('0x0000000000000000000000000000000000000000').send({ from: owner, gas: 5e6 }),
          "E412"
        );

        const balanceBefore = await web3.eth.getBalance(ionHodler);
        const receipt = await contractInstance.methods.withdrawFees(ionHodler).send({ from: owner, gas: 5e6 });
        const balanceAfter = await web3.eth.getBalance(ionHodler);

        expectEvent(receipt, 'ContractFeesWithdrawn', {
          _sender: owner,
          _receiver: ionHodler,
          _amount: web3.utils.toWei('3', 'ether').toString()
        });
        expect(web3.utils.fromWei((balanceAfter - balanceBefore).toString(), 'ether')).toBe('3');
      });

      test('burnPlasma', async () => {
        expectRevert(
          contractInstance.methods.burnPlasma(ionTokenId, 10).send({ from: nonOwner }),
          "E106"
        );

        const receipt = await contractInstance.methods.burnPlasma(ionTokenId, 10).send({ from: owner });
  
        expectEvent(receipt, 'PlasmaBurned', {
          _from: owner,
          _typeId: ionTokenId,
          _amount: '10'
        });

        const balance = await tokenManagerInstance.methods.balanceOf(owner, ionTokenId).call({ from: owner });
        expect(balance).toBe('32');
      });
    });
  });
});

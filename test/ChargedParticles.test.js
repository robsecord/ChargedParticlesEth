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

const debug = require('debug')('ChargedParticles.test');


describe('ChargedParticles Contract', function () {
    let deployer;
    let primaryWallet;
    let secondaryWallet;

    let chargedParticles;
    let chargedParticlesTokenManager;
    let chargedParticlesEscrowManager;
    let dai;

    const _getDeployedContract = contractManager(buidler);

    describe("before minting ions", () => {

        const { presets } = require('../js-utils/deploy-helpers');
        const ion = presets.ChargedParticles.ionToken;
        
        beforeEach(async () => {
            [deployer, primaryWallet, secondaryWallet] = await buidler.ethers.getSigners();
            await deployments.fixture();
            chargedParticles              = await _getDeployedContract('ChargedParticles');
            chargedParticlesTokenManager  = await _getDeployedContract('ChargedParticlesTokenManager');
            chargedParticlesEscrowManager = await _getDeployedContract('ChargedParticlesEscrowManager');
        });

        it('should maintain correct versioning', async () => {
            expect(toStr(await chargedParticles.version())).to.equal('v0.4.2');
        });

        it('should only allow modifications from Role: Admin/DAO', async () => {
            const ethFee = toWei('1');
            const ionFee = toWei('2');

            // Test Non-Admin
            await expect(chargedParticles.connect(secondaryWallet).setupFees(ethFee, ionFee))
                .to.be.revertedWith('CP: INVALID_DAO');

            // Test Admin
            await chargedParticles.setupFees(ethFee, ionFee);

            const { 0: createFeeEth, 1: createFeeIon } = await chargedParticles.getCreationPrice(false);
            debug({createFeeEth, createFeeIon});
            expect(createFeeEth).to.equal(ethFee);
            expect(createFeeIon).to.equal(ionFee);

            const { 0: createFeeEthForNFT, 1: createFeeIonForNFT } = await chargedParticles.getCreationPrice(true);
            debug({createFeeEthForNFT, createFeeIonForNFT});
            expect(createFeeEthForNFT).to.equal(ethFee.mul(2));
            expect(createFeeIonForNFT).to.equal(ionFee.mul(2));
        });

        it('should only allow modifications from Role: Maintainer', async () => {
            let isPaused = await chargedParticles.connect(secondaryWallet).isPaused();
            expect(isPaused).to.equal(false);

            // Test Non-Admin
            await expect(chargedParticles.connect(secondaryWallet).setPausedState(false))
                .to.be.revertedWith('CP: INVALID_MAINTAINER');

            // Test Admin - Toggle True
            await chargedParticles.setPausedState(true);

            isPaused = await chargedParticles.connect(secondaryWallet).isPaused();
            expect(isPaused).to.equal(true);

            // Test Admin - Toggle False
            await chargedParticles.setPausedState(false);

            isPaused = await chargedParticles.isPaused();
            expect(isPaused).to.equal(false);
        });

        it('should allow the Admin/DAO to assign a Valid Token Manager', async () => {
            await expect(chargedParticles.connect(secondaryWallet).registerTokenManager(chargedParticlesTokenManager.address))
                .to.be.revertedWith('CP: INVALID_DAO');

            await expect(chargedParticles.registerTokenManager(ZERO_ADDRESS))
                .to.be.revertedWith('CP: INVALID_ADDRESS');

            await chargedParticles.registerTokenManager(chargedParticlesTokenManager.address);
            expect(await chargedParticles.tokenMgr()).to.equal(chargedParticlesTokenManager.address);
        });

        it('should only allow Admin/DAO to Mint IONs one time', async () => {

            //  Test Non-Admin/DAO
            await expect(chargedParticles.connect(secondaryWallet).mintIons(ion.URI, ion.maxSupply, ion.mintFee, ion.initialMint))
                .to.be.revertedWith('CP: INVALID_DAO');

            // Test Mint
            chargedParticles.on("PlasmaTypeUpdated", (_plasmaTypeId, _symbol, _isPrivate, _initialMint, _uri, event) => {
                expect(_symbol).to.equal(web3.utils.keccak256('ION'));
                expect(_isPrivate).to.equal(false);
                expect(_initialMint).to.equal(ion.initialMint);
                expect(_uri).to.equal(ion.uri);
            });

            await chargedParticles.mintIons(ion.URI, ion.maxSupply, ion.mintFee, ion.initialMint);

            await expect(chargedParticles.mintIons(ion.URI, ion.maxSupply, ion.mintFee, ion.initialMint)).to.be.revertedWith("CP: ALREADY_INIT");
        });

        describe("after minting ions", () => {

            let assetAmount = toWei('10');

            const particle = {
                name: "test-partcile",
                uri: "https://example.com",
                symbol: "TCH",
                accessType: 0,
                assetPair: "chai",
                maxSupply: toWei('20000'),
                mintFee: toWei('0.0001'),
                payWithIons: true
            }

            beforeEach(async () => {
                const ionTokenId = await chargedParticles.callStatic.mintIons(ion.URI, ion.maxSupply, ion.mintFee, ion.maxSupply);
                await chargedParticles.mintIons(ion.URI, ion.maxSupply, ion.mintFee, ion.maxSupply);
            });

            it('should not be able to create particle with ions when having insufficient balance', async () => {
                await expect(chargedParticles.connect(secondaryWallet).createParticle(
                    particle.name,
                    particle.uri,
                    particle.symbol,
                    particle.accessType,
                    particle.assetPair,
                    particle.maxSupply,
                    particle.mintFee,
                    particle.payWithIons
                )).to.be.revertedWith('E1155: INSUFF_BALANCE');
            });

            describe("after creating particle", () => {

                let particleTypeId;

                beforeEach(async () => {
                    particleTypeId = await chargedParticles.callStatic.createParticle(
                        particle.name,
                        particle.uri,
                        particle.symbol,
                        particle.accessType,
                        particle.assetPair,
                        particle.maxSupply,
                        particle.mintFee,
                        particle.payWithIons
                    );
                    await chargedParticles.createParticle(
                        particle.name,
                        particle.uri,
                        particle.symbol,
                        particle.accessType,
                        particle.assetPair,
                        particle.maxSupply,
                        particle.mintFee,
                        particle.payWithIons
                    );
                });

                it('cannot mint particles if having insufficient funds', async () => {

                    const dai = await _getDeployedContract('Dai');
                    await dai.mint(deployer.getAddress(), toWei('100'));
                    await dai.approve(chargedParticles.address, toWei('100'));

                    // await expect(chargedParticles.mintParticle(
                    //     primaryWallet.getAddress(),
                    //     particleTypeId,
                    //     toWei('100'),
                    //     "https://example.com",
                    //     ethers.utils.formatBytes32String("some quirky data")
                    // )).to.be.revertedWith('CP: INSUFF_FUNDS');

                    // const tokenId = await chargedParticles.callStatic.mintParticle(
                    //     orimaryWallet.getAddress(),
                    //     particleTypeId,
                    //     toWei('100'),
                    //     "https://example.com",
                    //     ethers.utils.formatBytes32String("some quirky data"),
                    //     { value: toWei('0.0001') }
                    // );

                    // chargedParticles.on('ParticleMinted', (_sender, _receiver, _tokenId, _uri, event) => {
                    //     expect(_tokenId).to.equal(tokenId);
                    // })

                    // await chargedParticles.mintParticle(
                    //     primaryWallet.getAddress(),
                    //     particleTypeId,
                    //     toWei('100'),
                    //     "https://example.com",
                    //     ethers.utils.formatBytes32String("some quirky data"),
                    //     { value: toWei('0.0001') }
                    // );

                });

            });

        });

    });

});

// describe('ChargedParticles', () => {
//   let [owner, nonOwner, ionHodler] = accounts;
//   let chargedParticles;
//   let tokenManagerInstance;
//   let helper;

//   beforeEach(async () => {
//     helper = await TestHelper();
//   });

//   it('initializer', async () => {
//     debug('initializer');
//     // chargedParticles = await helper.createProxy(ChargedParticles, { initMethod: 'initialize' });
//     chargedParticles = await ChargedParticles.new();
//     debug({chargedParticles});
//     const version = await chargedParticles.version({ from: owner });
//     debug({version});
//     expect(web3.utils.hexToAscii(version)).toMatch("v0.4.2");
//   });


//   describe('with Token manager', () => {
//     beforeEach(async () => {
//       chargedParticles = await helper.createProxy(ChargedParticles, { initMethod: 'initialize', initArgs: [owner] });
//       tokenManagerInstance = await helper.createProxy(ChargedParticlesTokenManager, { initMethod: 'initialize', initArgs: [owner] });
//     });

//     it('registerTokenManager', async () => {
//       await expectRevert(
//         chargedParticles.registerTokenManager(tokenManagerInstance.address).send({ from: nonOwner }),
//         "Ownable: caller is not the owner"
//       );
      
//       await expectRevert(
//         chargedParticles.registerTokenManager(constants.ZERO_ADDRESS).send({ from: owner }),
//         "E412"
//       );
//     });

//     it('mintIons', async () => {
//       const mintFee = web3.utils.toWei('1', 'ether')

//       await chargedParticles.registerTokenManager(tokenManagerInstance.address).send({ from: owner });
//       await tokenManagerInstance.methods.setFusedParticleState(chargedParticles.address, true).send({ from: owner });
//       await expectRevert(
//         chargedParticles.mintIons('https://www.example.com', 1337, 42, mintFee).send({ from: nonOwner }),
//         "Ownable: caller is not the owner"
//       );
//       await expectRevert(
//         chargedParticles.mintIons('', 1337, 42, mintFee).send({ from: owner }),
//         "E107"
//       );

//       const receipt = await chargedParticles.mintIons('https://www.example.com', 1337, 42, mintFee).send({ from: owner, gas: 5e6 });
//       expectEvent(receipt, 'PlasmaTypeUpdated', {
//         _symbol: web3.utils.keccak256('ION'),
//         _isPrivate: false,
//         _initialMint: '42',
//         _uri: 'https://www.example.com'
//       });

//       await expectRevert(
//         chargedParticles.mintIons('https://www.example.com', 1337, 42, mintFee).send({ from: owner }),
//         "E416"
//       );
//     });

//     describe('Public Read of Ion token', () => {
//       let ionTokenId;

//       beforeEach(async () => {
//         await chargedParticles.registerTokenManager(tokenManagerInstance.address).send({ from: owner });
//         await tokenManagerInstance.methods.setFusedParticleState(chargedParticles.address, true).send({ from: owner });
//         const receipt = await chargedParticles.mintIons(
//           'https://www.example.com',
//           1337,
//           42,
//           web3.utils.toWei('1', 'ether')
//         ).send({ from: owner, gas: 5e6 });
//         ionTokenId = receipt.events['PlasmaTypeUpdated'].returnValues['_plasmaTypeId'];
//       });

//       it('uri', async () => {
//         const uri = await chargedParticles.uri(ionTokenId).call({ from: nonOwner });
//         expect(uri).to.equal('https://www.example.com');
//       });

//       it('getTypeCreator', async () => {
//         const typeCreator = await chargedParticles.getTypeCreator(ionTokenId).call({ from: nonOwner });
//         expect(typeCreator).to.equal(owner);
//       });

//       it('getTypeTokenBridge', async () => {
//         const bridgeAddress = await chargedParticles.getTypeTokenBridge(ionTokenId).call({ from: nonOwner });
//         expect(bridgeAddress).not.to.equal(owner);
//         expect(bridgeAddress).not.to.equal(nonOwner);
//         expect(bridgeAddress).not.to.equal(ionHodler);
//         expect(bridgeAddress).not.to.equal(chargedParticles.address);
//         expect(bridgeAddress).not.to.equal(tokenManagerInstance.address);
//       });

//       it('canMint', async () => {
//         let canMint = await chargedParticles.canMint(ionTokenId, 1).call({ from: nonOwner });
//         expect(canMint).to.equal(true);
//         canMint = await chargedParticles.canMint(ionTokenId, 2000).call({ from: nonOwner });
//         expect(canMint).to.equal(false);
//       });

//       it('getSeriesNumber', async () => {
//         const seriesNumber = await chargedParticles.getSeriesNumber(ionTokenId).call({ from: nonOwner });
//         expect(seriesNumber).to.equal('0');
//       });

//       it('getMintingFee', async () => {
//         const mintFee = await chargedParticles.getMintingFee(ionTokenId).call({ from: nonOwner });
//         expect(web3.utils.fromWei(mintFee, 'ether')).to.equal('1');
//       });

//       it('getMaxSupply', async () => {
//         const maxSupply = await chargedParticles.getMaxSupply(ionTokenId).call({ from: nonOwner });
//         expect(maxSupply).to.equal('1337');
//       });

//       it('getTotalMinted', async () => {
//         const totalMinted = await chargedParticles.getTotalMinted(ionTokenId).call({ from: nonOwner });
//         expect(totalMinted).to.equal('42');
//       });
//     });

//     describe('Operations on Ion token', () => {
//       let ionTokenId;

//       beforeEach(async () => {
//         await chargedParticles.registerTokenManager(tokenManagerInstance.address).send({ from: owner });
//         await tokenManagerInstance.methods.setFusedParticleState(chargedParticles.address, true).send({ from: owner });
//         const receipt = await chargedParticles.mintIons(
//           'https://www.example.com',
//           1337,
//           42,
//           web3.utils.toWei('1', 'ether')
//         ).send({ from: owner, gas: 5e6 });
//         ionTokenId = receipt.events['PlasmaTypeUpdated'].returnValues['_plasmaTypeId'];
//       });

//       it('mintParticle', async () => {
//         await chargedParticles.setPausedState(true).send({ from: owner });
//         await expectRevert(
//           chargedParticles.mintParticle(ionHodler, ionTokenId, 10, '', []).send({ from: owner }),
//           "E417"
//         );
//         await chargedParticles.setPausedState(false).send({ from: owner });

//         await expectRevert(
//           chargedParticles.mintParticle(ionHodler, ionTokenId, 10, '', []).send({ from: owner }),
//           "E104"
//         );
//       });

//       it('burnParticle', async () => {
//         expectRevert(
//           chargedParticles.burnParticle(ionTokenId).send({ from: owner }),
//           "E104"
//         );
//       });

//       it('energizeParticle', async () => {
//         expectRevert(
//           chargedParticles.energizeParticle(ionTokenId, 10).send({ from: owner }),
//           "E104"
//         );
//       });

//       it('mintPlasma from creator', async () => {
//         await chargedParticles.setPausedState(true).send({ from: owner });
//         await expectRevert(
//           chargedParticles.mintPlasma(ionHodler, ionTokenId, 10, []).send({ from: owner }),
//           "E417"
//         );
//         await chargedParticles.setPausedState(false).send({ from: owner });

//         // Mint amount exceends limit
//         await expectRevert(
//           chargedParticles.mintPlasma(ionHodler, ionTokenId, 9999, []).send({ from: owner }),
//           "E407"
//         );

//         const receipt = await chargedParticles.mintPlasma(ionHodler, ionTokenId, 3, []).send({ from: owner, gas: 5e6 });
//         expectEvent(receipt, 'PlasmaMinted', {
//           _sender: owner,
//           _receiver: ionHodler,
//           _typeId: ionTokenId,
//           _amount: '3'
//         });
//         expect(await tokenManagerInstance.methods.balanceOf(ionHodler, ionTokenId).call()).to.equal('3');
//       });

//       it('mintPlasma from non-creator', async () => {
//         // Mint amount exceends limit
//         await expectRevert(
//           chargedParticles.mintPlasma(ionHodler, ionTokenId, 9999, []).send({ from: nonOwner }),
//           "E407"
//         );

//         // Not including the minting fee with the transaction
//         await expectRevert(
//           chargedParticles.mintPlasma(ionHodler, ionTokenId, 10, []).send({ from: nonOwner, gas: 5e6 }),
//           "E404"
//         );

//         const receipt = await chargedParticles
//           .mintPlasma(ionHodler, ionTokenId, 3, [])
//           .send({ from: nonOwner, gas: 5e6, value: web3.utils.toWei('5', 'ether') });

//         expectEvent(receipt, 'PlasmaMinted', {
//           _sender: nonOwner,
//           _receiver: ionHodler,
//           _typeId: ionTokenId,
//           _amount: '3'
//         });

//         const balance = await tokenManagerInstance.methods.balanceOf(ionHodler, ionTokenId).call({ from: ionHodler });
//         expect(balance).to.equal('3');
//       });

//       it('withdrawFees', async () => {
//         await chargedParticles.mintPlasma(ionHodler, ionTokenId, 3, []).send({ from: nonOwner, gas: 5e6, value: web3.utils.toWei('5', 'ether') });

//         expectRevert(
//           chargedParticles.withdrawFees(ionHodler).send({ from: nonOwner, gas: 5e6 }),
//           "Ownable: caller is not the owner"
//         );

//         expectRevert(
//           chargedParticles.withdrawFees('0x0000000000000000000000000000000000000000').send({ from: owner, gas: 5e6 }),
//           "E412"
//         );

//         const balanceBefore = await web3.eth.getBalance(ionHodler);
//         const receipt = await chargedParticles.withdrawFees(ionHodler).send({ from: owner, gas: 5e6 });
//         const balanceAfter = await web3.eth.getBalance(ionHodler);

//         expectEvent(receipt, 'ContractFeesWithdrawn', {
//           _sender: owner,
//           _receiver: ionHodler,
//           _amount: web3.utils.toWei('3', 'ether').toString()
//         });
//         expect(web3.utils.fromWei((balanceAfter - balanceBefore).toString(), 'ether')).to.equal('3');
//       });

//       it('burnPlasma', async () => {
//         expectRevert(
//           chargedParticles.burnPlasma(ionTokenId, 10).send({ from: nonOwner }),
//           "E106"
//         );

//         const receipt = await chargedParticles.burnPlasma(ionTokenId, 10).send({ from: owner });
  
//         expectEvent(receipt, 'PlasmaBurned', {
//           _from: owner,
//           _typeId: ionTokenId,
//           _amount: '10'
//         });

//         const balance = await tokenManagerInstance.methods.balanceOf(owner, ionTokenId).call({ from: owner });
//         expect(balance).to.equal('32');
//       });
//     });
//   });
// });

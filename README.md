## Charged Particles - Solidity Contracts v0.2.0

**Charged Particles** are Non-Fungible Tokens (NFTs) that are minted with **DAI** and accrue interest via **CHAI** 
giving the Token a "Charge". 

#### Pre-production Site
https://charged-particles.netlify.com/

#### Staging Site
https://charged-particles-stage.netlify.com/


#### Value
```text
Particle Value
  =
Intrinsic Value (underlying asset, DAI)
  + 
Speculative Value (non-fungible rarity)
  +
Interest value (accrued in CHAI)
```

#### Value Appreciation
Imagine a Babe Ruth rookie card that was stuffed with $1 and earning interest since 1916!  The same might be true
of a Charged Particle NFT in 100 years!

#### Ownership
Charged Particles are non-custodial NFTs that can be "discharged" at any time by the owner, collecting the interest 
from the token. And just like any NFT, they are yours trade, transfer, sell, etc.

They can also be burned (melted) to reclaim the underlying DAI + interest in full, destroying the token.
Charged Particles, therefore, always have an underlying value in DAI. 

#### Custom Mechanics
Based on the amount of "charge" a token has, Smart Contracts and/or Dapps can decide how to handle the token - custom 
mechanics can be designed around the level of "Charge" a token has.

Imagine an NFT that represents a Sword - the power of that sword could be dependant on the amount of "Charge" the token 
has. Or perhaps certain items can only be used once they reach a certain level of charge.

Other possibilities include battling over the "charge" of a particle - the winner earns the interest from their 
competitor's particles.  (Still trying to work this part out, ideas are welcome!)

#### Token Flavours
Charged Particles currently come in 2 flavours: 
 - **ERC-721** - based on **openzeppelin-solidity v2.4.0** 
 - **ERC-1155** - based on **multi-token-standard v0.8.9**

Potential 3rd-flavour being researched: **ERC-998** for composable particles that can wrap existing NFTs, enabling 
them to generate a charge too! Thanks to James McCall @mccallios for contributing to the idea!

Also being researched; Zapped NFTs (combining NFTs with DeFiZaps)

#### Particle Accelerator
 - Fully-decentralized Public Particle Minting Station
 - Work-in-progress 
 - Repo: https://github.com/robsecord/ChargedParticlesWeb
 - Stage Site: https://charged-particles-stage.netlify.com/

#### Feedback & Contributions
Feel free to fork and/or use in your own projects!

And, of course, contributions are always welcome!

#### Community
Join our community, share ideas and help support the project in anyway you want!

**Discord**: https://discord.gg/Syh3gjz

### Frameworks/Software used:
 - Main Repo:
    - OpenZeppelin CLI **v2.6.0**
    - OpenZeppelin Ethereum Contracts **v2.4.0**
    - OpenZeppelin Upgrades **v2.6.0**
 - Variations folder:
    - Truffle **v5.1.11** (core: 5.1.11)
    - Ganache **2.1.0**
    - OpenZeppelin Solidity Contracts **v2.4.0**
 - Both:
    - Solidity  **v0.5.13** (solc-js)
    - NodeJS **v12.14.1**
    - Web3.js **v1.2.1**

### Prepare environment:
    
 Create a local .env file with the following (replace ... with your keys):
 
```bash
    INFURA_API_KEY="__api_key_only_no_url__"
    
    KOVAN_PROXY_ADDRESS="__public_address__"
    KOVAN_PROXY_MNEMONIC="__12-word_mnemonic__"
    
    KOVAN_OWNER_ADDRESS="__public_address__"
    KOVAN_OWNER_MNEMONIC="__12-word_mnemonic__"
    
    ROPSTEN_PROXY_ADDRESS="__public_address__"
    ROPSTEN_PROXY_MNEMONIC="__12-word_mnemonic__"
    
    ROPSTEN_OWNER_ADDRESS="__public_address__"
    ROPSTEN_OWNER_MNEMONIC="__12-word_mnemonic__"
    
    MAINNET_PROXY_ADDRESS="__public_address__"
    MAINNET_PROXY_MNEMONIC="__12-word_mnemonic__"
    
    MAINNET_OWNER_ADDRESS="__public_address__"
    MAINNET_OWNER_MNEMONIC="__12-word_mnemonic__"
```

### To run the Main Repo (Testnet or Mainnet only):
    
 1. npm install
 2. npm run deploy-kovan

 
### To run the Variations Folders Locally:
    
 1. Fire up a local Test RPC (Ganache)
    - npx ganache-cli --deterministic
 2. npm install
 3. manually deploy contracts: 
    - deploy: variations/assets/dai/*.sol
      - Get deploy addresses and copy to "variations/assets/chai/Chai.sol"
    - deploy: variations/assets/chai/Chai.sol
    - deploy: variations/erc721/ChargedParticlesCHAI.sol
      - OR
    - deploy: variations/erc1155/ChargedParticlesCHAI.sol
 4. run **setup()** on ChargedParticles contract
    - _daiAddress param should point to deployed address of "variations/assets/dai/DaiGem.sol"
    - _chaiAddress param should point to deployed address of "variations/assets/chai/Chai.sol"
        

See package.json for more scripts

~~__________________________________~~

_MIT License_

Copyright (c) 2019, 2020 Rob Secord <robsecord.eth>


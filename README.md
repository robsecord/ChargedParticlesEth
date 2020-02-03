## Charged Particles - Solidity Contracts v0.0.3

**Charged Particles** are Non-Fungible Tokens (NFTs) that are minted with **DAI** and accrue interest via **CHAI** 
giving the Token a "Charge". 

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

#### Feedback & Contributions
Feel free to fork and/or use in your own projects!

And, of course, contributions are always welcome!

#### Community
Join our community, share ideas and help support the project in anyway you want!

**Discord**: https://discord.gg/Syh3gjz

### Frameworks/Software used:
 - Truffle **v5.1.11** (core: 5.1.11)
 - Ganache **2.1.0**
 - Solidity  **v0.5.13** (solc-js)
 - NodeJS **v12.14.1**
 - Web3.js **v1.2.1**

### To run Locally:
    
 1. Create a local .env file with the following (replace ... with your keys):
 
```bash
    INFURA_API_KEY="..."
    
    LOCAL_OWNER_ACCOUNT="..."
    KOVAN_OWNER_ACCOUNT="..."
    MAINNET_OWNER_ACCOUNT="..."
    
    LOCAL_WALLET_MNEMONIC="..."
    KOVAN_WALLET_MNEMONIC="..."
    MAINNET_WALLET_MNEMONIC="..."
```
 2. Fire up a local Test RPC (Ganache)
 3. npm install
 4. npm run deploy-local
 
See package.json for more scripts

~~__________________________________~~

_MIT License_

Copyright (c) 2019, 2020 Rob Secord <robsecord.eth>


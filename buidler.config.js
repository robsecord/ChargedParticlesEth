usePlugin("@nomiclabs/buidler-truffle5");
usePlugin("solidity-coverage");

module.exports = {
  defaultNetwork: "buidlerevm",
  solc: { version: "0.5.16" },
  networks: {
    development: {
      gas: 7000000,
      url: "http://localhost:8545"
    }
  }
};

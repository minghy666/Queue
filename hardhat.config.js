require("@nomicfoundation/hardhat-toolbox");
require("hardhat-gas-reporter");
require("dotenv").config();
require('@nomiclabs/hardhat-ethers');
require('@openzeppelin/hardhat-upgrades');

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.9",
  
  gasReporter: {
    enabled: true
  },

  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },

    mumbai: {
      url: `https://polygon-mumbai.infura.io/v3/${process.env.INFURA_KEY}`,
      accounts: [process.env.PRIVATE_KEY],
    },

    goerli: {
      url: `https://goerli.infura.io/v3/${process.env.INFURA_KEY}`,
      accounts: [process.env.PRIVATE_KEY],
    },

    bsctest: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545",
      chainId: 97,
      gasPrice: 20000000000,
      accounts: [process.env.PRIVATE_KEY],
    }

  },

  mocha: {
    timeout: 10000000
  }
};

import type { HardhatUserConfig } from "hardhat/config";

import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable } from "hardhat/config";
//import { bscTestnet } from "viem/chains";

import { readFileSync } from 'fs';

const data = JSON.parse(readFileSync('./secrets.json', 'utf8'));
const mnemonic: string = data.mnemonic;

const config: HardhatUserConfig = {
  plugins: [hardhatToolboxViemPlugin],
  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    },
  },
  networks: {
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1",
    },
    hardhatOp: {
      type: "edr-simulated",
      chainType: "op",
    },
    sepolia: {
      type: "http",
      chainType: "l1",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
    },
    bscTestnet: {
      type: "http",
      url: "https://data-seed-prebsc-1-s1.binance.org:8545",
      chainId: 97,
      gasPrice: 20000000000,
      accounts: {mnemonic: mnemonic}
    },

    'base-mainnet': {
      type: "http",
      url: 'https://mainnet.base.org',
      accounts: {mnemonic: mnemonic},
      gasPrice: 1000000000,
    },
    // for testnet
    'base-sepolia': {
      type: "http",
      url: 'https://sepolia.base.org',
      accounts: {mnemonic: mnemonic},
      gasPrice: 1000000000,
    },
    // for local dev environment
    'base-local': {
      type: "http",
      url: 'http://localhost:8545',
      accounts: {mnemonic: mnemonic},
      gasPrice: 1000000000,
    },
   
  },
};

export default config;

import "@nomicfoundation/hardhat-toolbox";
import { HardhatUserConfig } from "hardhat/config";
import { monadAccount } from "./keys";

const config: HardhatUserConfig = {
  solidity: {
    // version: "0.6.6",
    version: "0.5.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 99999,
      },
    },
  },
  defaultNetwork: "monad",
  networks: {
    monad: {
      url: "https://rpc-mainnet.monadinfra.com/rpc/FDra1kPP5XIAXHwXPRMqxKmlVPXA72mE",
    },
    "monad-testnet": {
      url: "https://testnet-rpc.monad.xyz/",
      accounts: [monadAccount],
    },
  },
  sourcify: {
    enabled: true,
    apiUrl: "https://sourcify-api-monad.blockvision.org",
    browserUrl: "https://testnet.monadexplorer.com",
  },
  etherscan: {
    enabled: false,
  },
};

export default config;

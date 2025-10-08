// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const FACTORY = "0xC921877BEcB785fDFbb96B6D8354Bb443C015995";
const WETH = "0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701";

const V2PeripheryModule = buildModule("V2Periphery", (m) => {
  // const router01 = m.contract("MondaV2Router01", [FACTORY, WETH]); // 0x65F78bC0cA458A6D01F2a56D6c9aAf822619332a
  const router02 = m.contract("MondaV2Router03", [
    FACTORY,
    WETH,
    "0x2108b8F6a2D6cC6117db17EA4cE3Af67D92A4716",
  ]); // 0xE8E699842464DC483f99c7f8313313b5EbbE6238

  return { router02 };
});

export default V2PeripheryModule;

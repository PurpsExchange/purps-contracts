// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const OWNER = "0x2C1C4609256DbB926A08c79e8b4c7c8c55856e5d";

const V2CoreModule = buildModule("V2Core", (m) => {
  const factory = m.contract("MondaV2Factory", [OWNER]);
  // const factory = m.contractAt(
  //   "MondaV2Factory",
  //   "0xdE58E95d53d80e20e19C684cEe31dec83323e871"
  // );
  // m.call(factory, "setFeeTo", [OWNER]);

  return { factory };
});

export default V2CoreModule;

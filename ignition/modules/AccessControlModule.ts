import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { keccak256, toBytes } from "viem";

import * as dotenv from "dotenv";

dotenv.config();

export default buildModule("AccessControlModuleModule", (m) => {
  // Deploy the contract with constructor args: initial admin + multisig
  const accessControlModule = m.contract("AccessControlModule", [
     process.env.DEPLOYER_ADDRESS as any,  // replace with env variable or hardcoded address
     process.env.MULTI_SIG_ADDRESS as any,  // replace with env variable or hardcoded address
  ]);

  // Example: grant KEEPER_ROLE to another address after deployment
  //const KEEPER_ROLE = keccak256(toBytes("KEEPER_ROLE"));
  //m.call(accessControlModule, "grantRole", [KEEPER_ROLE, m.env("KEEPER_ADDRESS")]);

  return { accessControlModule };
});

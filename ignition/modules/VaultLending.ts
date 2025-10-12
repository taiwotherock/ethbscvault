import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { keccak256, toBytes } from "viem";

import * as dotenv from "dotenv";

dotenv.config();

export default buildModule("VaultLendingModule", (m) => {
  // Deploy the contract with constructor args: initial admin + multisig
  const vaultLending = m.contract("VaultLending", [
     process.env.ACCESS_CONTROL_CONTRACT_ADDRESS as any,  
     // replace with env variable or hardcoded address  // replace with env variable or hardcoded address
  ]);

 
  return { vaultLending };
});

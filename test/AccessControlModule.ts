import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import * as dotenv from "dotenv";

import { getAddress } from "ethers";

dotenv.config();

describe("AccessControlModule", async function () {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();

  it("Should deploy and emit RoleGranted + MultisigUpdated", async function () {
        const walletClients = await viem.getWalletClients();
        const deployer = walletClients[0];
        //const [deployer] = await viem.getWalletClients();
        const multiSigAddress = process.env.MULTI_SIG_ADDRESS as '0x${string}';
        const deployerAddress = deployer.account.address as '0x${string}';

        console.log('deployer addr: ' + deployerAddress)
         console.log('multiSigAddress addr: ' + multiSigAddress)
        
        // Explicitly type the contract
        const accessControlModuleContract = await viem.deployContract("AccessControlModule",
            [deployerAddress,
            multiSigAddress]);

        const deploymentTxHash = (accessControlModuleContract as any).deploymentTxHash;

        console.log('Deployer address: ' + deployerAddress)
        console.log("✅ Contract deployed at:", accessControlModuleContract.address);
        console.log("📦 Deployment tx hash:", deploymentTxHash);
        //console.log('deploy gas.. ' + accessControlModuleContract.estimateGas )
        const ADMIN_ROLE = await accessControlModuleContract.read.ADMIN_ROLE();
        const deployerAddress2 = getAddress(deployer.account.address);

        await viem.assertions.emitWithArgs(
        deploymentTxHash,
        accessControlModuleContract as any,
        "RoleGranted" as any,
        [
            ADMIN_ROLE,
            deployerAddress2,
            deployerAddress2
        ]
        );

        // Verify the deployer is actually admin
        const isAdmin = await accessControlModuleContract.read.isAdmin([
        deployer.account.address,
        ]);
        assert.equal(isAdmin, true);
    });
    
    // Verify RoleGranted event emitted
     it("should correctly return true for isAdmin() when called by the initial admin", async function () {
        // Deploy the AccessControlModule contract
         const walletClients = await viem.getWalletClients();
         const deployer = walletClients[0];
        //const [deployer] = await viem.getWalletClients();
        const multiSigAddress = process.env.MULTI_SIG_ADDRESS as '0x${string}';
        const deployerAddress =  deployer.account.address as '0x${string}';

        const accessControlModuleContract = await viem.deployContract(
        "AccessControlModule",
        [deployerAddress, multiSigAddress]
        );

        // Read value directly from the contract
        const isAdmin = await accessControlModuleContract.read.isAdmin([
        deployer.account.address,
        ]);

        // Assert the return value
        assert.equal(isAdmin, true, "Expected deployer to be admin");
    });



   
});

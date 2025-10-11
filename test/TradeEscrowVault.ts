import assert from "node:assert/strict";
import { describe, it, before } from "node:test";
import { network } from "hardhat";
import * as dotenv from "dotenv";
import { getAddress } from "ethers";
import { zeroPadValue, toBeHex } from "ethers";
import { decodeEventLog, parseAbiItem } from "viem";

dotenv.config();

describe("TradeEscrowVault", async function () {
  let deployer: any;
  let buyer: any;
  let seller: any;
  let escrowVault: any;
  let usdtAddress: any;
  let viem: any;

  before(async () => {
    ({ viem } = await network.connect());
    const walletClients = await viem.getWalletClients();

    deployer = walletClients[0];
    buyer = walletClients[1];
    seller = walletClients[2];
    usdtAddress = walletClients[3];

      const accessControl = await viem.deployContract("AccessControlModule", [
        deployer.account.address,
        deployer.account.address // or multisig
      ]);
      const accessControlAddress = accessControl.address as `0x${string}`;


    // Deploy TradeEscrowVault
    escrowVault = await viem.deployContract("TradeEscrowVault", [
      accessControlAddress,
    ]);

    console.log("✅ TradeEscrowVault deployed at:", escrowVault.address);
  });

  it("should allow admin to whitelist users", async () => {
    const buyerAddr = getAddress(buyer.account.address);
    const sellerAddr = getAddress(seller.account.address);

    // Admin (deployer) whitelists buyer and seller
    await escrowVault.write.setWhitelist([buyerAddr, true], {
      account: deployer.account,
    });

    await escrowVault.write.setWhitelist([sellerAddr, true], {
      account: deployer.account,
    });

    // Check if users are whitelisted
    const buyerOk = await escrowVault.read.whitelist([buyerAddr]);
    const sellerOk = await escrowVault.read.whitelist([sellerAddr]);

    assert.equal(buyerOk, true, "Buyer should be whitelisted");
    assert.equal(sellerOk, true, "Seller should be whitelisted");
  });

  it("should revert if non-admin tries to whitelist", async () => {
    const randomAddr = getAddress(buyer.account.address);

    let reverted = false;
    try {
      await escrowVault.write.setWhitelist([randomAddr, true], {
        account: buyer.account, // not admin
      });
    } catch (err: any) {
      reverted = true;
      assert.match(
        err.message,
        /revert|AccessControl|onlyAdmin/i,
        "Expected revert when non-admin calls setWhitelist"
      );
    }

    assert.equal(reverted, true, "Should revert for non-admin");
  });


  it("should create a sell offer and store it correctly", async () => {
    const ref = zeroPadValue(toBeHex(1), 32);
    const token = getAddress(usdtAddress.account.address);
    const publicClient = await viem.getPublicClient();

    const buyerAddr = getAddress(buyer.account.address);
    const sellerAddr = getAddress(seller.account.address);

    const DECIMALS = BigInt(1e18);
    const fiatAmount = 1000;
    const fiatToTokenRate = DECIMALS / BigInt(1500);

    // Create offer using seller's account
    const txHash =await escrowVault.write.createOffer(
      [
        ref,
        buyerAddr,
        token,
        false, // isBuy
        Math.floor(Date.now() / 1000) + 3600, // expiry +1h
        "NGN",
        fiatAmount,
        fiatToTokenRate,
      ],
      { account: seller.account } // correct Viem syntax
    );

    // Read the offer from the contract
    console.log('ref ' + ref)
    console.log('fiatAmount ' + fiatAmount)
    
    //const offer = await escrowVault.read.offers([ref]);

    console.log("txHash:", txHash);
    const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
    console.log(receipt);

    assert.equal("success",receipt.status,"Offer creation failed")

     //const offer = await escrowVault.read.getOffer([ref]);

    
});



});

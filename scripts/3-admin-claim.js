import { Lucid, Blockfrost, Data, Constr, fromText } from "@lucid-evolution/lucid";
import { validatorToAddress, getAddressDetails } from "@lucid-evolution/utils";
import * as BF from "@blockfrost/blockfrost-js";
import contract from "../plutus.json" with { type: "json" };
import * as dotenv from "dotenv";
dotenv.config();

(async function main() {
  try {
    const lucid = await Lucid(
      new Blockfrost(process.env.BLOCKFROST_URL, process.env.BLOCKFROST_API_KEY),
      process.env.NETWORK
    );

    const API = new BF.BlockFrostAPI({ projectId: process.env.BLOCKFROST_API_KEY });

    const spendValidator = {
      type: "PlutusV3",
      script: contract.validators[0].compiledCode,
    };

    const contractAddress = validatorToAddress(process.env.NETWORK, spendValidator);
    console.log("Contract Address:", contractAddress);

    const utxos = await API.addressesUtxos(contractAddress);
    if (utxos.length === 0) throw new Error("No UTxOs at contract");
    const previousDatumHash = utxos[0].data_hash;
    const previousDatum = await API.scriptsDatum(previousDatumHash);
    console.log("Previous Datum:", JSON.stringify(previousDatum, null, 2));

    const spendingUtxo = (await lucid.utxosAt(contractAddress))[0];

    // Admin wallet
    const mnemonic = process.env.ADMIN_MNEMONIC;
    lucid.selectWallet.fromSeed(mnemonic);
    const ownerAddress = await lucid.wallet().address();
    console.log("Owner Address:", ownerAddress);
    const ownerPKH = getAddressDetails(ownerAddress).paymentCredential?.hash;
    if (!ownerPKH) throw new Error("Cannot get owner PKH");

    const raised = BigInt(previousDatum.json_value.fields[5]["int"]);
    console.log("Raised: ",raised);

    // Redeemer: OwnerWithdraw(current_time, owner_address)
    const currentTime = BigInt(Math.floor(Date.now() / 1000)) + 8n * 24n * 60n * 60n;

    const redeemer = Data.to(new Constr(2, [currentTime]));
    console.log("Redeemer:", redeemer);

    const tx = await lucid
      .newTx()
      .collectFrom([spendingUtxo], redeemer)
      .attach.SpendingValidator(spendValidator)
      // .pay.ToAddress(ownerAddress, { lovelace: raised })
      .addSigner(ownerAddress)
      .complete();

    const signedTx = await tx.sign.withWallet().complete();
    const txHash = await signedTx.submit();
    console.log("Owner withdraw txHash:", txHash);
  } catch (err) {
    console.error("err:", err);
  }
})();

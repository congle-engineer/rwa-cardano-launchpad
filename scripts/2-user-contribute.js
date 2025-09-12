import { Lucid, Blockfrost, Data, Constr } from "@lucid-evolution/lucid";
import { validatorToAddress, getAddressDetails } from "@lucid-evolution/utils";
import * as BF from "@blockfrost/blockfrost-js";
import contract from "../plutus.json" assert { type: "json" };
import * as dotenv from "dotenv";
dotenv.config();

(async function main() {
  try {
    const lucid = await Lucid(
      new Blockfrost(
        process.env.BLOCKFROST_URL,
        process.env.BLOCKFROST_API_KEY
      ),
      process.env.NETWORK
    );

    const API = new BF.BlockFrostAPI({
      projectId: process.env.BLOCKFROST_API_KEY,
    });

    // Read validator from plutus.json
    const spendValidator = {
      type: "PlutusV3",
      script: contract.validators[0].compiledCode,
    };

    // Get contract address
    const contractAddress = validatorToAddress(
      process.env.NETWORK,
      spendValidator
    );
    console.log("Contract Address: ", contractAddress);

    // Read current datum belongs to the single utxo of contract address
    // Note: Read utxo by API to get datum info
    const utxo = await API.addressesUtxos(contractAddress);
    console.log("utxo: ", utxo);

    const previousDatumHash = utxo[0].data_hash;
    const previousDatum = await API.scriptsDatum(previousDatumHash);
    console.log("previousDatum: ", JSON.stringify(previousDatum, 0, 4));

    const previousOwnerPKH = previousDatum.json_value.fields[0]["bytes"];
    console.log("previousOwnerPKH: ", previousOwnerPKH);

    const previousStartDate = previousDatum.json_value.fields[1]["int"];
    console.log("previousStartDate: ", previousStartDate);

    const previousEndDate = previousDatum.json_value.fields[2]["int"];
    console.log("previousEndDate: ", previousEndDate);

    const previousInterestRate = previousDatum.json_value.fields[3]["int"];
    console.log("previousInterestRate: ", previousInterestRate);

    const previousTargetAmount = previousDatum.json_value.fields[4]["int"];
    console.log("previousTargetAmount: ", previousTargetAmount);

    const previousCurrentRaised = previousDatum.json_value.fields[5]["int"];
    console.log("previousCurrentRaised: ", previousCurrentRaised);

    const previousContributors = previousDatum.json_value.fields[6]["list"];
    console.log("previousContributors: ", previousContributors);

    // Get utxo to build transaction
    // Note: Read utxo by lucid to build transaction
    const spendingUtxo = await lucid.utxosAt(contractAddress);
    console.log("spendingUtxo: ", spendingUtxo);

    // User mnemonic
    const mnemonic = process.env.USER_MNEMONIC;
    lucid.selectWallet.fromSeed(mnemonic);

    const userAddress = await lucid.wallet().address();
    console.log("userAddress: ", userAddress);

    const userPKH = getAddressDetails(userAddress).paymentCredential?.hash;
    if (!userPKH) throw new Error("Cannot get user PKH");
    console.log("userPKH: ", userPKH);

    // Amount contribute to the crowdfunding
    const userContribute = 1_000_000n; // 1 ADA

    // Get current time
    const currentTime = BigInt(Math.floor(Date.now() / 1000));

    // Redeemer Actions:
    // 0 - UserContribute
    const redeemer = Data.to(new Constr(0, [currentTime, userPKH]));
    console.log("redeemer: ", redeemer);

    // Calculate new current raised for new datum
    const currentRaised = BigInt(previousCurrentRaised) + userContribute;
    console.log("currentRaised: ", currentRaised);

    let newContributors = [];
    let isExist = false;

    previousContributors.forEach((contributor) => {
      if (contributor.fields[0]["bytes"] == userPKH) {
        isExist = true;
        newContributors.push(
          new Constr(0, [
            userPKH,
            BigInt(contributor.fields[1]["int"]) + userContribute,
          ])
        );
      } else {
        newContributors.push(
          new Constr(0, [
            contributor.fields[0]["bytes"],
            BigInt(contributor.fields[1]["int"]),
          ])
        );
      }
    });

    // Because list.push() in Aiken will add an element in front of the list
    if (!isExist) {
      newContributors = [
        new Constr(0, [userPKH, userContribute]),
        ...newContributors,
      ];
    }
    console.log("newContributors: ", newContributors);

    // Construct the datum
    const datum = Data.to(
      new Constr(0, [
        previousOwnerPKH,
        BigInt(previousStartDate),
        BigInt(previousEndDate),
        BigInt(previousInterestRate),
        BigInt(previousTargetAmount),
        BigInt(currentRaised),
        newContributors,
      ])
    );
    console.log("datum: ", datum);

    // Calculate final amount to send to contract
    const finalAmount = spendingUtxo[0].assets.lovelace + userContribute;
    console.log("finalAmount: ", finalAmount);

    const tx = await lucid
      .newTx()
      .collectFrom([spendingUtxo[0]], redeemer)
      .attach.SpendingValidator(spendValidator)
      .pay.ToContract(
        contractAddress,
        { kind: "inline", value: datum },
        { lovelace: finalAmount }
      )
      .addSigner(userAddress)
      .complete();

    const signedTx = await tx.sign.withWallet().complete();

    const txHash = await signedTx.submit();
    console.log("txHash: ", txHash);
  } catch (err) {
    console.log("err: ", err);
  }
})();

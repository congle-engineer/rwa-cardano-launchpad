import { Lucid, Blockfrost, Data, Constr } from "@lucid-evolution/lucid";
import { validatorToAddress, getAddressDetails } from "@lucid-evolution/utils";
import contract from "../plutus.json" with { type: "json" };
import * as dotenv from "dotenv";
dotenv.config();

(async function main() {
  try {
    // ======== SETUP ========
    const lucid = await Lucid(
      new Blockfrost(process.env.BLOCKFROST_URL, process.env.BLOCKFROST_API_KEY),
      process.env.NETWORK
    );

    // ======== ADMIN WALLET ========
    const adminAddress = process.env.ADMIN_ADDRESS;
    const adminPKH = getAddressDetails(adminAddress).paymentCredential?.hash;
    if (!adminPKH) throw new Error("Cannot get admin PKH");
    lucid.selectWallet.fromSeed(process.env.ADMIN_MNEMONIC);

    // ======== CONTRACT ========
    const spendValidator = { type: "PlutusV3", script: contract.validators[0].compiledCode };
    const contractAddress = validatorToAddress(process.env.NETWORK, spendValidator);
    console.log("Contract Address:", contractAddress);

    // ======== INITIALIZE DATUM ========
    const startDate = BigInt(Math.floor(Date.now() / 1000)); // now
    const endDate = startDate + 7n * 24n * 60n * 60n; // +7 days
    const interestRate = 5n;
    const targetAmount = 5_000_000n; // 5 ADA in lovelace
    const currentRaised = 0n;
    const contributors = []; // empty

    const initDatum = Data.to(
      new Constr(0, [
        adminPKH,
        startDate,
        endDate,
        interestRate,
        targetAmount,
        currentRaised,
        contributors
      ])
    );
    const initialLovelace = 2_000_000n;

    // ======== SUBMIT INITIALIZATION TX ========
    const initTx = await lucid
      .newTx()
      .pay.ToContract(contractAddress, { kind: "inline", value: initDatum }, { lovelace: initialLovelace })
      .complete();
    const signedInitTx = await initTx.sign.withWallet().complete();
    const initTxHash = await signedInitTx.submit();
    console.log("Contract initialized! TxHash:", initTxHash);

    // ======== WAIT A BIT OR REFRESH UTXO ========
    // Fetch contract UTxO to contribute
    const spendingUtxos = await lucid.utxosAt(contractAddress);
    const spendingUtxo = spendingUtxos[0];

  } catch (err) {
    console.error("Error:", err);
  }
})();

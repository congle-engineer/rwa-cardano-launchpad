# 🚀 Crowdfunding Smart Contract (Cardano + Aiken + Lucid Evolution)

## 📖 Overview

This project implements a **crowdfunding smart contract** on the Cardano blockchain using **Aiken** for on-chain validation and **Lucid Evolution** (Node.js SDK) for off-chain interaction.

The contract allows:

* 📥 **Contributions** during the fundraising period.
* 💸 **Refunds** if the target is not met after the deadline.
* 🏦 **Owner withdrawals** if the target is reached after the deadline.
* 🎟️ **Future extension** for distributing RWA tokens proportionally to contributors.

---

## ⚙️ Tech Stack

* **Smart contract**: [Aiken](https://aiken-lang.org/)
* **Off-chain SDK**: [Lucid Evolution](https://github.com/spacebudz/lucid-evolution)
* **Blockchain API**: [Blockfrost](https://blockfrost.io/)
* **Runtime**: Node.js

---

## 📂 Project Structure

```
crowdfunding/
├── aiken.toml
├── validators/
│   └── fundraising.ak
│   └── rwa_minting.ak
├── plutus.json            # Compiled contract
├── scripts/               # Off-chain scripts
│   ├── 1-initialize.js
├── .env.example
└── README.md
```

---

## 🔧 Setup

### 1. Compile the contract

```sh
cd rwa-cardano-launchpad
aiken build -t verbose
```

### 2. Run scripts step by step

#### Install dependencies

```sh
cd rwa-cardano-launchpad/scripts
npm install
```

#### Setup environment variables

Copy and edit your `.env` file:

```sh
cp env.sample .env
```

Fill in the variables:

* `BLOCKFROST_API_KEY`: [Get one from Blockfrost](https://blockfrost.io/)
* `BLOCKFROST_URL`: Blockfrost endpoint (e.g., `https://cardano-preprod.blockfrost.io/api/v0`)
* `NETWORK`: Cardano network (e.g., `Preprod`)
* `ADMIN_ADDRESS`: Your admin wallet address
* `ADMIN_MNEMONIC`: Mnemonic phrase for admin wallet
* `USER_MNEMONIC`: Mnemonic phrase for a contributor wallet

---

## 🚀 Workflow

### 2.1. Initialize the crowdfunding contract

Update the script (`1-initialize.js`) to set your campaign parameters:

```js
// Prepare data for datum
const startDate = BigInt(Math.floor(Date.now() / 1000)); // now
const endDate = startDate + 7n * 24n * 60n * 60n; // +7 days
const interestRate = 5n;
const targetAmount = 5_000_000n; // 5 ADA in lovelace
const currentRaised = 0n;
const contributors = []; // empty
```

Run the script:

```sh
node 1-initialize.js
```

Example output:

```sh
Contract Address:  addr_test1wrdzsldt65nfpsy3e7gzfmfhstuwm3wjz5qxyt8e5jn0jegzlz7z2
txHash:  306f36a5332040da394a1652ef792b9214f92b60fc46e201a9f33d176a0d1245
```
---

## 🔒 Validation Rules

The validator enforces:

* Contributions only allowed within `[start_date, end_date]`.
* Minimum contribution = **1 ADA**.
* Immutable parameters (`owner_pkh`, `start_date`, `end_date`, `target_amount`, `interest_rate`) cannot change.
* Contributions update `contributors` list correctly.
* Refunds only possible if target not met after end date.
* Withdrawals only possible if target met after end date.

---

## 📜 License

MIT License. Free for educational and commercial use.

---

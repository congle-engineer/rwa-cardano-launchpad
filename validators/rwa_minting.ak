use cardano/transaction.{Transaction}
use aiken/crypto.{VerificationKeyHash}
use aiken/collection/list

pub type Datum {
  owner_pkh: VerificationKeyHash,
  start_date: Int,
  end_date: Int,
  claim_date: Int,
  interest_rate: Int,
  target_amount: Int,
  current_raised: Int
}

pub type Redeemer {
  MintRWA(Int)
  BurnRWAForReimbursement(Int, Int) // current_time, amount_of_RWA
}

validator rwa_minting {
  mint(datum: Option<Datum>, redeemer: Redeemer, self: Transaction) {
    expect Some(Datum { owner_pkh, end_date, claim_date, current_raised, target_amount, .. }) = datum

    let is_owner = list.has(self.extra_signatories, owner_pkh)

    when redeemer is {
      MintRWA(current_time) -> {
        if !(current_time >= end_date) {
          trace @"[RWA Mint Error]: cannot mint before end_date"
          False
        } else if !(current_raised == target_amount) {
          trace @"[RWA Mint Error]: target not reached, cannot mint"
          False
        } else if !is_owner {
          trace @"[RWA Mint Error]: only owner can mint"
          False
        } else {
          True
        }
      }

      BurnRWAForReimbursement(current_time, _) -> {
        if !(current_time >= claim_date) {
          trace @"[RWA Burn Error]: cannot burn for reimbursement before claim_date"
          False
        } else if !(current_raised == target_amount) {
          trace @"[RWA Burn Error]: fundraising target not reached"
          False
        } else {
          True
        }
      }
    }
  }

  else(_) {
    fail
  }
}


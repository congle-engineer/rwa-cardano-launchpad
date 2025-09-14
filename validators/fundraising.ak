use cardano/assets.{lovelace_of}
use cardano/transaction.{Transaction, OutputReference, InlineDatum, Output}
use aiken/crypto.{VerificationKeyHash}
use aiken/collection/list
use cardano/address.{VerificationKey}

// Constants
//const lovelace_per_ada: Int = 1_000_000
const min_contribution_lovelace: Int = 1_000_000 // 1 ADA minimum

pub type ContributorInfo {
  contributor_pkh: VerificationKeyHash,
  amount: Int  // In lovelace (not ADA) to avoid precision loss
}

pub type Datum {
  owner_pkh: VerificationKeyHash,
  start_date: Int,        // Fundraising start
  end_date: Int,          // Fundraising end (also when withdraw & mint start)
  interest_rate: Int,     // Kept for off-chain use
  target_amount: Int,     // In lovelace
  current_raised: Int,    // In lovelace
  contributors: List<ContributorInfo>  // Track all contributors
}

pub type Redeemer {
  UserContribute(Int, VerificationKeyHash)  // current_time, contributor_pkh
  UserClaimRefund(Int, VerificationKeyHash) // current_time, contributor_pkh
  OwnerWithdraw(Int)       // current_time
  OwnerDistributeRWA(Int)  // current_time
}

// Helper function to find contributor
fn find_contributor(contributors: List<ContributorInfo>, pkh: VerificationKeyHash) -> Option<ContributorInfo> {
  contributors
    |> list.find(fn(c) { c.contributor_pkh == pkh })
}

// Helper function to calculate total contributed amount
// fn calculate_total_contributed(contributors: List<ContributorInfo>) -> Int {
//   contributors
//     |> list.foldr(0, fn(c, acc) { acc + c.amount })
// }

// Helper function to update contributor list
fn update_contributors(contributors: List<ContributorInfo>, contributor_pkh: VerificationKeyHash, amount: Int) -> List<ContributorInfo> {
  when find_contributor(contributors, contributor_pkh) is {
    Some(existing) -> 
      contributors
        |> list.map(fn(c) { 
          if c.contributor_pkh == contributor_pkh {
            ContributorInfo { contributor_pkh: contributor_pkh, amount: existing.amount + amount }
          } else {
            c
          }
        })
    None -> 
      list.push(contributors, ContributorInfo { contributor_pkh: contributor_pkh, amount: amount })
  }
}

// Helper function to remove contributor
fn remove_contributor(contributors: List<ContributorInfo>, contributor_pkh: VerificationKeyHash) -> List<ContributorInfo> {
  contributors
    |> list.filter(fn(c) { c.contributor_pkh != contributor_pkh })
}

// Helper function to validate output goes to specific address
fn validate_output_to_address(outputs: List<Output>, target_pkh: VerificationKeyHash, min_amount: Int) -> Bool {
  outputs
    |> list.any(fn(output) { 
      output.address.payment_credential == VerificationKey(target_pkh) && lovelace_of(output.value) >= min_amount 
    })
}

validator fundraising {
  spend(datum: Option<Datum>, redeemer: Redeemer, utxo: OutputReference, self: Transaction) {
    expect Some(Datum { owner_pkh, start_date, end_date, target_amount, current_raised, interest_rate, contributors }) = datum

    let Transaction { inputs, outputs, extra_signatories, .. } = self

    expect Some(spending_utxo) = inputs |> list.find(fn(input) { input.output_reference == utxo })

    when redeemer is {
      UserContribute(current_time, contributor_pkh) -> {
        // Validate timing
        if !(current_time >= start_date && current_time <= end_date) {
          trace @"[Contract Error]: fundraising not active"
          False
        } else {
          expect Some(output_to_contract) =
            outputs |> list.find(fn(output) { output.address == spending_utxo.output.address })

          expect InlineDatum(new_data) = output_to_contract.datum
          expect new_datum: Datum = new_data

          let value_difference = lovelace_of(output_to_contract.value) - lovelace_of(spending_utxo.output.value)
          let contribution_amount_lovelace = value_difference

          // Validate minimum contribution
          if contribution_amount_lovelace < min_contribution_lovelace {
            trace @"[Contract Error]: contribution below minimum"
            False
          } else {
            // Validate contribution amount matches datum update
            let expected_new_raised = current_raised + contribution_amount_lovelace
            let is_contribution_correct = new_datum.current_raised == expected_new_raised

            // Validate contribution doesn't exceed target
            let is_within_target = new_datum.current_raised <= target_amount

            // Validate immutable fields remain unchanged
            let is_owner_unchanged = owner_pkh == new_datum.owner_pkh
            let is_target_unchanged = target_amount == new_datum.target_amount
            let is_start_date_unchanged = start_date == new_datum.start_date
            let is_end_date_unchanged = end_date == new_datum.end_date
            let is_interest_rate_unchanged = interest_rate == new_datum.interest_rate

            // Validate contributors list is updated correctly
            let expected_contributors = update_contributors(contributors, contributor_pkh, contribution_amount_lovelace)
            let is_contributors_updated_correctly = new_datum.contributors == expected_contributors

            // Validate that the transaction is signed by the contributor
            let is_signed_by_contributor = list.has(extra_signatories, contributor_pkh)

            if !is_contribution_correct {
              trace @"[Contract Error]: contribution amount mismatch."
              False
            } else if !is_within_target {
              trace @"[Contract Error]: contribution exceeds target amount"
              False
            } else if !is_owner_unchanged {
              trace @"[Contract Error]: owner must remain unchanged"
              False
            } else if !is_target_unchanged {
              trace @"[Contract Error]: target amount must remain unchanged"
              False
            } else if !is_start_date_unchanged {
              trace @"[Contract Error]: start date must remain unchanged"
              False
            } else if !is_end_date_unchanged {
              trace @"[Contract Error]: end date must remain unchanged"
              False
            } else if !is_interest_rate_unchanged {
              trace @"[Contract Error]: interest rate must remain unchanged"
              False
            } else if !is_contributors_updated_correctly {
              trace @"[Contract Error]: contributors list not updated correctly"
              False
            } else if !is_signed_by_contributor {
              trace @"[Contract Error]: transaction must be signed by contributor"
              False
            } else {
              True
            }
          }
        }
      }

      UserClaimRefund(current_time, contributor_pkh) -> {
        let is_after_end = current_time > end_date
        let is_failed = current_raised < target_amount
        let is_signed_by_contributor = list.has(extra_signatories, contributor_pkh)

        if !is_after_end {
          trace @"[Contract Error]: cannot refund before end date"
          False
        } else if !is_failed {
          trace @"[Contract Error]: refund only available if target not reached"
          False
        } else if !is_signed_by_contributor {
          trace @"[Contract Error]: refund must be signed by contributor"
          False
        } else {
          // Find the contributor and validate refund amount
          expect Some(contributor_info) = find_contributor(contributors, contributor_pkh)
          let refund_amount_lovelace = contributor_info.amount
          
          // Validate that refund is sent to the contributor
          let is_refund_sent = validate_output_to_address(outputs, contributor_pkh, refund_amount_lovelace)
          
          if !is_refund_sent {
            trace @"[Contract Error]: refund not properly sent to contributor"
            False
          } else {
            // If there's a continuing UTxO, validate contributors list is updated
            when outputs |> list.find(fn(output) { output.address == spending_utxo.output.address }) is {
              Some(continuing_output) -> {
                expect InlineDatum(continuing_data) = continuing_output.datum
                expect continuing_datum: Datum = continuing_data
                
                let expected_contributors = remove_contributor(contributors, contributor_pkh)
                let expected_raised = current_raised - contributor_info.amount
                
                continuing_datum.contributors == expected_contributors &&
                continuing_datum.current_raised == expected_raised
              }
              None -> True  // Contract is being consumed entirely
            }
          }
        }
      }

      OwnerWithdraw(current_time) -> {
        let is_after_end = current_time > end_date
        let is_target_reached = current_raised >= target_amount  // Allow over-funding
        let is_owner = list.has(extra_signatories, owner_pkh)

        if !is_after_end {
          trace @"[Contract Error]: cannot withdraw before end date"
          False
        } else if !is_target_reached {
          trace @"[Contract Error]: withdraw only available if target reached"
          False
        } else if !is_owner {
          trace @"[Contract Error]: withdrawal must be signed by owner"
          False
        } else {
          // Validate that funds are actually sent to owner
          let withdrawal_amount = current_raised
          
          let is_withdrawal_sent = validate_output_to_address(outputs, owner_pkh, withdrawal_amount)
          
          if !is_withdrawal_sent {
            trace @"[Contract Error]: funds not properly sent to owner"
            False
          } else {
            True
          }
        }
      }

      OwnerDistributeRWA(current_time) -> {
        let is_after_end = current_time > end_date
        let is_target_reached = current_raised >= target_amount
        let is_owner = list.has(extra_signatories, owner_pkh)

        if !is_after_end {
          trace @"[Contract Error]: cannot distribute before end date"
          False
        } else if !is_target_reached {
          trace @"[Contract Error]: distribution only available if target reached"
          False
        } else if !is_owner {
          trace @"[Contract Error]: distribution must be signed by owner"
          False
        } else {
          // Validate that RWA tokens are distributed proportionally to contributors
          // This would need more complex validation based on the specific RWA token implementation
          // For now, we just validate the basic conditions
          True
        }
      }
    }
  }

  else(_) {
    fail
  }
}

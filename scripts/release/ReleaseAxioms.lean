-- Fresh axiom report for the release hardening proofs (H1 and grounded parts of H2/H3/H5).
-- Run: lake build MathguardRelease && lake env lean scripts/release/ReleaseAxioms.lean
import ReleaseH1
import ReleaseDispatch
import ReleaseReload
import ReleaseApproval
-- ReleaseH1
#print axioms Mathguard.Release.executeReplyTag_committed_iff
#print axioms Mathguard.Release.chargeBound_after_reserve_isSome
#print axioms Mathguard.Release.reserve_then_charge
#print axioms Mathguard.Release.executeCore_of_not_committed
#print axioms Mathguard.Release.executeCore_of_reserve_none
#print axioms Mathguard.Release.executeCore_of_reserve_charge
#print axioms Mathguard.Release.executeCore_committed_iff
#print axioms Mathguard.Release.executeCore_committed_iff_capacity
#print axioms Mathguard.Release.executeCore_commit_state
#print axioms Mathguard.Release.executeCore_commit_exact
#print axioms Mathguard.Release.executeCore_noncommit_unchanged
#print axioms Mathguard.Release.executeCore_replayed_iff
#print axioms Mathguard.Release.executeCore_exact_replay
#print axioms Mathguard.Release.executeCore_replay_any_policy_clock_approval
#print axioms Mathguard.Release.executeCore_conflict
#print axioms Mathguard.Release.executeCore_financialInvariant
#print axioms Mathguard.Release.TicketsBelow.fresh
#print axioms Mathguard.Release.executeCore_ticketsBelow
#print axioms Mathguard.Release.request_requestJson
#print axioms Mathguard.Release.approvalOpt_of_ne_null
#print axioms Mathguard.Release.context_contextJson
#print axioms Mathguard.Release.executeJson_fields
#print axioms Mathguard.Release.dispatch_executeJson_spec
#print axioms Mathguard.Release.dispatch_executeJson_uninitialized
#print axioms Mathguard.Release.dispatch_executeJson_refines
#print axioms Mathguard.Release.previewJson_fields
#print axioms Mathguard.Release.dispatch_previewJson_spec
#print axioms Mathguard.Release.demo_h1_fresh_commit
#print axioms Mathguard.Release.demo_h1_capacity_denial
#print axioms Mathguard.Release.demo_h1_expired_exact_replay
#print axioms Mathguard.Release.demo_h1_conflict
#print axioms Mathguard.Release.demo_h1_preview
#print axioms Mathguard.Release.demo_h1_dispatch_commit
-- ReleaseDispatch
#print axioms Mathguard.Release.dispatch_ok_cases
#print axioms Mathguard.Release.settle_seen
#print axioms Mathguard.Release.settle_spent
#print axioms Mathguard.Release.chargeBound_settle
#print axioms Mathguard.Release.initial_workerInvariant
#print axioms Mathguard.Release.dispatch_preserves_workerInvariant
#print axioms Mathguard.Release.workerFrame_preserves_workerInvariant
#print axioms Mathguard.Release.WorkerInvariant.committed_iff_capacity
#print axioms Mathguard.Release.executeCore_monotone
#print axioms Mathguard.Release.dispatch_monotone
#print axioms Mathguard.Release.workerFrame_journal_prefix
#print axioms Mathguard.Release.replayCompleted_nil
#print axioms Mathguard.Release.replayCompleted_cons
#print axioms Mathguard.Release.replayCompleted_append
#print axioms Mathguard.Release.replayCompleted_append_of_ok
#print axioms Mathguard.Release.replayCompleted_ok_state
#print axioms Mathguard.Release.replayCompleted_preserves
#print axioms Mathguard.Release.replayCompleted_journal_prefix
#print axioms Mathguard.Release.replayCompleted_mismatch
#print axioms Mathguard.Release.replayCompleted_append_of_error
#print axioms Mathguard.Release.replayCompleted_rejected
#print axioms Mathguard.Release.committed_retry_replays
#print axioms Mathguard.Release.retry_after_replay
-- ReleaseReload
#print axioms Mathguard.Release.workerFrame_of_error
#print axioms Mathguard.Release.controlPolicy_valid
#print axioms Mathguard.Release.dispatch_configure
#print axioms Mathguard.Release.configure_preserves
#print axioms Mathguard.Release.rejected_command_unchanged
#print axioms Mathguard.Release.configure_stales_old_epoch
#print axioms Mathguard.Release.dispatch_control_configure
-- ReleaseApproval
#print axioms Mathguard.Release.genericApprovalValid_iff
#print axioms Mathguard.Release.genericApprovalValid_fields
#print axioms Mathguard.Release.consumeGenericApproval_eq_some_iff
#print axioms Mathguard.Release.consume_rejects_other_binding
#print axioms Mathguard.Release.consume_rejects_changed_interaction
#print axioms Mathguard.Release.consume_rejects_changed_content
#print axioms Mathguard.Release.consume_rejects_changed_config
#print axioms Mathguard.Release.consume_marks_used
#print axioms Mathguard.Release.consume_twice_fails
#print axioms Mathguard.Release.consume_after_expiry_fails
#print axioms Mathguard.Release.issue_some_iff
#print axioms Mathguard.Release.issued_valid
#print axioms Mathguard.Release.combine_executes_false_of_right
#print axioms Mathguard.Release.semantic_review_blocks_despite_approval
#print axioms Mathguard.Release.unavailable_blocks_despite_approval
#print axioms Mathguard.Release.genericAdmit_irreversible
#print axioms Mathguard.Release.le_foldl_max
#print axioms Mathguard.Release.lt_foldl_max_succ
#print axioms Mathguard.Release.freshApprovalNonce_fresh
#print axioms Mathguard.Release.probe_nonce_fresh
#print axioms Mathguard.Release.length_allocator_collides
#print axioms Mathguard.Release.refs_invalid_after_restart

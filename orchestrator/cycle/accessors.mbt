///|
pub fn UpdateCycle::state(self : Self) -> CycleState {
  self.state
}

///|
pub fn UpdateCycle::policy(self : Self) -> @identity.PolicyGeneration {
  self.round.policy()
}

///|
pub fn UpdateCycle::training_policy(self : Self) -> @identity.PolicyGeneration {
  self.training_policy
}

///|
pub fn UpdateCycle::manifest(self : Self) -> @experiment.ExperimentManifest {
  self.manifest
}

///|
pub fn UpdateCycle::rollout_count(self : Self) -> Int32 {
  self.round.rollout_count()
}

///|
pub fn UpdateCycle::terminal_count(self : Self) -> Int32 {
  self.groups.terminal_count
}

///|
pub fn UpdateCycle::usable_count(self : Self) -> Int32 {
  self.groups.usable_count
}

///|
pub fn UpdateCycle::group_count(self : Self) -> Int32 {
  self.groups.group_count()
}

///|
pub fn UpdateCycle::staleness(self : Self) -> @staleness.StalenessEvidence? {
  self.staleness
}

///|
pub fn UpdateCycle::advantage_count(self : Self) -> Int32 {
  self.round.advantage_count()
}

///|
pub fn UpdateCycle::candidate(self : Self) -> @update.CandidatePolicy? {
  self.candidate
}

///|
pub fn UpdateCycle::committed_policy(
  self : Self,
) -> @identity.PolicyGeneration? {
  self.committed_policy
}

///|
pub fn UpdateCycle::abort_reason(self : Self) -> CycleAbortReason? {
  self.abort_reason
}

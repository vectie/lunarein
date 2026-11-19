///|
pub(all) suberror TrainerProtocolError {
  InvalidRequestId
  InvalidState(expected~ : TrainerState, actual~ : TrainerState)
  BatchMismatch
  PolicyMismatch
  CandidateMismatch
  UnsupportedVersion
} derive(Debug, Eq)

///|
#valtype
pub struct TrainingRequestId {
  priv value : UInt64
} derive(Debug, Eq)

///|
pub fn TrainingRequestId::new(
  value : UInt64,
) -> Self raise TrainerProtocolError {
  if value == 0UL {
    raise InvalidRequestId
  }
  { value, }
}

///|
pub fn TrainingRequestId::value(self : Self) -> UInt64 {
  self.value
}

///|
pub struct TrainingRequest {
  priv version : @version.ProtocolVersion
  priv id : TrainingRequestId
  priv batch : @update.TrainingBatch
}

///|
pub fn TrainingRequest::new(
  id~ : TrainingRequestId,
  batch~ : @update.TrainingBatch,
) -> Self {
  { version: @version.ProtocolVersion::v1(), id, batch, }
}

///|
pub fn TrainingRequest::new_versioned(
  version~ : @version.ProtocolVersion,
  id~ : TrainingRequestId,
  batch~ : @update.TrainingBatch,
) -> Self raise TrainerProtocolError {
  if !version.is_exact(@version.ProtocolVersion::v1()) {
    raise UnsupportedVersion
  }
  { version, id, batch, }
}

///|
pub fn TrainingRequest::version(self : Self) -> @version.ProtocolVersion {
  self.version
}

///|
pub fn TrainingRequest::id(self : Self) -> TrainingRequestId {
  self.id
}

///|
pub fn TrainingRequest::batch(self : Self) -> @update.TrainingBatch {
  self.batch
}

///|
pub struct TrainerStepResult {
  priv request_id : TrainingRequestId
  priv evidence : @update.OptimizerStepEvidence
  priv candidate : @update.CandidatePolicy
}

///|
pub fn TrainerStepResult::new(
  request~ : TrainingRequest,
  evidence~ : @update.OptimizerStepEvidence,
  candidate~ : @update.CandidatePolicy,
) -> Self raise TrainerProtocolError {
  let batch = request.batch()
  if evidence.batch_id() != batch.id() {
    raise BatchMismatch
  }
  if evidence.parent() != batch.policy() || candidate.parent() != batch.policy() {
    raise PolicyMismatch
  }
  if evidence.target() != candidate.target() ||
    evidence.candidate_digest() != candidate.artifact_digest() {
    raise CandidateMismatch
  }
  { request_id: request.id(), evidence, candidate, }
}

///|
pub fn TrainerStepResult::request_id(self : Self) -> TrainingRequestId {
  self.request_id
}

///|
pub fn TrainerStepResult::evidence(
  self : Self,
) -> @update.OptimizerStepEvidence {
  self.evidence
}

///|
pub fn TrainerStepResult::candidate(self : Self) -> @update.CandidatePolicy {
  self.candidate
}

///|
pub(all) enum TrainerFailure {
  BackendUnavailable
  ResourceExhausted
  NumericalFailure
  Cancelled
} derive(Debug, Eq)

///|
pub(all) enum TrainerState {
  Prepared
  Dispatched
  ResultAccepted
  Completed
  Failed
} derive(Debug, Eq)

///|
pub struct TrainerTransaction {
  priv request : TrainingRequest
  priv mut state : TrainerState
  priv mut result : TrainerStepResult?
  priv mut failure : TrainerFailure?
}

///|
pub fn TrainerTransaction::new(request : TrainingRequest) -> Self {
  { request, state: Prepared, result: None, failure: None, }
}

///|
fn TrainerTransaction::require_state(
  self : Self,
  expected : TrainerState,
) -> Unit raise TrainerProtocolError {
  if self.state != expected {
    raise InvalidState(expected~, actual=self.state)
  }
}

///|
pub fn TrainerTransaction::dispatch(
  self : Self,
) -> Unit raise TrainerProtocolError {
  self.require_state(Prepared)
  self.state = Dispatched
}

///|
pub fn TrainerTransaction::accept_result(
  self : Self,
  result : TrainerStepResult,
) -> Unit raise TrainerProtocolError {
  self.require_state(Dispatched)
  if result.request_id() != self.request.id() {
    raise BatchMismatch
  }
  let batch = self.request.batch()
  if result.evidence().batch_id() != batch.id() {
    raise BatchMismatch
  }
  if result.candidate().parent() != batch.policy() {
    raise PolicyMismatch
  }
  self.result = Some(result)
  self.state = ResultAccepted
}

///|
pub fn TrainerTransaction::complete(
  self : Self,
) -> Unit raise TrainerProtocolError {
  self.require_state(ResultAccepted)
  self.state = Completed
}

///|
pub fn TrainerTransaction::fail(
  self : Self,
  failure : TrainerFailure,
) -> Unit raise TrainerProtocolError {
  if self.state != Prepared && self.state != Dispatched {
    raise InvalidState(expected=Dispatched, actual=self.state)
  }
  self.failure = Some(failure)
  self.state = Failed
}

///|
pub fn TrainerTransaction::request(self : Self) -> TrainingRequest {
  self.request
}

///|
pub fn TrainerTransaction::state(self : Self) -> TrainerState {
  self.state
}

///|
pub fn TrainerTransaction::result(self : Self) -> TrainerStepResult? {
  self.result
}

///|
pub fn TrainerTransaction::failure(self : Self) -> TrainerFailure? {
  self.failure
}

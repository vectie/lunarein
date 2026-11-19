///|
pub struct CandidatePolicy {
  priv parent : @identity.PolicyGeneration
  priv target : @identity.PolicyGeneration
  priv artifact_digest : @identity.Sha256Digest
  priv tensor_vocabulary_digest : @identity.Sha256Digest
}

///|
pub fn CandidatePolicy::new(
  parent~ : @identity.PolicyGeneration,
  target~ : @identity.PolicyGeneration,
  artifact_digest~ : @identity.Sha256Digest,
  tensor_vocabulary_digest~ : @identity.Sha256Digest,
) -> Self raise UpdateError {
  if !target.follows(parent) {
    raise BrokenPolicyLineage
  }
  if target.actor() != artifact_digest {
    raise CandidateDigestMismatch
  }
  { parent, target, artifact_digest, tensor_vocabulary_digest, }
}

///|
pub fn CandidatePolicy::parent(self : Self) -> @identity.PolicyGeneration {
  self.parent
}

///|
pub fn CandidatePolicy::target(self : Self) -> @identity.PolicyGeneration {
  self.target
}

///|
pub fn CandidatePolicy::artifact_digest(self : Self) -> @identity.Sha256Digest {
  self.artifact_digest
}

///|
pub fn CandidatePolicy::tensor_vocabulary_digest(
  self : Self,
) -> @identity.Sha256Digest {
  self.tensor_vocabulary_digest
}

///|
pub struct OptimizerStepEvidence {
  priv step_id : OptimizerStepId
  priv batch_id : TrainingBatchId
  priv parent : @identity.PolicyGeneration
  priv target : @identity.PolicyGeneration
  priv candidate_digest : @identity.Sha256Digest
  priv optimizer_state_digest : @identity.Sha256Digest
  priv trained_token_count : Int32
  priv mean_loss : Double
}

///|
pub fn OptimizerStepEvidence::new(
  step_id~ : OptimizerStepId,
  batch~ : TrainingBatch,
  candidate~ : CandidatePolicy,
  optimizer_state_digest~ : @identity.Sha256Digest,
  trained_token_count~ : Int32,
  mean_loss~ : Double,
) -> Self raise UpdateError {
  if candidate.parent() != batch.policy() {
    raise ForeignPolicy
  }
  if trained_token_count != batch.trainable_token_count() {
    raise StepTokenMismatch
  }
  if mean_loss.is_nan() || mean_loss.is_inf() {
    raise NonFiniteMeanLoss
  }
  {
    step_id,
    batch_id: batch.id(),
    parent: batch.policy(),
    target: candidate.target(),
    candidate_digest: candidate.artifact_digest(),
    optimizer_state_digest,
    trained_token_count,
    mean_loss,
  }
}

///|
pub fn OptimizerStepEvidence::step_id(self : Self) -> OptimizerStepId {
  self.step_id
}

///|
pub fn OptimizerStepEvidence::batch_id(self : Self) -> TrainingBatchId {
  self.batch_id
}

///|
pub fn OptimizerStepEvidence::parent(self : Self) -> @identity.PolicyGeneration {
  self.parent
}

///|
pub fn OptimizerStepEvidence::target(self : Self) -> @identity.PolicyGeneration {
  self.target
}

///|
pub fn OptimizerStepEvidence::candidate_digest(
  self : Self,
) -> @identity.Sha256Digest {
  self.candidate_digest
}

///|
pub fn OptimizerStepEvidence::optimizer_state_digest(
  self : Self,
) -> @identity.Sha256Digest {
  self.optimizer_state_digest
}

///|
pub fn OptimizerStepEvidence::trained_token_count(self : Self) -> Int32 {
  self.trained_token_count
}

///|
pub fn OptimizerStepEvidence::mean_loss(self : Self) -> Double {
  self.mean_loss
}

///|
pub(all) suberror UpdateError {
  InvalidBatchId
  InvalidStepId
  InvalidLimit
  InvalidTokenCount
  EmptyBatch
  ForeignPolicy
  DuplicateRollout
  NonCanonicalRolloutOrder
  TotalTokenLimitExceeded
  TrainableTokenLimitExceeded
  BrokenPolicyLineage
  CandidateDigestMismatch
  StepTokenMismatch
  NonFiniteMeanLoss
  NonFiniteTrainingTarget(index~ : Int32)
  NonzeroEnvironmentTarget(index~ : Int32)
} derive(Debug, Eq)

///|
#valtype
pub struct TrainingBatchId {
  priv value : UInt64
} derive(Debug, Eq)

///|
pub fn TrainingBatchId::new(value : UInt64) -> Self raise UpdateError {
  if value == 0UL {
    raise InvalidBatchId
  }
  { value, }
}

///|
pub fn TrainingBatchId::value(self : Self) -> UInt64 {
  self.value
}

///|
#valtype
pub struct OptimizerStepId {
  priv value : UInt64
} derive(Debug, Eq)

///|
pub fn OptimizerStepId::new(value : UInt64) -> Self raise UpdateError {
  if value == 0UL {
    raise InvalidStepId
  }
  { value, }
}

///|
pub fn OptimizerStepId::value(self : Self) -> UInt64 {
  self.value
}

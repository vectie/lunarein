///|
pub struct ExperimentManifest {
  priv identity : ExperimentIdentity
  priv actor : @identity.PolicyGeneration
  priv dataset : DatasetIdentity
  priv reward_policy : RewardPolicyIdentity
  priv tokenizer : TokenizerIdentity
  priv algorithm : AlgorithmIdentity
  priv limits : ExperimentLimits
} derive(Debug, Eq)

///|
pub fn ExperimentManifest::new(
  identity~ : ExperimentIdentity,
  actor~ : @identity.PolicyGeneration,
  dataset~ : DatasetIdentity,
  reward_policy~ : RewardPolicyIdentity,
  tokenizer~ : TokenizerIdentity,
  algorithm~ : AlgorithmIdentity,
  limits~ : ExperimentLimits,
) -> Self {
  { identity, actor, dataset, reward_policy, tokenizer, algorithm, limits, }
}

///|
pub fn ExperimentManifest::identity(self : Self) -> ExperimentIdentity {
  self.identity
}

///|
pub fn ExperimentManifest::actor(self : Self) -> @identity.PolicyGeneration {
  self.actor
}

///|
pub fn ExperimentManifest::dataset(self : Self) -> DatasetIdentity {
  self.dataset
}

///|
pub fn ExperimentManifest::reward_policy(self : Self) -> RewardPolicyIdentity {
  self.reward_policy
}

///|
pub fn ExperimentManifest::tokenizer(self : Self) -> TokenizerIdentity {
  self.tokenizer
}

///|
pub fn ExperimentManifest::algorithm(self : Self) -> AlgorithmIdentity {
  self.algorithm
}

///|
pub fn ExperimentManifest::limits(self : Self) -> ExperimentLimits {
  self.limits
}

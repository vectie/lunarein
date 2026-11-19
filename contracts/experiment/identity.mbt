///|
pub struct ExperimentIdentity {
  priv digest : @identity.Sha256Digest
} derive(Debug, Eq)

///|
pub fn ExperimentIdentity::new(digest : @identity.Sha256Digest) -> Self {
  { digest, }
}

///|
pub fn ExperimentIdentity::digest(self : Self) -> @identity.Sha256Digest {
  self.digest
}

///|
pub struct DatasetIdentity {
  priv digest : @identity.Sha256Digest
} derive(Debug, Eq)

///|
pub fn DatasetIdentity::new(digest : @identity.Sha256Digest) -> Self {
  { digest, }
}

///|
pub fn DatasetIdentity::digest(self : Self) -> @identity.Sha256Digest {
  self.digest
}

///|
pub struct RewardPolicyIdentity {
  priv digest : @identity.Sha256Digest
} derive(Debug, Eq)

///|
pub fn RewardPolicyIdentity::new(digest : @identity.Sha256Digest) -> Self {
  { digest, }
}

///|
pub fn RewardPolicyIdentity::digest(self : Self) -> @identity.Sha256Digest {
  self.digest
}

///|
pub struct TokenizerIdentity {
  priv digest : @identity.Sha256Digest
} derive(Debug, Eq)

///|
pub fn TokenizerIdentity::new(digest : @identity.Sha256Digest) -> Self {
  { digest, }
}

///|
pub fn TokenizerIdentity::digest(self : Self) -> @identity.Sha256Digest {
  self.digest
}

///|
pub(all) enum AlgorithmKind {
  Reinforce
  ReinforceReferenceKl
  Grpo
  GaePpo
} derive(Debug, Eq)

///|
pub struct AlgorithmIdentity {
  priv digest : @identity.Sha256Digest
  priv kind : AlgorithmKind
} derive(Debug, Eq)

///|
pub fn AlgorithmIdentity::new(
  digest : @identity.Sha256Digest,
  kind : AlgorithmKind,
) -> Self {
  { digest, kind, }
}

///|
pub fn AlgorithmIdentity::kind(self : Self) -> AlgorithmKind {
  self.kind
}

///|
pub fn AlgorithmIdentity::digest(self : Self) -> @identity.Sha256Digest {
  self.digest
}

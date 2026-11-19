///|
/// Content identity of an immutable rollout-group request.
pub struct RolloutRequestId {
  priv digest : @identity.Sha256Digest
} derive(Debug, Eq)

///|
pub fn RolloutRequestId::new(digest : @identity.Sha256Digest) -> Self {
  { digest, }
}

///|
pub fn RolloutRequestId::digest(self : Self) -> @identity.Sha256Digest {
  self.digest
}

///|
/// Content identity of an immutable teacher-forcing request.
pub struct ScoreRequestId {
  priv digest : @identity.Sha256Digest
} derive(Debug, Eq)

///|
pub fn ScoreRequestId::new(digest : @identity.Sha256Digest) -> Self {
  { digest, }
}

///|
pub fn ScoreRequestId::digest(self : Self) -> @identity.Sha256Digest {
  self.digest
}

///|
/// A deterministic sampling plan binds the content-addressed sampling
/// algorithm/configuration to the seed used for one rollout slot.
pub struct SamplingIdentity {
  priv plan_digest : @identity.Sha256Digest
  priv seed : UInt64
} derive(Debug, Eq)

///|
pub fn SamplingIdentity::new(
  plan_digest~ : @identity.Sha256Digest,
  seed~ : UInt64,
) -> Self {
  { plan_digest, seed, }
}

///|
pub fn SamplingIdentity::plan_digest(self : Self) -> @identity.Sha256Digest {
  self.plan_digest
}

///|
pub fn SamplingIdentity::seed(self : Self) -> UInt64 {
  self.seed
}

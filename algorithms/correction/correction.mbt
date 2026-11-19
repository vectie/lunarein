///|
pub(all) suberror CorrectionError {
  InvalidBounds
  LengthMismatch
  EvidenceIdentityMismatch
  MissingTargetLogprob(index~ : Int32)
  UnexpectedTargetLogprob(index~ : Int32)
  InvalidTargetLogprob(index~ : Int32)
  MissingBehaviorLogprob(index~ : Int32)
  InvalidBehaviorLogprob(index~ : Int32)
  UnsafeRatio(index~ : Int32, ratio~ : Double)
  InvalidIndex(index~ : Int32)
  Trajectory(@trajectory.TrajectoryError)
} derive(Debug, Eq)

///|
/// The denominator is explicit because actor-model and actual sampling
/// probabilities have different meanings and cannot substitute silently.
pub(all) enum CorrectionDenominator {
  BehaviorModel
  SamplingDistribution
} derive(Debug, Eq)

///|
pub struct ImportanceBounds {
  priv minimum_ratio : Double
  priv maximum_ratio : Double
  priv denominator : CorrectionDenominator
} derive(Debug, Eq)

///|
pub fn ImportanceBounds::new(
  minimum_ratio~ : Double,
  maximum_ratio~ : Double,
  denominator~ : CorrectionDenominator,
) -> Self raise CorrectionError {
  if minimum_ratio.is_nan() ||
    minimum_ratio.is_inf() ||
    maximum_ratio.is_nan() ||
    maximum_ratio.is_inf() ||
    minimum_ratio <= 0.0 ||
    minimum_ratio > 1.0 ||
    maximum_ratio < 1.0 ||
    minimum_ratio > maximum_ratio {
    raise InvalidBounds
  }
  { minimum_ratio, maximum_ratio, denominator, }
}

///|
pub fn ImportanceBounds::minimum_ratio(self : Self) -> Double {
  self.minimum_ratio
}

///|
pub fn ImportanceBounds::maximum_ratio(self : Self) -> Double {
  self.maximum_ratio
}

///|
pub fn ImportanceBounds::denominator(self : Self) -> CorrectionDenominator {
  self.denominator
}

///|
/// Response-aligned importance ratios. Environment-token positions are absent;
/// model-token positions are finite, positive, and within the declared bounds.
pub struct ImportanceCorrectionEvidence {
  priv trajectory : @trajectory.TrajectoryEvidenceIdentity
  priv staleness : @staleness.StalenessEvidence
  priv denominator : CorrectionDenominator
  priv ratios : ReadOnlyArray[Double?]
}

///|
pub fn ImportanceCorrectionEvidence::new(
  trajectory : @trajectory.Trajectory,
  staleness : @staleness.StalenessEvidence,
  target_scores : @reward.PolicyScoreEvidence,
  bounds : ImportanceBounds,
) -> Self raise CorrectionError {
  if staleness.source() != trajectory.policy() ||
    !target_scores.trajectory_identity().matches_trajectory(trajectory) ||
    target_scores.source_policy() != trajectory.policy() ||
    target_scores.target_policy() != staleness.target() ||
    target_scores.token_count() != trajectory.response_length() {
    raise EvidenceIdentityMismatch
  }
  let ratios : Array[Double?] = []
  for index in 0..<trajectory.response_length() {
    let token = trajectory.response_token_at(index) catch {
      error => raise Trajectory(error)
    }
    if token.is_trainable() {
      let behavior = match bounds.denominator() {
        BehaviorModel => token.model_logprob()
        SamplingDistribution => token.sampling_logprob()
      }
      guard behavior is Some(behavior_logprob) else {
        raise MissingBehaviorLogprob(index~)
      }
      if behavior_logprob.is_nan() ||
        behavior_logprob.is_inf() ||
        behavior_logprob > 0.0 {
        raise InvalidBehaviorLogprob(index~)
      }
      let target_score = target_scores.logprob_at(index) catch {
        _ => raise InvalidIndex(index~)
      }
      guard target_score is Some(target_logprob) else {
        raise MissingTargetLogprob(index~)
      }
      let ratio = @math.exp(target_logprob - behavior_logprob)
      if ratio.is_nan() ||
        ratio.is_inf() ||
        ratio <= 0.0 ||
        ratio < bounds.minimum_ratio() ||
        ratio > bounds.maximum_ratio() {
        raise UnsafeRatio(index~, ratio~)
      }
      ratios.push(Some(ratio))
    } else {
      let target_score = target_scores.logprob_at(index) catch {
        _ => raise InvalidIndex(index~)
      }
      if target_score is Some(_) {
        raise UnexpectedTargetLogprob(index~)
      }
      ratios.push(None)
    }
  }
  {
    trajectory: trajectory.evidence_identity(),
    staleness,
    denominator: bounds.denominator(),
    ratios: ReadOnlyArray::from_array(ratios),
  }
}

///|
pub fn ImportanceCorrectionEvidence::rollout_id(
  self : Self,
) -> @identity.RolloutId {
  self.trajectory.rollout_id()
}

///|
pub fn ImportanceCorrectionEvidence::trajectory_identity(
  self : Self,
) -> @trajectory.TrajectoryEvidenceIdentity {
  self.trajectory
}

///|
pub fn ImportanceCorrectionEvidence::source_policy(
  self : Self,
) -> @identity.PolicyGeneration {
  self.staleness.source()
}

///|
pub fn ImportanceCorrectionEvidence::target_policy(
  self : Self,
) -> @identity.PolicyGeneration {
  self.staleness.target()
}

///|
pub fn ImportanceCorrectionEvidence::generations(self : Self) -> Int32 {
  self.staleness.generations()
}

///|
pub fn ImportanceCorrectionEvidence::staleness(
  self : Self,
) -> @staleness.StalenessEvidence {
  self.staleness
}

///|
pub fn ImportanceCorrectionEvidence::denominator(
  self : Self,
) -> CorrectionDenominator {
  self.denominator
}

///|
pub fn ImportanceCorrectionEvidence::token_count(self : Self) -> Int32 {
  self.ratios.length()
}

///|
pub fn ImportanceCorrectionEvidence::ratio_at(
  self : Self,
  index : Int32,
) -> Double? raise CorrectionError {
  if index < 0 || index >= self.ratios.length() {
    raise InvalidIndex(index~)
  }
  self.ratios[index]
}

///|
/// Exact policy-gradient targets after applying bounded importance ratios.
/// The output retains both the source trajectory identity and target policy;
/// it cannot be relabeled as ordinary on-policy advantage evidence.
pub struct CorrectedAdvantageEvidence {
  priv source : @advantage.AdvantageEvidence
  priv correction : ImportanceCorrectionEvidence
  priv item : @update.TrainingItemRef
}

///|
pub fn CorrectedAdvantageEvidence::new(
  source : @advantage.AdvantageEvidence,
  correction : ImportanceCorrectionEvidence,
) -> Self raise CorrectionError {
  if !source.trajectory_identity().same(correction.trajectory_identity()) ||
    source.policy() != correction.source_policy() ||
    source.token_count() != correction.token_count() {
    raise EvidenceIdentityMismatch
  }
  let values = Array::make(source.token_count(), 0.0)
  for index in 0..<source.token_count() {
    let source_value = source.value_at(index) catch {
      _ => raise InvalidIndex(index~)
    }
    match correction.ratio_at(index) {
      Some(ratio) => values[index] = source_value * ratio
      None => if source_value != 0.0 { raise EvidenceIdentityMismatch }
    }
  }
  let item = @update.TrainingItemRef::corrected(
    trajectory=source.trajectory_identity(),
    training_policy=correction.target_policy(),
    target_values=values,
  ) catch {
    _ => raise EvidenceIdentityMismatch
  }
  { source, correction, item, }
}

///|
pub fn CorrectedAdvantageEvidence::rollout_id(
  self : Self,
) -> @identity.RolloutId {
  self.source.rollout_id()
}

///|
pub fn CorrectedAdvantageEvidence::source_policy(
  self : Self,
) -> @identity.PolicyGeneration {
  self.correction.source_policy()
}

///|
pub fn CorrectedAdvantageEvidence::target_policy(
  self : Self,
) -> @identity.PolicyGeneration {
  self.correction.target_policy()
}

///|
pub fn CorrectedAdvantageEvidence::staleness(
  self : Self,
) -> @staleness.StalenessEvidence {
  self.correction.staleness()
}

///|
pub fn CorrectedAdvantageEvidence::trajectory_identity(
  self : Self,
) -> @trajectory.TrajectoryEvidenceIdentity {
  self.source.trajectory_identity()
}

///|
pub fn CorrectedAdvantageEvidence::reward_source(
  self : Self,
) -> @reward.RewardSourceId {
  self.source.reward_source()
}

///|
pub fn CorrectedAdvantageEvidence::algorithm(
  self : Self,
) -> @experiment.AlgorithmIdentity {
  self.source.algorithm()
}

///|
pub fn CorrectedAdvantageEvidence::training_item(
  self : Self,
) -> @update.TrainingItemRef {
  self.item
}

///|
pub fn CorrectedAdvantageEvidence::matches_training_item(
  self : Self,
  item : @update.TrainingItemRef,
) -> Bool {
  if item.policy() != self.item.policy() ||
    !item.trajectory_identity().same(self.item.trajectory_identity()) ||
    item.token_count() != self.item.token_count() ||
    item.trainable_token_count() != self.item.trainable_token_count() ||
    item.has_value_returns() {
    return false
  }
  for index in 0..<item.token_count() {
    let left = item.target_value_at(index) catch { _ => return false }
    let right = self.item.target_value_at(index) catch { _ => return false }
    if left != right {
      return false
    }
  }
  true
}

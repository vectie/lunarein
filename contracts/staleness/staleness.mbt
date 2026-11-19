///|
pub(all) suberror StalenessError {
  InvalidMaximum
  EmptyLineage
  SourceMismatch
  TargetMismatch
  BrokenLineage(index~ : Int32)
  ExceedsMaximum(actual~ : Int32, maximum~ : Int32)
  InvalidIndex(index~ : Int32)
} derive(Debug, Eq)

///|
/// A startup-bounded policy for admitting evidence produced by an older actor.
/// Zero permits only on-policy evidence. The hard upper bound keeps every
/// lineage witness and coordinator using this policy structurally bounded.
pub struct StalenessPolicy {
  priv maximum_generations : Int32
} derive(Debug, Eq)

///|
pub fn StalenessPolicy::new(
  maximum_generations : Int32,
) -> Self raise StalenessError {
  if maximum_generations < 0 || maximum_generations > 1024 {
    raise InvalidMaximum
  }
  { maximum_generations, }
}

///|
pub fn StalenessPolicy::maximum_generations(self : Self) -> Int32 {
  self.maximum_generations
}

///|
/// Immutable proof that `source` reaches `target` through immediate policy
/// successors and fits this policy's bound. The lineage includes both ends.
pub struct StalenessEvidence {
  priv source : @identity.PolicyGeneration
  priv target : @identity.PolicyGeneration
  priv lineage : ReadOnlyArray[@identity.PolicyGeneration]
  priv generations : Int32
} derive(Debug, Eq)

///|
pub fn StalenessPolicy::evaluate(
  self : Self,
  source~ : @identity.PolicyGeneration,
  target~ : @identity.PolicyGeneration,
  lineage~ : ArrayView[@identity.PolicyGeneration],
) -> StalenessEvidence raise StalenessError {
  if lineage.is_empty() {
    raise EmptyLineage
  }
  if lineage.length() > self.maximum_generations + 1 {
    raise ExceedsMaximum(
      actual=lineage.length() - 1,
      maximum=self.maximum_generations,
    )
  }
  if lineage[0] != source {
    raise SourceMismatch
  }
  let last_index = lineage.length() - 1
  if lineage[last_index] != target {
    raise TargetMismatch
  }
  for index in 1..<lineage.length() {
    if !lineage[index].follows(lineage[index - 1]) {
      raise BrokenLineage(index~)
    }
  }
  let generations = last_index
  { source, target, lineage: ReadOnlyArray::from_array(lineage), generations, }
}

///|
pub fn StalenessEvidence::source(self : Self) -> @identity.PolicyGeneration {
  self.source
}

///|
pub fn StalenessEvidence::target(self : Self) -> @identity.PolicyGeneration {
  self.target
}

///|
pub fn StalenessEvidence::generations(self : Self) -> Int32 {
  self.generations
}

///|
pub fn StalenessEvidence::requires_correction(self : Self) -> Bool {
  self.generations > 0
}

///|
pub fn StalenessEvidence::lineage_length(self : Self) -> Int32 {
  self.lineage.length()
}

///|
pub fn StalenessEvidence::generation_at(
  self : Self,
  index : Int32,
) -> @identity.PolicyGeneration raise StalenessError {
  if index < 0 || index >= self.lineage.length() {
    raise InvalidIndex(index~)
  }
  self.lineage[index]
}

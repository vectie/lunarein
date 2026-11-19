///|
fn digest(byte : String) -> @identity.Sha256Digest {
  try! @identity.Sha256Digest::parse(byte.repeat(64))
}

///|
fn generations() -> (
  @identity.PolicyGeneration,
  @identity.PolicyGeneration,
  @identity.PolicyGeneration,
) {
  let first = @identity.PolicyGeneration::initial(digest("a"))
  let second = try! @identity.PolicyGeneration::new(
    sequence=2UL,
    actor=digest("b"),
    parent_actor=Some(first.actor()),
  )
  let third = try! @identity.PolicyGeneration::new(
    sequence=3UL,
    actor=digest("c"),
    parent_actor=Some(second.actor()),
  )
  (first, second, third)
}

///|
test "on-policy and bounded stale lineage are explicit" {
  let (first, second, third) = generations()
  let on_policy = @staleness.StalenessPolicy::new(0).evaluate(
    source=first,
    target=first,
    lineage=[first],
  )
  assert_eq(on_policy.generations(), 0)
  assert_false(on_policy.requires_correction())
  let bounded = @staleness.StalenessPolicy::new(2).evaluate(
    source=first,
    target=third,
    lineage=[first, second, third],
  )
  assert_eq(bounded.generations(), 2)
  assert_true(bounded.requires_correction())
  assert_eq(bounded.lineage_length(), 3)
  assert_eq(bounded.generation_at(1), second)
}

///|
test "lineage endpoints and every immediate successor fail closed" {
  let (first, second, third) = generations()
  let policy = @staleness.StalenessPolicy::new(2)
  try
    policy.evaluate(source=second, target=third, lineage=[first, second, third])
  catch {
    SourceMismatch => ()
    _ => fail("unexpected source mismatch error")
  } noraise {
    _ => fail("substituted source was accepted")
  }
  try
    policy.evaluate(source=first, target=second, lineage=[first, second, third])
  catch {
    TargetMismatch => ()
    _ => fail("unexpected target mismatch error")
  } noraise {
    _ => fail("substituted target was accepted")
  }
  try
    policy.evaluate(source=first, target=third, lineage=[first, third])
  catch {
    BrokenLineage(index=1) => ()
    _ => fail("unexpected broken-lineage error")
  } noraise {
    _ => fail("skipped generation was accepted")
  }
}

///|
test "staleness and storage bounds are enforced before evidence creation" {
  let (first, second, third) = generations()
  try
    @staleness.StalenessPolicy::new(1).evaluate(source=first, target=third, lineage=[
      first, second, third,
    ])
  catch {
    ExceedsMaximum(actual=2, maximum=1) => ()
    _ => fail("unexpected maximum-staleness error")
  } noraise {
    _ => fail("over-stale evidence was accepted")
  }
  try @staleness.StalenessPolicy::new(1025) catch {
    InvalidMaximum => ()
    _ => fail("unexpected policy-bound error")
  } noraise {
    _ => fail("unbounded policy was accepted")
  }
}

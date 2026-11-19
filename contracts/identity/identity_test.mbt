///|
fn digest(byte : String) -> @identity.Sha256Digest {
  try! @identity.Sha256Digest::parse(byte.repeat(64))
}

///|
test "policy generations preserve exact lineage" {
  let first = @identity.PolicyGeneration::initial(digest("a"))
  let second = @identity.PolicyGeneration::new(
    sequence=2UL,
    actor=digest("b"),
    parent_actor=Some(first.actor()),
  )
  assert_true(second.follows(first))
  assert_eq(second.sequence(), 2UL)
  assert_false(first.follows(second))
}

///|
test "identity rejects malformed and ambiguous values" {
  try @identity.Sha256Digest::parse("A".repeat(64)) catch {
    InvalidDigestByte(index=0) => ()
    _ => fail("unexpected digest error")
  } noraise {
    _ => fail("uppercase digest was accepted")
  }
  try @identity.RolloutId::new(0UL) catch {
    InvalidRolloutId => ()
    _ => fail("unexpected rollout-id error")
  } noraise {
    _ => fail("zero rollout id was accepted")
  }
  try
    @identity.PolicyGeneration::new(
      sequence=2UL,
      actor=digest("b"),
      parent_actor=None,
    )
  catch {
    InvalidLineage => ()
    _ => fail("unexpected lineage error")
  } noraise {
    _ => fail("missing parent lineage was accepted")
  }
}

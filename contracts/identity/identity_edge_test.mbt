///|
test "identity accessors preserve canonical values" {
  let actor = @identity.Sha256Digest::parse("a".repeat(64))
  assert_eq(actor.as_string(), "a".repeat(64))
  let group = @identity.GroupId::new(7UL)
  assert_eq(group.value(), 7UL)
  let initial = @identity.PolicyGeneration::initial(actor)
  let next = @identity.PolicyGeneration::new(
    sequence=2UL,
    actor=@identity.Sha256Digest::parse("b".repeat(64)),
    parent_actor=Some(actor),
  )
  assert_eq(initial.parent_actor(), None)
  assert_eq(next.parent_actor(), Some(actor))
}

///|
test "identity rejects every invalid canonical form" {
  try @identity.Sha256Digest::parse("a".repeat(63)) catch {
    InvalidDigestLength => ()
    _ => fail("unexpected digest-length error")
  } noraise {
    _ => fail("short digest was accepted")
  }
  try @identity.GroupId::new(0UL) catch {
    InvalidGroupId => ()
    _ => fail("unexpected group-id error")
  } noraise {
    _ => fail("zero group id was accepted")
  }
  let actor = @identity.Sha256Digest::parse("a".repeat(64))
  try
    @identity.PolicyGeneration::new(sequence=0UL, actor~, parent_actor=None)
  catch {
    InvalidSequence => ()
    _ => fail("unexpected sequence error")
  } noraise {
    _ => fail("zero policy sequence was accepted")
  }
  try
    @identity.PolicyGeneration::new(
      sequence=1UL,
      actor~,
      parent_actor=Some(actor),
    )
  catch {
    InvalidLineage => ()
    _ => fail("unexpected initial-lineage error")
  } noraise {
    _ => fail("initial policy with a parent was accepted")
  }
}

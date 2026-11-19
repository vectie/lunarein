///|
test "v1 is explicit and exact" {
  let version = @version.ProtocolVersion::v1()
  assert_eq(version.major(), 1)
  assert_eq(version.minor(), 0)
  assert_true(version.is_exact(@version.ProtocolVersion::new(major=1, minor=0)))
  assert_false(
    version.is_exact(@version.ProtocolVersion::new(major=1, minor=1)),
  )
}

///|
test "zero major fails closed" {
  try @version.ProtocolVersion::new(major=0, minor=1) catch {
    InvalidMajor => ()
  } noraise {
    _ => fail("expected invalid major")
  }
}

///|
/// Version validation errors are deliberately small: a protocol package owns
/// compatibility policy, while this package owns only the version value.
pub(all) suberror VersionError {
  InvalidMajor
} derive(Debug, Eq)

///|
/// A protocol schema version. Version zero is reserved so an absent or
/// zero-initialized value cannot be mistaken for a negotiated schema.
#valtype
pub struct ProtocolVersion {
  priv major : UInt16
  priv minor : UInt16
} derive(Debug, Eq)

///|
pub fn ProtocolVersion::new(
  major~ : UInt16,
  minor~ : UInt16,
) -> Self raise VersionError {
  if major == 0 {
    raise InvalidMajor
  }
  { major, minor, }
}

///|
/// The first LunaRein protocol schema version.
pub fn ProtocolVersion::v1() -> Self {
  { major: 1, minor: 0, }
}

///|
pub fn ProtocolVersion::major(self : Self) -> UInt16 {
  self.major
}

///|
pub fn ProtocolVersion::minor(self : Self) -> UInt16 {
  self.minor
}

///|
/// Protocol packages use exact compatibility unless a future schema explicitly
/// defines a narrower compatibility rule.
pub fn ProtocolVersion::is_exact(self : Self, required : Self) -> Bool {
  self == required
}

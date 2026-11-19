///|
pub(all) suberror IdentityError {
  InvalidDigestLength
  InvalidDigestByte(index~ : Int32)
  InvalidSequence
  InvalidLineage
  InvalidRolloutId
  InvalidGroupId
} derive(Debug, Eq)

///|
pub struct Sha256Digest {
  priv value : String
} derive(Debug, Eq)

///|
fn is_lower_hex(character : Char) -> Bool {
  (character >= '0' && character <= '9') ||
  (character >= 'a' && character <= 'f')
}

///|
pub fn Sha256Digest::parse(value : String) -> Self raise IdentityError {
  if value.length() != 64 {
    raise InvalidDigestLength
  }
  for index in 0..<64 {
    guard value.get_char(index) is Some(character) && is_lower_hex(character) else {
      raise InvalidDigestByte(index~)
    }
  }
  { value, }
}

///|
pub fn Sha256Digest::as_string(self : Self) -> String {
  self.value
}

///|
#valtype
pub struct RolloutId {
  priv value : UInt64
} derive(Debug, Eq)

///|
pub fn RolloutId::new(value : UInt64) -> Self raise IdentityError {
  if value == 0UL {
    raise InvalidRolloutId
  }
  { value, }
}

///|
pub fn RolloutId::value(self : Self) -> UInt64 {
  self.value
}

///|
#valtype
pub struct GroupId {
  priv value : UInt64
} derive(Debug, Eq)

///|
pub fn GroupId::new(value : UInt64) -> Self raise IdentityError {
  if value == 0UL {
    raise InvalidGroupId
  }
  { value, }
}

///|
pub fn GroupId::value(self : Self) -> UInt64 {
  self.value
}

///|
pub struct PolicyGeneration {
  priv sequence : UInt64
  priv actor : Sha256Digest
  priv parent_actor : Sha256Digest?
} derive(Debug, Eq)

///|
pub fn PolicyGeneration::new(
  sequence~ : UInt64,
  actor~ : Sha256Digest,
  parent_actor~ : Sha256Digest?,
) -> Self raise IdentityError {
  if sequence == 0UL {
    raise InvalidSequence
  }
  if (sequence == 1UL && parent_actor is Some(_)) ||
    (sequence > 1UL && parent_actor is None) {
    raise InvalidLineage
  }
  { sequence, actor, parent_actor, }
}

///|
pub fn PolicyGeneration::initial(actor : Sha256Digest) -> Self {
  { sequence: 1UL, actor, parent_actor: None, }
}

///|
pub fn PolicyGeneration::sequence(self : Self) -> UInt64 {
  self.sequence
}

///|
pub fn PolicyGeneration::actor(self : Self) -> Sha256Digest {
  self.actor
}

///|
pub fn PolicyGeneration::parent_actor(self : Self) -> Sha256Digest? {
  self.parent_actor
}

///|
pub fn PolicyGeneration::follows(self : Self, previous : Self) -> Bool {
  previous.sequence != 0xffffffffffffffffUL &&
  self.sequence == previous.sequence + 1UL &&
  self.parent_actor == Some(previous.actor) &&
  self.actor != previous.actor
}

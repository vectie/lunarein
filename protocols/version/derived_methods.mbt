///|
pub extend VersionError with @debug.Debug::{to_repr}

///|
pub extend VersionError with Eq::{not_equal, equal}

///|
pub extend ProtocolVersion with @debug.Debug::{to_repr}

///|
pub extend ProtocolVersion with Eq::{not_equal, equal}

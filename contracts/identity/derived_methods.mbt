///|
pub extend IdentityError with @debug.Debug::{to_repr}

///|
pub extend IdentityError with Eq::{not_equal, equal}

///|
pub extend Sha256Digest with @debug.Debug::{to_repr}

///|
pub extend Sha256Digest with Eq::{not_equal, equal}

///|
pub extend RolloutId with @debug.Debug::{to_repr}

///|
pub extend RolloutId with Eq::{not_equal, equal}

///|
pub extend GroupId with @debug.Debug::{to_repr}

///|
pub extend GroupId with Eq::{not_equal, equal}

///|
pub extend PolicyGeneration with @debug.Debug::{to_repr}

///|
pub extend PolicyGeneration with Eq::{not_equal, equal}

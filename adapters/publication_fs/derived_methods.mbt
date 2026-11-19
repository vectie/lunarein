///|
pub extend PublicationFsOperation with @debug.Debug::{to_repr}

///|
pub extend PublicationFsOperation with Eq::{not_equal, equal}

///|
pub extend PublicationFsError with @debug.Debug::{to_repr}

///|
pub extend PublicationFsError with Eq::{not_equal, equal}

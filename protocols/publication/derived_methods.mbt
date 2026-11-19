///|
pub extend ReservationOutcome with @debug.Debug::{to_repr}

///|
pub extend ReservationOutcome with Eq::{not_equal, equal}

///|
pub extend PublicationError with @debug.Debug::{to_repr}

///|
pub extend PublicationError with Eq::{not_equal, equal}

///|
pub extend PublicationId with @debug.Debug::{to_repr}

///|
pub extend PublicationId with Eq::{not_equal, equal}

///|
pub extend PolicyArtifactFormat with @debug.Debug::{to_repr}

///|
pub extend PolicyArtifactFormat with Eq::{not_equal, equal}

///|
pub extend PublicationTransport with @debug.Debug::{to_repr}

///|
pub extend PublicationTransport with Eq::{not_equal, equal}

///|
pub extend PublicationState with @debug.Debug::{to_repr}

///|
pub extend PublicationState with Eq::{not_equal, equal}

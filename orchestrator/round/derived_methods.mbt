///|
pub extend RoundError with @debug.Debug::{to_repr}

///|
pub extend RoundError with Eq::{not_equal, equal}

///|
pub extend RoundState with @debug.Debug::{to_repr}

///|
pub extend RoundState with Eq::{not_equal, equal}

///|
pub extend RoundAbortReason with @debug.Debug::{to_repr}

///|
pub extend RoundAbortReason with Eq::{not_equal, equal}

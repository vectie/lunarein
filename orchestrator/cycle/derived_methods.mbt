///|
pub extend CycleError with @debug.Debug::{to_repr}

///|
pub extend CycleError with Eq::{not_equal, equal}

///|
pub extend CycleState with @debug.Debug::{to_repr}

///|
pub extend CycleState with Eq::{not_equal, equal}

///|
pub extend CycleAbortReason with @debug.Debug::{to_repr}

///|
pub extend CycleAbortReason with Eq::{not_equal, equal}

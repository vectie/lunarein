///|
pub extend TrajectoryError with @debug.Debug::{to_repr}

///|
pub extend TrajectoryError with Eq::{not_equal, equal}

///|
pub extend TokenOrigin with @debug.Debug::{to_repr}

///|
pub extend TokenOrigin with Eq::{not_equal, equal}

///|
pub extend TrajectoryTerminal with @debug.Debug::{to_repr}

///|
pub extend TrajectoryTerminal with Eq::{not_equal, equal}

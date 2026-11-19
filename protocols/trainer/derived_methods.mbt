///|
pub extend TrainerProtocolError with @debug.Debug::{to_repr}

///|
pub extend TrainerProtocolError with Eq::{not_equal, equal}

///|
pub extend TrainingRequestId with @debug.Debug::{to_repr}

///|
pub extend TrainingRequestId with Eq::{not_equal, equal}

///|
pub extend TrainerFailure with @debug.Debug::{to_repr}

///|
pub extend TrainerFailure with Eq::{not_equal, equal}

///|
pub extend TrainerState with @debug.Debug::{to_repr}

///|
pub extend TrainerState with Eq::{not_equal, equal}

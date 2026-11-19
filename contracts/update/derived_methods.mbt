///|
pub extend UpdateError with @debug.Debug::{to_repr}

///|
pub extend UpdateError with Eq::{not_equal, equal}

///|
pub extend TrainingBatchId with @debug.Debug::{to_repr}

///|
pub extend TrainingBatchId with Eq::{not_equal, equal}

///|
pub extend OptimizerStepId with @debug.Debug::{to_repr}

///|
pub extend OptimizerStepId with Eq::{not_equal, equal}

///|
pub extend PipelineError with @debug.Debug::{to_repr}

///|
pub extend PipelineError with Eq::{not_equal, equal}

///|
pub extend PipelineState with @debug.Debug::{to_repr}

///|
pub extend PipelineState with Eq::{not_equal, equal}

///|
pub extend RetirementOutcome with @debug.Debug::{to_repr}

///|
pub extend RetirementOutcome with Eq::{not_equal, equal}

///|
pub extend RetiredCycle with @debug.Debug::{to_repr}

///|
pub extend RetiredCycle with Eq::{not_equal, equal}

///|
pub extend GenerationSnapshot with @debug.Debug::{to_repr}

///|
pub extend GenerationSnapshot with Eq::{not_equal, equal}

///|
pub extend PipelineSnapshot with @debug.Debug::{to_repr}

///|
pub extend PipelineSnapshot with Eq::{not_equal, equal}

///|
pub extend QuiescentCheckpoint with @debug.Debug::{to_repr}

///|
pub extend QuiescentCheckpoint with Eq::{not_equal, equal}

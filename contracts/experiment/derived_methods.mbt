///|
pub extend CapacityKind with @debug.Debug::{to_repr}

///|
pub extend CapacityKind with Eq::{not_equal, equal}

///|
pub extend ExperimentError with @debug.Debug::{to_repr}

///|
pub extend ExperimentError with Eq::{not_equal, equal}

///|
pub extend ConcurrentGroupCapacity with @debug.Debug::{to_repr}

///|
pub extend ConcurrentGroupCapacity with Eq::{not_equal, equal}

///|
pub extend RolloutsPerGroupCapacity with @debug.Debug::{to_repr}

///|
pub extend RolloutsPerGroupCapacity with Eq::{not_equal, equal}

///|
pub extend PromptTokenCapacity with @debug.Debug::{to_repr}

///|
pub extend PromptTokenCapacity with Eq::{not_equal, equal}

///|
pub extend ResponseTokenCapacity with @debug.Debug::{to_repr}

///|
pub extend ResponseTokenCapacity with Eq::{not_equal, equal}

///|
pub extend PendingUpdateCapacity with @debug.Debug::{to_repr}

///|
pub extend PendingUpdateCapacity with Eq::{not_equal, equal}

///|
pub extend ExperimentLimits with @debug.Debug::{to_repr}

///|
pub extend ExperimentLimits with Eq::{not_equal, equal}

///|
pub extend ExperimentIdentity with @debug.Debug::{to_repr}

///|
pub extend ExperimentIdentity with Eq::{not_equal, equal}

///|
pub extend DatasetIdentity with @debug.Debug::{to_repr}

///|
pub extend DatasetIdentity with Eq::{not_equal, equal}

///|
pub extend RewardPolicyIdentity with @debug.Debug::{to_repr}

///|
pub extend RewardPolicyIdentity with Eq::{not_equal, equal}

///|
pub extend TokenizerIdentity with @debug.Debug::{to_repr}

///|
pub extend TokenizerIdentity with Eq::{not_equal, equal}

///|
pub extend AlgorithmKind with @debug.Debug::{to_repr}

///|
pub extend AlgorithmKind with Eq::{not_equal, equal}

///|
pub extend AlgorithmIdentity with @debug.Debug::{to_repr}

///|
pub extend AlgorithmIdentity with Eq::{not_equal, equal}

///|
pub extend ExperimentManifest with @debug.Debug::{to_repr}

///|
pub extend ExperimentManifest with Eq::{not_equal, equal}

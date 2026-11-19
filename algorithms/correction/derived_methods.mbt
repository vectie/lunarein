///|
pub extend CorrectionError with @debug.Debug::{to_repr}

///|
pub extend CorrectionError with Eq::{not_equal, equal}

///|
pub extend CorrectionDenominator with @debug.Debug::{to_repr}

///|
pub extend CorrectionDenominator with Eq::{not_equal, equal}

///|
pub extend ImportanceBounds with @debug.Debug::{to_repr}

///|
pub extend ImportanceBounds with Eq::{not_equal, equal}

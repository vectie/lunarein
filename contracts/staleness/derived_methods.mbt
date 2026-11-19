///|
pub extend StalenessError with @debug.Debug::{to_repr}

///|
pub extend StalenessError with Eq::{not_equal, equal}

///|
pub extend StalenessPolicy with @debug.Debug::{to_repr}

///|
pub extend StalenessPolicy with Eq::{not_equal, equal}

///|
pub extend StalenessEvidence with @debug.Debug::{to_repr}

///|
pub extend StalenessEvidence with Eq::{not_equal, equal}

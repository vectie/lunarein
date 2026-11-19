///|
/// Errors are structural and backend-neutral so adapters cannot leak runtime
/// vocabulary into the protocol contract.
pub(all) suberror RolloutProtocolError {
  UnsupportedVersion
  InvalidLimit
  EmptyPrompt
  InvalidPromptToken(index~ : Int32)
  EmptyRolloutSlots
  TooManyRolloutSlots
  InvalidSelectionPolicy
  DuplicateRolloutId(index~ : Int32)
  DuplicateSamplingIdentity(index~ : Int32)
  InvalidSlotIndex(index~ : Int32)
  UnknownRollout
  RequestIdentityMismatch
  GroupIdentityMismatch
  ActorIdentityMismatch
  TokenizerIdentityMismatch
  SamplingIdentityMismatch
  PromptMismatch
  ResponseTooLong
  ResponseTokenOutOfRange(index~ : Int32)
  TerminalMismatch
  IneligibleForScoring
  NoTrainableTokens
  ScoreIdentityMismatch
  ScoreLengthMismatch
  InvalidScoreLogProbability(index~ : Int32)
  ScoreOriginMismatch(index~ : Int32)
  ScoreTargetMismatch
  Reward(@reward.RewardError)
  Trajectory(@trajectory.TrajectoryError)
} derive(Debug, Eq)

///|
fn require_supported_version(
  version : @version.ProtocolVersion,
) -> Unit raise RolloutProtocolError {
  if !version.is_exact(@version.ProtocolVersion::v1()) {
    raise UnsupportedVersion
  }
}

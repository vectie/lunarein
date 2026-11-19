///|
pub(all) enum PublicationFsOperation {
  Open
  InspectExisting
  WriteChunk
  Publish
  Cleanup
} derive(Debug, Eq)

///|
pub(all) suberror PublicationFsError {
  Closed
  InvalidDigestEncoding
  ChunkEvidenceMismatch
  ChunkLengthMismatch
  DuplicateChunk
  UnexpectedProtocolState
  PhysicalTargetConflict
  NativeFailure(operation~ : PublicationFsOperation, status~ : Int32)
  Protocol(@publication.PublicationError)
} derive(Debug, Eq)

///|
fn fail_native(
  operation : PublicationFsOperation,
  status : Int32,
) -> Unit raise PublicationFsError {
  raise NativeFailure(operation~, status~)
}

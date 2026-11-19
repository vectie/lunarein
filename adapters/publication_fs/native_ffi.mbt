///|
type NativePublicationSession

///|
#borrow(root, final_name, staging_name, lock_name, status)
extern "c" fn raw_open_session(
  root : Bytes,
  final_name : Bytes,
  staging_name : Bytes,
  lock_name : Bytes,
  status : Ref[Int32],
) -> NativePublicationSession = "lunarein_publication_fs_open"

///|
#borrow(session, expected_digest, expected_metadata, status)
extern "c" fn raw_inspect_existing(
  session : NativePublicationSession,
  expected_size : Int64,
  expected_digest : Bytes,
  expected_metadata : Bytes,
  status : Ref[Int32],
) -> Bytes = "lunarein_publication_fs_inspect_existing"

///|
#borrow(session, data, expected_digest)
extern "c" fn raw_write_chunk(
  session : NativePublicationSession,
  offset : Int64,
  data : Bytes,
  expected_digest : Bytes,
) -> Int32 = "lunarein_publication_fs_write_chunk"

///|
#borrow(session, expected_digest, metadata)
extern "c" fn raw_publish(
  session : NativePublicationSession,
  expected_size : Int64,
  expected_digest : Bytes,
  metadata : Bytes,
) -> Int32 = "lunarein_publication_fs_publish"

///|
#borrow(session)
extern "c" fn raw_discard_staging(session : NativePublicationSession) -> Int32 = "lunarein_publication_fs_discard_staging"

///|
#borrow(session)
extern "c" fn raw_close_session(session : NativePublicationSession) -> Int32 = "lunarein_publication_fs_close"

///|
#borrow(session)
extern "c" fn raw_session_is_closed(session : NativePublicationSession) -> Bool = "lunarein_publication_fs_is_closed"

///|
#borrow(data)
extern "c" fn raw_sha256_bytes(data : Bytes) -> Bytes = "lunarein_publication_fs_sha256_bytes"

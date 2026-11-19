///|
pub struct PublicationFs {
  priv manifest : @publication.FullArtifactManifest
  priv owner : @publication.PublicationOwner
  priv session : NativePublicationSession
  priv chunks_written : FixedArray[Bool]
  priv mut physically_published : Bool
  priv mut closed : Bool
}

///|
fn parse_native_digest(
  bytes : Bytes,
) -> @identity.Sha256Digest raise PublicationFsError {
  @identity.Sha256Digest::parse(@utf8.decode_lossy(bytes)) catch {
    _ => raise InvalidDigestEncoding
  }
}

///|
pub fn sha256_bytes(data : Bytes) -> @identity.Sha256Digest {
  try! parse_native_digest(raw_sha256_bytes(data))
}

///|
fn digest_bytes(digest : @identity.Sha256Digest) -> Bytes {
  @utf8.encode(digest.as_string())
}

///|
fn metadata_record(manifest : @publication.FullArtifactManifest) -> Bytes {
  let candidate = manifest.candidate()
  let record =
    $|version=1
    $|format=safetensors-v1
    $|artifact_sha256=\{candidate.artifact_digest().as_string()}
    $|parent_sha256=\{candidate.parent().actor().as_string()}
    $|target_sequence=\{candidate.target().sequence()}
    $|target_sha256=\{candidate.target().actor().as_string()}
    $|tensor_vocabulary_sha256=\{candidate.tensor_vocabulary_digest().as_string()}
    $|total_bytes=\{manifest.total_bytes()}
  @utf8.encode(record)
}

///|
fn publication_final_name(
  manifest : @publication.FullArtifactManifest,
) -> Bytes {
  @utf8.encode(
    "policy-\{manifest.target().sequence()}-\{manifest.artifact_digest().as_string()}",
  )
}

///|
fn close_after_open_failure(session : NativePublicationSession) -> Unit {
  ignore(raw_close_session(session))
}

///|
fn PublicationFs::require_open(self : Self) -> Unit raise PublicationFsError {
  if self.closed || raw_session_is_closed(self.session) {
    raise Closed
  }
}

///|
pub fn PublicationFs::open(
  root : String,
  manifest : @publication.FullArtifactManifest,
) -> Self raise PublicationFsError {
  let digest = manifest.artifact_digest().as_string()
  let final_name = publication_final_name(manifest)
  let staging_name = @utf8.encode(".policy-\{digest}.staging")
  let lock_name = @utf8.encode(".policy-\{digest}.lock")
  let status = Ref(0)
  let session = raw_open_session(
    @utf8.encode(root),
    final_name,
    staging_name,
    lock_name,
    status,
  )
  if status.val < 0 {
    close_after_open_failure(session)
    fail_native(Open, status.val)
  }
  let owner = @publication.PublicationOwner::new(manifest)
  let mut physically_published = false
  if status.val == 0 {
    owner.accept_reservation(
      @publication.ReservationEvidence::reserved(manifest),
    ) catch {
      error => {
        close_after_open_failure(session)
        raise Protocol(error)
      }
    }
  } else if status.val == 1 {
    let inspect_status = Ref(0)
    let observed_bytes = raw_inspect_existing(
      session,
      manifest.total_bytes(),
      digest_bytes(manifest.artifact_digest()),
      metadata_record(manifest),
      inspect_status,
    )
    if inspect_status.val < 0 {
      close_after_open_failure(session)
      fail_native(InspectExisting, inspect_status.val)
    }
    let observed = {
      errdefer close_after_open_failure(session)
      parse_native_digest(observed_bytes)
    }
    owner.accept_reservation(
      @publication.ReservationEvidence::existing(manifest, observed),
    ) catch {
      error => {
        close_after_open_failure(session)
        raise Protocol(error)
      }
    }
    physically_published = observed == manifest.artifact_digest()
  } else {
    close_after_open_failure(session)
    fail_native(Open, status.val)
  }
  {
    manifest,
    owner,
    session,
    chunks_written: FixedArray::make(manifest.chunk_count(), false),
    physically_published,
    closed: false,
  }
}

///|
pub fn PublicationFs::state(self : Self) -> @publication.PublicationState {
  self.owner.state()
}

///|
pub fn PublicationFs::manifest(
  self : Self,
) -> @publication.FullArtifactManifest {
  self.manifest
}

///|
pub fn PublicationFs::begin_transfer(
  self : Self,
) -> Unit raise PublicationFsError {
  self.require_open()
  self.owner.begin_transport(FullArtifactV1) catch {
    error => raise Protocol(error)
  }
}

///|
pub fn PublicationFs::write_chunk(
  self : Self,
  evidence : @publication.ArtifactChunkEvidence,
  data : Bytes,
) -> Unit raise PublicationFsError {
  self.require_open()
  if self.owner.state() != TransferringFullArtifact {
    raise UnexpectedProtocolState
  }
  let index = evidence.index()
  let expected_offset = self.manifest.chunk_offset(index) catch {
    error => raise Protocol(error)
  }
  let expected_length = self.manifest.chunk_length(index) catch {
    error => raise Protocol(error)
  }
  if evidence.publication_id() != self.manifest.id() ||
    evidence.target() != self.manifest.target() ||
    index < 0 ||
    index >= self.chunks_written.length() ||
    evidence.offset() != expected_offset ||
    evidence.length() != expected_length {
    raise ChunkEvidenceMismatch
  }
  if data.length() != evidence.length() {
    raise ChunkLengthMismatch
  }
  if self.chunks_written[index] {
    raise DuplicateChunk
  }
  let status = raw_write_chunk(
    self.session,
    evidence.offset(),
    data,
    digest_bytes(evidence.chunk_digest()),
  )
  if status < 0 {
    fail_native(WriteChunk, status)
  }
  self.owner.accept_chunk(evidence) catch {
    error => raise Protocol(error)
  }
  self.chunks_written[index] = true
}

///|
fn PublicationFs::inspect_published(
  self : Self,
) -> @identity.Sha256Digest raise PublicationFsError {
  let status = Ref(0)
  let digest = raw_inspect_existing(
    self.session,
    self.manifest.total_bytes(),
    digest_bytes(self.manifest.artifact_digest()),
    metadata_record(self.manifest),
    status,
  )
  if status.val < 0 {
    fail_native(InspectExisting, status.val)
  }
  parse_native_digest(digest)
}

///|
pub fn PublicationFs::seal(self : Self) -> Unit raise PublicationFsError {
  self.require_open()
  if self.owner.state() != VerifyingArtifact {
    raise UnexpectedProtocolState
  }
  let status = raw_publish(
    self.session,
    self.manifest.total_bytes(),
    digest_bytes(self.manifest.artifact_digest()),
    metadata_record(self.manifest),
  )
  if status < 0 {
    fail_native(Publish, status)
  }
  if status == 1 {
    let observed = self.inspect_published()
    if observed != self.manifest.artifact_digest() {
      raise PhysicalTargetConflict
    }
    let cleanup_status = raw_discard_staging(self.session)
    if cleanup_status < 0 {
      fail_native(Cleanup, cleanup_status)
    }
  } else if status != 0 {
    fail_native(Publish, status)
  }
  self.physically_published = true
  self.owner.verify_artifact(self.manifest.artifact_digest()) catch {
    error => raise Protocol(error)
  }
}

///|
pub fn PublicationFs::acknowledge_rank(
  self : Self,
  rank : Int32,
  observed_artifact_digest : @identity.Sha256Digest,
) -> Unit raise PublicationFsError {
  self.require_open()
  let acknowledgement = @publication.RolloutRankAcknowledgement::new(
    manifest=self.manifest,
    rank~,
    observed_artifact_digest~,
  ) catch {
    error => raise Protocol(error)
  }
  self.owner.accept_acknowledgement(acknowledgement) catch {
    error => raise Protocol(error)
  }
}

///|
pub fn PublicationFs::commit(self : Self) -> Unit raise PublicationFsError {
  self.require_open()
  if !self.physically_published {
    raise UnexpectedProtocolState
  }
  self.owner.commit() catch {
    error => raise Protocol(error)
  }
}

///|
pub fn PublicationFs::committed_publication(
  self : Self,
) -> @publication.PublicationOwner raise PublicationFsError {
  if !self.physically_published || self.owner.state() != Committed {
    raise UnexpectedProtocolState
  }
  self.owner
}

///|
pub fn PublicationFs::close(self : Self) -> Unit raise PublicationFsError {
  if self.closed {
    return
  }
  let status = raw_close_session(self.session)
  self.closed = true
  if status < 0 {
    fail_native(Cleanup, status)
  }
}

///|
pub fn PublicationFs::is_closed(self : Self) -> Bool {
  self.closed || raw_session_is_closed(self.session)
}

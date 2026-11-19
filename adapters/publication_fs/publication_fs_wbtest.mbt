///|
#borrow(status)
extern "c" fn raw_test_make_root(status : Ref[Int32]) -> Bytes = "lunarein_publication_fs_test_make_root"

///|
#borrow(root)
extern "c" fn raw_test_remove_root(root : Bytes) -> Int32 = "lunarein_publication_fs_test_remove_root"

///|
#borrow(root, final_name, data)
extern "c" fn raw_test_replace_artifact(
  root : Bytes,
  final_name : Bytes,
  data : Bytes,
) -> Int32 = "lunarein_publication_fs_test_replace_artifact"

///|
fn test_digest(value : String) -> @identity.Sha256Digest {
  try! @identity.Sha256Digest::parse(value)
}

///|
test "native SHA-256 matches a standard known-answer vector" {
  assert_eq(
    sha256_bytes(b"abc"),
    test_digest(
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    ),
  )
  assert_eq(
    sha256_bytes(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
    test_digest(
      "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
    ),
  )
}

///|
fn test_root() -> String raise {
  let status = Ref(0)
  let root = raw_test_make_root(status)
  assert_eq(status.val, 0)
  @utf8.decode_lossy(root)
}

///|
fn cleanup_test_root(root : String) -> Unit raise {
  assert_eq(raw_test_remove_root(@utf8.encode(root)), 0)
}

///|
fn safetensors_from_header(header_text : String, tensor_data : Bytes) -> Bytes {
  let header = @utf8.encode(header_text)
  let padding = (8 - header.length() % 8) % 8
  let header_length = header.length() + padding
  let artifact : Array[Byte] = []
  artifact.push((header_length & 0xff).to_byte())
  artifact.push(((header_length >> 8) & 0xff).to_byte())
  artifact.push(((header_length >> 16) & 0xff).to_byte())
  artifact.push(((header_length >> 24) & 0xff).to_byte())
  artifact.push(b'\x00')
  artifact.push(b'\x00')
  artifact.push(b'\x00')
  artifact.push(b'\x00')
  for byte in header {
    artifact.push(byte)
  }
  for _ in 0..<padding {
    artifact.push(b' ')
  }
  for byte in tensor_data {
    artifact.push(byte)
  }
  Bytes::from_array(artifact)
}

///|
fn safetensors_with_byte(value : Byte) -> Bytes {
  safetensors_from_header(
    "{\"weight\":{\"dtype\":\"U8\",\"shape\":[1],\"data_offsets\":[0,1]}}",
    Bytes::from_array([value]),
  )
}

///|
fn manifest_for(
  artifact : Bytes,
  publication_id~ : UInt64 = 1UL,
  chunk_bytes~ : Int32 = 17,
) -> @publication.FullArtifactManifest raise {
  let parent_actor = test_digest(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let parent = @identity.PolicyGeneration::initial(parent_actor)
  let artifact_digest = sha256_bytes(artifact)
  let target = @identity.PolicyGeneration::new(
    sequence=2UL,
    actor=artifact_digest,
    parent_actor=Some(parent_actor),
  )
  let candidate = @update.CandidatePolicy::new(
    parent~,
    target~,
    artifact_digest~,
    tensor_vocabulary_digest=test_digest(
      "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    ),
  )
  @publication.FullArtifactManifest::new(
    id=@publication.PublicationId::new(publication_id),
    candidate~,
    total_bytes=artifact.length().to_int64(),
    chunk_bytes~,
    maximum_chunk_bytes=1024,
    rollout_rank_count=1,
    maximum_artifact_bytes=1048576L,
    maximum_chunks=1024,
    maximum_rollout_ranks=8,
  )
}

///|
fn write_artifact_chunks(
  adapter : PublicationFs,
  artifact : Bytes,
) -> Unit raise {
  let manifest = adapter.manifest()
  adapter.begin_transfer()
  for index in 0..<manifest.chunk_count() {
    let offset = manifest.chunk_offset(index).to_int()
    let length = manifest.chunk_length(index)
    let chunk = artifact[offset:offset + length].to_owned()
    let evidence = @publication.ArtifactChunkEvidence::new(
      manifest~,
      index~,
      chunk_digest=sha256_bytes(chunk),
    )
    adapter.write_chunk(evidence, chunk)
  }
}

///|
fn transfer_artifact(adapter : PublicationFs, artifact : Bytes) -> Unit raise {
  write_artifact_chunks(adapter, artifact)
  adapter.seal()
}

///|
fn acknowledge_and_commit(adapter : PublicationFs) -> Unit raise {
  adapter.acknowledge_rank(0, adapter.manifest().artifact_digest())
  adapter.commit()
}

///|
test "native publication commits and resumes the same digest" {
  let root = test_root()
  let artifact = safetensors_with_byte(b'\x2a')
  let manifest = manifest_for(artifact)
  let first = PublicationFs::open(root, manifest)
  assert_eq(first.state(), AwaitingTransport)
  try first.committed_publication() catch {
    UnexpectedProtocolState => ()
    _ => fail("wrong pre-commit handoff error")
  } noraise {
    _ => fail("publication owner escaped before commit")
  }
  transfer_artifact(first, artifact)
  assert_eq(first.state(), AwaitingRankAcknowledgements)
  acknowledge_and_commit(first)
  assert_eq(first.state(), Committed)
  assert_eq(first.committed_publication().state(), Committed)
  first.close()
  first.close()
  assert_true(first.is_closed())
  let recovered = PublicationFs::open(root, manifest)
  assert_eq(recovered.state(), AwaitingRecoveredRankAcknowledgements)
  acknowledge_and_commit(recovered)
  assert_eq(recovered.committed_publication().state(), Committed)
  recovered.close()
  cleanup_test_root(root)
}

///|
test "different physical digest remains a no-overwrite conflict" {
  let root = test_root()
  let artifact = safetensors_with_byte(b'\x2a')
  let manifest = manifest_for(artifact)
  let first = PublicationFs::open(root, manifest)
  transfer_artifact(first, artifact)
  acknowledge_and_commit(first)
  first.close()
  let replacement = safetensors_with_byte(b'\x2b')
  assert_eq(
    raw_test_replace_artifact(
      @utf8.encode(root),
      publication_final_name(manifest),
      replacement,
    ),
    0,
  )
  let conflicted = PublicationFs::open(root, manifest)
  assert_eq(conflicted.state(), TargetConflict)
  conflicted.close()
  cleanup_test_root(root)
}

///|
test "invalid safetensors never reaches the final directory" {
  let root = test_root()
  let artifact = b"not-a-safetensors-artifact"
  let manifest = manifest_for(artifact, chunk_bytes=artifact.length())
  let adapter = PublicationFs::open(root, manifest)
  adapter.begin_transfer()
  let evidence = @publication.ArtifactChunkEvidence::new(
    manifest~,
    index=0,
    chunk_digest=sha256_bytes(artifact),
  )
  adapter.write_chunk(evidence, artifact)
  try adapter.seal() catch {
    NativeFailure(operation=Publish, status=-7) => ()
    _ => fail("wrong publication error")
  } noraise {
    _ => fail("invalid safetensors was published")
  }
  assert_eq(adapter.state(), VerifyingArtifact)
  adapter.close()
  let retry = PublicationFs::open(root, manifest)
  assert_eq(retry.state(), AwaitingTransport)
  retry.close()
  cleanup_test_root(root)
}

///|
test "truncated safetensors header is rejected" {
  let root = test_root()
  let artifact = b"\x40\x00\x00\x00\x00\x00\x00\x00{}"
  let manifest = manifest_for(artifact, chunk_bytes=artifact.length())
  let adapter = PublicationFs::open(root, manifest)
  write_artifact_chunks(adapter, artifact)
  try adapter.seal() catch {
    NativeFailure(operation=Publish, status=-7) => ()
    _ => fail("wrong truncated-header error")
  } noraise {
    _ => fail("truncated safetensors header was published")
  }
  adapter.close()
  cleanup_test_root(root)
}

///|
test "malformed safetensors JSON is rejected" {
  let root = test_root()
  let artifact = safetensors_from_header("{\"weight\":", b"\x2a")
  let manifest = manifest_for(artifact, chunk_bytes=artifact.length())
  let adapter = PublicationFs::open(root, manifest)
  write_artifact_chunks(adapter, artifact)
  try adapter.seal() catch {
    NativeFailure(operation=Publish, status=-7) => ()
    _ => fail("wrong malformed-header error")
  } noraise {
    _ => fail("malformed safetensors JSON was published")
  }
  adapter.close()
  cleanup_test_root(root)
}

///|
test "duplicate top-level tensor names are rejected" {
  let root = test_root()
  let artifact = safetensors_from_header(
    "{\"weight\":{\"dtype\":\"U8\",\"shape\":[1],\"data_offsets\":[0,1]},\"weight\":{\"dtype\":\"U8\",\"shape\":[1],\"data_offsets\":[1,2]}}",
    b"\x2a\x2b",
  )
  let manifest = manifest_for(artifact, chunk_bytes=artifact.length())
  let adapter = PublicationFs::open(root, manifest)
  write_artifact_chunks(adapter, artifact)
  try adapter.seal() catch {
    NativeFailure(operation=Publish, status=-7) => ()
    _ => fail("wrong duplicate-name error")
  } noraise {
    _ => fail("duplicate tensor name was published")
  }
  adapter.close()
  cleanup_test_root(root)
}

///|
test "full artifact digest mismatch is rejected" {
  let root = test_root()
  let expected = safetensors_with_byte(b'\x2a')
  let observed = safetensors_with_byte(b'\x2b')
  assert_eq(expected.length(), observed.length())
  let manifest = manifest_for(expected, chunk_bytes=expected.length())
  let adapter = PublicationFs::open(root, manifest)
  write_artifact_chunks(adapter, observed)
  try adapter.seal() catch {
    NativeFailure(operation=Publish, status=-8) => ()
    _ => fail("wrong full-artifact digest error")
  } noraise {
    _ => fail("wrong full-artifact digest was published")
  }
  adapter.close()
  cleanup_test_root(root)
}

///|
test "chunk digest mismatch fails before chunk admission" {
  let root = test_root()
  let artifact = safetensors_with_byte(b'\x2a')
  let manifest = manifest_for(artifact, chunk_bytes=artifact.length())
  let adapter = PublicationFs::open(root, manifest)
  adapter.begin_transfer()
  let wrong = @publication.ArtifactChunkEvidence::new(
    manifest~,
    index=0,
    chunk_digest=test_digest(
      "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    ),
  )
  try adapter.write_chunk(wrong, artifact) catch {
    NativeFailure(operation=WriteChunk, status=-8) => ()
    _ => fail("wrong chunk error")
  } noraise {
    _ => fail("digest mismatch was accepted")
  }
  let correct = @publication.ArtifactChunkEvidence::new(
    manifest~,
    index=0,
    chunk_digest=sha256_bytes(artifact),
  )
  adapter.write_chunk(correct, artifact)
  adapter.seal()
  acknowledge_and_commit(adapter)
  adapter.close()
  cleanup_test_root(root)
}

///|
test "candidate lock rejects a concurrent writer" {
  let root = test_root()
  let artifact = safetensors_with_byte(b'\x2a')
  let manifest = manifest_for(artifact)
  let first = PublicationFs::open(root, manifest)
  try PublicationFs::open(root, manifest) catch {
    NativeFailure(operation=Open, status=-11) => ()
    _ => fail("wrong lock error")
  } noraise {
    _ => fail("concurrent writer acquired candidate lock")
  }
  first.close()
  cleanup_test_root(root)
}

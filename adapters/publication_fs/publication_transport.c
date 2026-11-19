#define _GNU_SOURCE 1
#define _DARWIN_C_SOURCE 1
#define _POSIX_C_SOURCE 200809L

#include "publication_fs_private.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#if defined(__linux__)
#include <linux/fs.h>
#include <sys/syscall.h>
#endif

static int lrpfs_open_existing_file(
  lrpfs_session *session,
  const char *name,
  int *directory_fd
) {
  int final_fd = openat(
    session->root_fd,
    session->final_name,
    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
  );
  if (final_fd < 0) return -1;
  int file_fd = openat(final_fd, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  if (file_fd < 0) {
    (void)lrpfs_close_fd(final_fd);
    return -1;
  }
  *directory_fd = final_fd;
  return file_fd;
}

static int lrpfs_compare_metadata(
  int directory_fd,
  moonbit_bytes_t expected_metadata
) {
  int32_t length = Moonbit_array_length(expected_metadata);
  if (length <= 0 || length > 4096) return LRPFS_INVALID;
  int fd = openat(
    directory_fd, "manifest.v1", O_RDONLY | O_CLOEXEC | O_NOFOLLOW
  );
  if (fd < 0) return LRPFS_METADATA_MISMATCH;
  struct stat info;
  int status = LRPFS_METADATA_MISMATCH;
  if (fstat(fd, &info) == 0 && S_ISREG(info.st_mode) && info.st_size == length) {
    uint8_t buffer[4096];
    size_t cursor = 0;
    while (cursor < (size_t)length) {
      ssize_t count = pread(
        fd, buffer + cursor, (size_t)length - cursor, (off_t)cursor
      );
      if (count > 0) cursor += (size_t)count;
      else if (count < 0 && errno == EINTR) continue;
      else break;
    }
    if (cursor == (size_t)length &&
        memcmp(buffer, expected_metadata, (size_t)length) == 0) {
      status = LRPFS_OK;
    }
  }
  (void)lrpfs_close_fd(fd);
  return status;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t lunarein_publication_fs_inspect_existing(
  lrpfs_session *session,
  int64_t expected_size,
  moonbit_bytes_t expected_digest,
  moonbit_bytes_t expected_metadata,
  int32_t *status
) {
  moonbit_bytes_t result = moonbit_make_bytes(64, 0);
  *status = LRPFS_EXISTING_INVALID;
  if (session == NULL || session->closed || expected_size <= 0 ||
      !lrpfs_digest_text_valid(
        expected_digest, Moonbit_array_length(expected_digest)
      )) {
    *status = session == NULL || session->closed ? LRPFS_CLOSED : LRPFS_INVALID;
    return result;
  }
  int directory_fd = -1;
  int artifact_fd = lrpfs_open_existing_file(
    session, "model.safetensors", &directory_fd
  );
  if (artifact_fd < 0) return result;
  struct stat info;
  char digest[65];
  int hash_status = lrpfs_sha256_fd(artifact_fd, digest);
  if (hash_status != LRPFS_OK) {
    *status = hash_status;
  } else {
    memcpy(result, digest, 64);
    if (memcmp(digest, expected_digest, 64) != 0) {
      *status = LRPFS_OK;
    } else if (fstat(artifact_fd, &info) != 0 || !S_ISREG(info.st_mode) ||
               info.st_size != expected_size) {
      *status = LRPFS_EXISTING_INVALID;
    } else {
      int safe = lrpfs_validate_safetensors_fd(artifact_fd, expected_size);
      *status = safe == LRPFS_OK
        ? lrpfs_compare_metadata(directory_fd, expected_metadata)
        : safe;
    }
  }
  memset(digest, 0, sizeof(digest));
  (void)lrpfs_close_fd(artifact_fd);
  (void)lrpfs_close_fd(directory_fd);
  return result;
}

MOONBIT_FFI_EXPORT
int32_t lunarein_publication_fs_write_chunk(
  lrpfs_session *session,
  int64_t offset,
  moonbit_bytes_t data,
  moonbit_bytes_t expected_digest
) {
  if (session == NULL || session->closed || session->staging_fd < 0) {
    return LRPFS_CLOSED;
  }
  int32_t length = Moonbit_array_length(data);
  if (offset < 0 || length <= 0 || offset > INT64_MAX - length ||
      !lrpfs_digest_text_valid(
        expected_digest, Moonbit_array_length(expected_digest)
      )) {
    return LRPFS_INVALID;
  }
  lrpfs_sha256 hash;
  uint8_t digest_bytes[32];
  char digest[65];
  lrpfs_sha256_init(&hash);
  lrpfs_sha256_update(&hash, data, (size_t)length);
  lrpfs_sha256_final(&hash, digest_bytes);
  lrpfs_sha256_hex(digest_bytes, digest);
  memset(digest_bytes, 0, sizeof(digest_bytes));
  if (memcmp(digest, expected_digest, 64) != 0) {
    memset(digest, 0, sizeof(digest));
    return LRPFS_DIGEST_MISMATCH;
  }
  memset(digest, 0, sizeof(digest));
  int fd = openat(
    session->staging_fd,
    ".artifact.part",
    O_WRONLY | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
    0600
  );
  if (fd < 0) return LRPFS_IO;
  int32_t cursor = 0;
  int status = LRPFS_OK;
  while (cursor < length) {
    ssize_t count = pwrite(
      fd, data + cursor, (size_t)(length - cursor), (off_t)(offset + cursor)
    );
    if (count > 0) cursor += (int32_t)count;
    else if (count < 0 && errno == EINTR) continue;
    else {
      status = LRPFS_IO;
      break;
    }
  }
  if (lrpfs_close_fd(fd) != LRPFS_OK && status == LRPFS_OK) status = LRPFS_IO;
  return status;
}

static int lrpfs_write_metadata(
  lrpfs_session *session,
  moonbit_bytes_t metadata
) {
  int32_t length = Moonbit_array_length(metadata);
  if (length <= 0 || length > 4096) return LRPFS_INVALID;
  int fd = openat(
    session->staging_fd,
    ".manifest.part",
    O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
    0600
  );
  if (fd < 0) return LRPFS_IO;
  int32_t cursor = 0;
  int status = LRPFS_OK;
  while (cursor < length) {
    ssize_t count = write(fd, metadata + cursor, (size_t)(length - cursor));
    if (count > 0) cursor += (int32_t)count;
    else if (count < 0 && errno == EINTR) continue;
    else {
      status = LRPFS_IO;
      break;
    }
  }
  if (status == LRPFS_OK && fsync(fd) != 0) status = LRPFS_IO;
  if (lrpfs_close_fd(fd) != LRPFS_OK && status == LRPFS_OK) status = LRPFS_IO;
  if (status != LRPFS_OK) return status;
  return renameat(
    session->staging_fd,
    ".manifest.part",
    session->staging_fd,
    "manifest.v1"
  ) == 0 ? LRPFS_OK : LRPFS_IO;
}

static int lrpfs_rename_noreplace(lrpfs_session *session) {
#if defined(__APPLE__)
  return renameatx_np(
    session->root_fd,
    session->staging_name,
    session->root_fd,
    session->final_name,
    RENAME_EXCL
  );
#elif defined(__linux__) && defined(SYS_renameat2)
  return (int)syscall(
    SYS_renameat2,
    session->root_fd,
    session->staging_name,
    session->root_fd,
    session->final_name,
    RENAME_NOREPLACE
  );
#else
  errno = ENOTSUP;
  return -1;
#endif
}

MOONBIT_FFI_EXPORT
int32_t lunarein_publication_fs_publish(
  lrpfs_session *session,
  int64_t expected_size,
  moonbit_bytes_t expected_digest,
  moonbit_bytes_t metadata
) {
  if (session == NULL || session->closed || session->staging_fd < 0) {
    return LRPFS_CLOSED;
  }
  if (expected_size <= 0 || !lrpfs_digest_text_valid(
        expected_digest, Moonbit_array_length(expected_digest)
      )) {
    return LRPFS_INVALID;
  }
  int fd = openat(
    session->staging_fd, ".artifact.part", O_RDWR | O_CLOEXEC | O_NOFOLLOW
  );
  if (fd < 0) return LRPFS_IO;
  struct stat info;
  char digest[65];
  int status = LRPFS_OK;
  if (fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) ||
      info.st_size != expected_size) {
    status = LRPFS_INVALID;
  } else {
    status = lrpfs_validate_safetensors_fd(fd, expected_size);
  }
  if (status == LRPFS_OK) status = lrpfs_sha256_fd(fd, digest);
  if (status == LRPFS_OK && memcmp(digest, expected_digest, 64) != 0) {
    status = LRPFS_DIGEST_MISMATCH;
  }
  if (status == LRPFS_OK && fsync(fd) != 0) status = LRPFS_IO;
  if (lrpfs_close_fd(fd) != LRPFS_OK && status == LRPFS_OK) status = LRPFS_IO;
  memset(digest, 0, sizeof(digest));
  if (status != LRPFS_OK) return status;
  status = lrpfs_write_metadata(session, metadata);
  if (status != LRPFS_OK) return status;
  if (renameat(
        session->staging_fd,
        ".artifact.part",
        session->staging_fd,
        "model.safetensors"
      ) != 0) {
    return LRPFS_IO;
  }
  if (fsync(session->staging_fd) != 0) return LRPFS_IO;
  if (lrpfs_rename_noreplace(session) != 0) {
    if (errno == EEXIST || errno == ENOTEMPTY) return LRPFS_EXISTS;
    return errno == ENOTSUP ? LRPFS_UNSUPPORTED : LRPFS_IO;
  }
  session->published = 1;
  return fsync(session->root_fd) == 0 ? LRPFS_OK : LRPFS_IO;
}

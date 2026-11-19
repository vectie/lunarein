#define _DARWIN_C_SOURCE 1
#define _POSIX_C_SOURCE 200809L

#include "publication_fs_private.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

int lrpfs_close_fd(int fd) {
  if (fd < 0) return LRPFS_OK;
  int result;
#if defined(__APPLE__)
  do result = close(fd); while (result != 0 && errno == EINTR);
#else
  result = close(fd);
#endif
  return result == 0 ? LRPFS_OK : LRPFS_IO;
}

static void lrpfs_session_finalize(void *object) {
  lrpfs_session *session = (lrpfs_session *)object;
  if (session == NULL || session->closed) return;
  (void)lrpfs_close_fd(session->staging_fd);
  (void)lrpfs_close_fd(session->lock_fd);
  (void)lrpfs_close_fd(session->root_fd);
  session->staging_fd = -1;
  session->lock_fd = -1;
  session->root_fd = -1;
  session->closed = 1;
}

static lrpfs_session *lrpfs_new_session(void) {
  lrpfs_session *session = (lrpfs_session *)moonbit_make_external_object(
    lrpfs_session_finalize, sizeof(lrpfs_session)
  );
  session->root_fd = -1;
  session->staging_fd = -1;
  session->lock_fd = -1;
  session->closed = 1;
  session->published = 0;
  session->final_name[0] = '\0';
  session->staging_name[0] = '\0';
  return session;
}

static int lrpfs_bytes_c_string(
  moonbit_bytes_t bytes,
  int require_absolute,
  int require_component,
  const char **output,
  int32_t *length
) {
  *length = Moonbit_array_length(bytes);
  if (*length <= 0 || memchr(bytes, '\0', (size_t)*length) != NULL) return 0;
  const char *text = (const char *)bytes;
  if (require_absolute && text[0] != '/') return 0;
  if (require_component) {
    if (*length > 255 || (*length == 1 && text[0] == '.') ||
        (*length == 2 && text[0] == '.' && text[1] == '.')) {
      return 0;
    }
    for (int32_t index = 0; index < *length; index++) {
      unsigned char c = (unsigned char)text[index];
      if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') || c == '.' || c == '-')) {
        return 0;
      }
    }
  }
  *output = text;
  return 1;
}

static int lrpfs_unlink_known(int directory_fd, const char *name) {
  if (unlinkat(directory_fd, name, 0) == 0 || errno == ENOENT) return LRPFS_OK;
  return LRPFS_IO;
}

static int lrpfs_cleanup_staging(lrpfs_session *session) {
  if (session->staging_fd < 0) return LRPFS_OK;
  int status = LRPFS_OK;
  const char *known[] = {
    ".artifact.part", ".manifest.part", "model.safetensors", "manifest.v1"
  };
  for (size_t index = 0; index < sizeof(known) / sizeof(known[0]); index++) {
    int item_status = lrpfs_unlink_known(session->staging_fd, known[index]);
    if (status == LRPFS_OK && item_status != LRPFS_OK) status = item_status;
  }
  if (fsync(session->staging_fd) != 0 && status == LRPFS_OK) status = LRPFS_IO;
  if (lrpfs_close_fd(session->staging_fd) != LRPFS_OK && status == LRPFS_OK) {
    status = LRPFS_IO;
  }
  session->staging_fd = -1;
  if (unlinkat(session->root_fd, session->staging_name, AT_REMOVEDIR) != 0 &&
      errno != ENOENT) {
    if (errno == ENOTEMPTY || errno == EEXIST) return LRPFS_CLEANUP_REFUSED;
    if (status == LRPFS_OK) status = LRPFS_IO;
  }
  if (fsync(session->root_fd) != 0 && status == LRPFS_OK) status = LRPFS_IO;
  return status;
}

static int lrpfs_open_staging(lrpfs_session *session) {
  session->staging_fd = openat(
    session->root_fd,
    session->staging_name,
    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
  );
  return session->staging_fd >= 0 ? LRPFS_OK : LRPFS_IO;
}

static int lrpfs_remove_crashed_staging(lrpfs_session *session) {
  struct stat info;
  if (fstatat(
        session->root_fd, session->staging_name, &info, AT_SYMLINK_NOFOLLOW
      ) != 0) {
    return errno == ENOENT ? LRPFS_OK : LRPFS_IO;
  }
  if (!S_ISDIR(info.st_mode)) return LRPFS_CLEANUP_REFUSED;
  int status = lrpfs_open_staging(session);
  if (status != LRPFS_OK) return status;
  return lrpfs_cleanup_staging(session);
}

static int lrpfs_existing_directory(lrpfs_session *session) {
  struct stat info;
  if (fstatat(
        session->root_fd, session->final_name, &info, AT_SYMLINK_NOFOLLOW
      ) == 0) {
    return S_ISDIR(info.st_mode) ? LRPFS_EXISTS : LRPFS_EXISTING_INVALID;
  }
  return errno == ENOENT ? LRPFS_OK : LRPFS_IO;
}

MOONBIT_FFI_EXPORT
lrpfs_session *lunarein_publication_fs_open(
  moonbit_bytes_t root,
  moonbit_bytes_t final_name,
  moonbit_bytes_t staging_name,
  moonbit_bytes_t lock_name,
  int32_t *status
) {
  lrpfs_session *session = lrpfs_new_session();
  const char *root_text;
  const char *final_text;
  const char *staging_text;
  const char *lock_text;
  int32_t root_length, final_length, staging_length, lock_length;
  char root_path[PATH_MAX];
  char lock_path[256];
  *status = LRPFS_INVALID;
  if (!lrpfs_bytes_c_string(root, 1, 0, &root_text, &root_length) ||
      !lrpfs_bytes_c_string(
        final_name, 0, 1, &final_text, &final_length
      ) ||
      !lrpfs_bytes_c_string(
        staging_name, 0, 1, &staging_text, &staging_length
      ) ||
      !lrpfs_bytes_c_string(lock_name, 0, 1, &lock_text, &lock_length)) {
    return session;
  }
  if (root_length >= PATH_MAX || lock_length >= (int32_t)sizeof(lock_path)) {
    return session;
  }
  memcpy(root_path, root_text, (size_t)root_length);
  root_path[root_length] = '\0';
  memcpy(lock_path, lock_text, (size_t)lock_length);
  lock_path[lock_length] = '\0';
  memcpy(session->final_name, final_text, (size_t)final_length);
  session->final_name[final_length] = '\0';
  memcpy(session->staging_name, staging_text, (size_t)staging_length);
  session->staging_name[staging_length] = '\0';
  session->root_fd = open(
    root_path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
  );
  if (session->root_fd < 0) {
    *status = errno == ELOOP ? LRPFS_UNSAFE_PATH : LRPFS_UNAVAILABLE;
    return session;
  }
  session->lock_fd = openat(
    session->root_fd,
    lock_path,
    O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
    0600
  );
  if (session->lock_fd < 0) {
    *status = errno == ELOOP ? LRPFS_UNSAFE_PATH : LRPFS_IO;
    return session;
  }
  if (flock(session->lock_fd, LOCK_EX | LOCK_NB) != 0) {
    *status = errno == EWOULDBLOCK ? LRPFS_BUSY : LRPFS_IO;
    return session;
  }
  session->closed = 0;
  int existing = lrpfs_existing_directory(session);
  if (existing != LRPFS_OK) {
    *status = existing;
    return session;
  }
  int cleanup = lrpfs_remove_crashed_staging(session);
  if (cleanup != LRPFS_OK) {
    *status = cleanup;
    return session;
  }
  if (mkdirat(session->root_fd, session->staging_name, 0700) != 0) {
    *status = LRPFS_IO;
    return session;
  }
  if (lrpfs_open_staging(session) != LRPFS_OK || fsync(session->root_fd) != 0) {
    *status = LRPFS_IO;
    return session;
  }
  *status = LRPFS_OK;
  return session;
}

MOONBIT_FFI_EXPORT
int32_t lunarein_publication_fs_discard_staging(lrpfs_session *session) {
  if (session == NULL || session->closed) return LRPFS_CLOSED;
  return lrpfs_cleanup_staging(session);
}

MOONBIT_FFI_EXPORT
int32_t lunarein_publication_fs_close(lrpfs_session *session) {
  if (session == NULL) return LRPFS_INVALID;
  if (session->closed) return LRPFS_OK;
  int status = LRPFS_OK;
  if (!session->published) status = lrpfs_cleanup_staging(session);
  if (session->staging_fd >= 0 &&
      lrpfs_close_fd(session->staging_fd) != LRPFS_OK && status == LRPFS_OK) {
    status = LRPFS_IO;
  }
  session->staging_fd = -1;
  if (lrpfs_close_fd(session->lock_fd) != LRPFS_OK && status == LRPFS_OK) {
    status = LRPFS_IO;
  }
  session->lock_fd = -1;
  if (lrpfs_close_fd(session->root_fd) != LRPFS_OK && status == LRPFS_OK) {
    status = LRPFS_IO;
  }
  session->root_fd = -1;
  session->closed = 1;
  return status;
}

MOONBIT_FFI_EXPORT
int32_t lunarein_publication_fs_is_closed(lrpfs_session *session) {
  return session == NULL || session->closed;
}

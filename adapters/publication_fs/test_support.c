#define _DARWIN_C_SOURCE 1
#define _POSIX_C_SOURCE 200809L

#include "publication_fs_private.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

MOONBIT_FFI_EXPORT
moonbit_bytes_t lunarein_publication_fs_test_make_root(int32_t *status) {
  char path[] = "/tmp/lunarein-publication-fs.XXXXXX";
  char *created = mkdtemp(path);
  if (created == NULL) {
    *status = LRPFS_IO;
    return moonbit_make_bytes(0, 0);
  }
  size_t length = strlen(created);
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)length, 0);
  memcpy(result, created, length);
  *status = LRPFS_OK;
  return result;
}

static int lrpfs_test_remove_contents(int directory_fd, int depth) {
  if (depth > 8) return LRPFS_CLEANUP_REFUSED;
  int duplicate = fcntl(directory_fd, F_DUPFD_CLOEXEC, 0);
  if (duplicate < 0) return LRPFS_IO;
  DIR *directory = fdopendir(duplicate);
  if (directory == NULL) {
    (void)close(duplicate);
    return LRPFS_IO;
  }
  int status = LRPFS_OK;
  for (;;) {
    errno = 0;
    struct dirent *entry = readdir(directory);
    if (entry == NULL) {
      if (errno != 0) status = LRPFS_IO;
      break;
    }
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
      continue;
    }
    struct stat info;
    if (fstatat(
          directory_fd, entry->d_name, &info, AT_SYMLINK_NOFOLLOW
        ) != 0) {
      status = LRPFS_IO;
      break;
    }
    if (S_ISDIR(info.st_mode)) {
      int child = openat(
        directory_fd,
        entry->d_name,
        O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
      );
      if (child < 0) {
        status = LRPFS_IO;
        break;
      }
      status = lrpfs_test_remove_contents(child, depth + 1);
      (void)close(child);
      if (status != LRPFS_OK ||
          unlinkat(directory_fd, entry->d_name, AT_REMOVEDIR) != 0) {
        status = status == LRPFS_OK ? LRPFS_IO : status;
        break;
      }
    } else if (unlinkat(directory_fd, entry->d_name, 0) != 0) {
      status = LRPFS_IO;
      break;
    }
  }
  (void)closedir(directory);
  return status;
}

MOONBIT_FFI_EXPORT
int32_t lunarein_publication_fs_test_remove_root(moonbit_bytes_t root) {
  static const char prefix[] = "/tmp/lunarein-publication-fs.";
  int32_t length = Moonbit_array_length(root);
  char path[PATH_MAX];
  if (length <= (int32_t)(sizeof(prefix) - 1U) ||
      memchr(root, '\0', (size_t)length) != NULL ||
      memcmp(root, prefix, sizeof(prefix) - 1U) != 0) {
    return LRPFS_UNSAFE_PATH;
  }
  if (length >= PATH_MAX) return LRPFS_UNSAFE_PATH;
  memcpy(path, root, (size_t)length);
  path[length] = '\0';
  int fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (fd < 0) return errno == ENOENT ? LRPFS_OK : LRPFS_IO;
  int status = lrpfs_test_remove_contents(fd, 0);
  (void)close(fd);
  if (status != LRPFS_OK) return status;
  return rmdir(path) == 0 || errno == ENOENT ? LRPFS_OK : LRPFS_IO;
}

MOONBIT_FFI_EXPORT
int32_t lunarein_publication_fs_test_replace_artifact(
  moonbit_bytes_t root,
  moonbit_bytes_t final_name,
  moonbit_bytes_t data
) {
  int32_t root_length = Moonbit_array_length(root);
  int32_t final_length = Moonbit_array_length(final_name);
  char root_path[PATH_MAX];
  char final_path[256];
  if (root_length <= 0 || final_length <= 0 || final_length > 255 ||
      memchr(root, '\0', (size_t)root_length) != NULL ||
      memchr(final_name, '\0', (size_t)final_length) != NULL ||
      ((const char *)root)[0] != '/' ||
      memchr(final_name, '/', (size_t)final_length) != NULL) {
    return LRPFS_INVALID;
  }
  if (root_length >= PATH_MAX || final_length >= (int32_t)sizeof(final_path)) {
    return LRPFS_INVALID;
  }
  memcpy(root_path, root, (size_t)root_length);
  root_path[root_length] = '\0';
  memcpy(final_path, final_name, (size_t)final_length);
  final_path[final_length] = '\0';
  int root_fd = open(
    root_path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
  );
  if (root_fd < 0) return LRPFS_IO;
  int final_fd = openat(
    root_fd,
    final_path,
    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
  );
  if (final_fd < 0) {
    (void)close(root_fd);
    return LRPFS_IO;
  }
  int artifact_fd = openat(
    final_fd,
    "model.safetensors",
    O_WRONLY | O_TRUNC | O_CLOEXEC | O_NOFOLLOW
  );
  int status = artifact_fd < 0 ? LRPFS_IO : LRPFS_OK;
  int32_t length = Moonbit_array_length(data);
  int32_t cursor = 0;
  while (status == LRPFS_OK && cursor < length) {
    ssize_t count = write(
      artifact_fd, data + cursor, (size_t)(length - cursor)
    );
    if (count > 0) cursor += (int32_t)count;
    else if (count < 0 && errno == EINTR) continue;
    else status = LRPFS_IO;
  }
  if (status == LRPFS_OK && fsync(artifact_fd) != 0) status = LRPFS_IO;
  if (artifact_fd >= 0) (void)close(artifact_fd);
  (void)close(final_fd);
  (void)close(root_fd);
  return status;
}

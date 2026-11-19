#ifndef LUNAREIN_PUBLICATION_FS_PRIVATE_H
#define LUNAREIN_PUBLICATION_FS_PRIVATE_H

#include <moonbit.h>
#include <stdint.h>
#include <stddef.h>

enum {
  LRPFS_OK = 0,
  LRPFS_EXISTS = 1,
  LRPFS_INVALID = -1,
  LRPFS_UNAVAILABLE = -2,
  LRPFS_UNSAFE_PATH = -3,
  LRPFS_IO = -4,
  LRPFS_EXISTING_INVALID = -5,
  LRPFS_METADATA_MISMATCH = -6,
  LRPFS_SAFETENSORS_INVALID = -7,
  LRPFS_DIGEST_MISMATCH = -8,
  LRPFS_NO_OVERWRITE_CONFLICT = -9,
  LRPFS_CLEANUP_REFUSED = -10,
  LRPFS_BUSY = -11,
  LRPFS_CLOSED = -12,
  LRPFS_UNSUPPORTED = -13
};

typedef struct {
  int root_fd;
  int staging_fd;
  int lock_fd;
  int closed;
  int published;
  char final_name[256];
  char staging_name[256];
} lrpfs_session;

typedef struct {
  uint32_t state[8];
  uint64_t bit_count;
  uint8_t block[64];
  size_t block_length;
} lrpfs_sha256;

int lrpfs_close_fd(int fd);

void lrpfs_sha256_init(lrpfs_sha256 *ctx);
void lrpfs_sha256_update(lrpfs_sha256 *ctx, const uint8_t *data, size_t length);
void lrpfs_sha256_final(lrpfs_sha256 *ctx, uint8_t output[32]);
void lrpfs_sha256_hex(const uint8_t digest[32], char output[65]);
int lrpfs_sha256_fd(int fd, char output[65]);
int lrpfs_digest_text_valid(const uint8_t *text, int32_t length);

int lrpfs_validate_safetensors_fd(int fd, int64_t file_size);

#endif

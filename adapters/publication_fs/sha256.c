#define _POSIX_C_SOURCE 200809L

#include "publication_fs_private.h"

#include <errno.h>
#include <string.h>
#include <unistd.h>

static const uint32_t lrpfs_sha256_k[64] = {
  0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U,
  0x3956c25bU, 0x59f111f1U, 0x923f82a4U, 0xab1c5ed5U,
  0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U,
  0x72be5d74U, 0x80deb1feU, 0x9bdc06a7U, 0xc19bf174U,
  0xe49b69c1U, 0xefbe4786U, 0x0fc19dc6U, 0x240ca1ccU,
  0x2de92c6fU, 0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU,
  0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U,
  0xc6e00bf3U, 0xd5a79147U, 0x06ca6351U, 0x14292967U,
  0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU, 0x53380d13U,
  0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U,
  0xa2bfe8a1U, 0xa81a664bU, 0xc24b8b70U, 0xc76c51a3U,
  0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U,
  0x19a4c116U, 0x1e376c08U, 0x2748774cU, 0x34b0bcb5U,
  0x391c0cb3U, 0x4ed8aa4aU, 0x5b9cca4fU, 0x682e6ff3U,
  0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U,
  0x90befffaU, 0xa4506cebU, 0xbef9a3f7U, 0xc67178f2U
};

static uint32_t lrpfs_rotr(uint32_t value, uint32_t bits) {
  return (value >> bits) | (value << (32U - bits));
}

static uint32_t lrpfs_load_be32(const uint8_t *input) {
  return ((uint32_t)input[0] << 24U) |
         ((uint32_t)input[1] << 16U) |
         ((uint32_t)input[2] << 8U) |
         (uint32_t)input[3];
}

static void lrpfs_sha256_transform(lrpfs_sha256 *ctx, const uint8_t block[64]) {
  uint32_t words[64];
  for (size_t index = 0; index < 16; index++) {
    words[index] = lrpfs_load_be32(block + index * 4U);
  }
  for (size_t index = 16; index < 64; index++) {
    uint32_t a = words[index - 15];
    uint32_t b = words[index - 2];
    uint32_t s0 = lrpfs_rotr(a, 7) ^ lrpfs_rotr(a, 18) ^ (a >> 3U);
    uint32_t s1 = lrpfs_rotr(b, 17) ^ lrpfs_rotr(b, 19) ^ (b >> 10U);
    words[index] = words[index - 16] + s0 + words[index - 7] + s1;
  }
  uint32_t a = ctx->state[0];
  uint32_t b = ctx->state[1];
  uint32_t c = ctx->state[2];
  uint32_t d = ctx->state[3];
  uint32_t e = ctx->state[4];
  uint32_t f = ctx->state[5];
  uint32_t g = ctx->state[6];
  uint32_t h = ctx->state[7];
  for (size_t index = 0; index < 64; index++) {
    uint32_t s1 = lrpfs_rotr(e, 6) ^ lrpfs_rotr(e, 11) ^ lrpfs_rotr(e, 25);
    uint32_t choose = (e & f) ^ ((~e) & g);
    uint32_t temp1 = h + s1 + choose + lrpfs_sha256_k[index] + words[index];
    uint32_t s0 = lrpfs_rotr(a, 2) ^ lrpfs_rotr(a, 13) ^ lrpfs_rotr(a, 22);
    uint32_t majority = (a & b) ^ (a & c) ^ (b & c);
    uint32_t temp2 = s0 + majority;
    h = g;
    g = f;
    f = e;
    e = d + temp1;
    d = c;
    c = b;
    b = a;
    a = temp1 + temp2;
  }
  ctx->state[0] += a;
  ctx->state[1] += b;
  ctx->state[2] += c;
  ctx->state[3] += d;
  ctx->state[4] += e;
  ctx->state[5] += f;
  ctx->state[6] += g;
  ctx->state[7] += h;
}

void lrpfs_sha256_init(lrpfs_sha256 *ctx) {
  static const uint32_t initial[8] = {
    0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU,
    0x510e527fU, 0x9b05688cU, 0x1f83d9abU, 0x5be0cd19U
  };
  memcpy(ctx->state, initial, sizeof(initial));
  ctx->bit_count = 0;
  ctx->block_length = 0;
}

void lrpfs_sha256_update(lrpfs_sha256 *ctx, const uint8_t *data, size_t length) {
  while (length > 0) {
    size_t room = sizeof(ctx->block) - ctx->block_length;
    size_t take = length < room ? length : room;
    memcpy(ctx->block + ctx->block_length, data, take);
    ctx->block_length += take;
    data += take;
    length -= take;
    if (ctx->block_length == sizeof(ctx->block)) {
      lrpfs_sha256_transform(ctx, ctx->block);
      ctx->bit_count += 512U;
      ctx->block_length = 0;
    }
  }
}

void lrpfs_sha256_final(lrpfs_sha256 *ctx, uint8_t output[32]) {
  uint64_t total_bits = ctx->bit_count + (uint64_t)ctx->block_length * 8U;
  ctx->block[ctx->block_length++] = 0x80U;
  if (ctx->block_length > 56U) {
    memset(ctx->block + ctx->block_length, 0, 64U - ctx->block_length);
    lrpfs_sha256_transform(ctx, ctx->block);
    ctx->block_length = 0;
  }
  memset(ctx->block + ctx->block_length, 0, 56U - ctx->block_length);
  for (size_t index = 0; index < 8; index++) {
    ctx->block[63U - index] = (uint8_t)(total_bits >> (index * 8U));
  }
  lrpfs_sha256_transform(ctx, ctx->block);
  for (size_t index = 0; index < 8; index++) {
    output[index * 4U] = (uint8_t)(ctx->state[index] >> 24U);
    output[index * 4U + 1U] = (uint8_t)(ctx->state[index] >> 16U);
    output[index * 4U + 2U] = (uint8_t)(ctx->state[index] >> 8U);
    output[index * 4U + 3U] = (uint8_t)ctx->state[index];
  }
  memset(ctx, 0, sizeof(*ctx));
}

void lrpfs_sha256_hex(const uint8_t digest[32], char output[65]) {
  static const char hex[] = "0123456789abcdef";
  for (size_t index = 0; index < 32; index++) {
    output[index * 2U] = hex[digest[index] >> 4U];
    output[index * 2U + 1U] = hex[digest[index] & 0x0fU];
  }
  output[64] = '\0';
}

int lrpfs_sha256_fd(int fd, char output[65]) {
  uint8_t buffer[65536];
  lrpfs_sha256 ctx;
  lrpfs_sha256_init(&ctx);
  int64_t offset = 0;
  for (;;) {
    ssize_t count = pread(fd, buffer, sizeof(buffer), (off_t)offset);
    if (count > 0) {
      lrpfs_sha256_update(&ctx, buffer, (size_t)count);
      offset += count;
    } else if (count == 0) {
      break;
    } else if (errno != EINTR) {
      memset(&ctx, 0, sizeof(ctx));
      return LRPFS_IO;
    }
  }
  uint8_t digest[32];
  lrpfs_sha256_final(&ctx, digest);
  lrpfs_sha256_hex(digest, output);
  memset(digest, 0, sizeof(digest));
  return LRPFS_OK;
}

int lrpfs_digest_text_valid(const uint8_t *text, int32_t length) {
  if (length != 64) return 0;
  for (int32_t index = 0; index < length; index++) {
    uint8_t c = text[index];
    if (!((c >= (uint8_t)'0' && c <= (uint8_t)'9') ||
          (c >= (uint8_t)'a' && c <= (uint8_t)'f'))) {
      return 0;
    }
  }
  return 1;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t lunarein_publication_fs_sha256_bytes(moonbit_bytes_t data) {
  int32_t length = Moonbit_array_length(data);
  lrpfs_sha256 ctx;
  uint8_t digest[32];
  char hex[65];
  lrpfs_sha256_init(&ctx);
  lrpfs_sha256_update(&ctx, data, (size_t)length);
  lrpfs_sha256_final(&ctx, digest);
  lrpfs_sha256_hex(digest, hex);
  moonbit_bytes_t result = moonbit_make_bytes(64, 0);
  memcpy(result, hex, 64);
  memset(digest, 0, sizeof(digest));
  memset(hex, 0, sizeof(hex));
  return result;
}

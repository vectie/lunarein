#define _POSIX_C_SOURCE 200809L

#include "publication_fs_private.h"

#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct {
  uint64_t start;
  uint64_t end;
} lrpfs_range;

typedef struct {
  size_t start;
  size_t length;
} lrpfs_name;

typedef struct {
  const uint8_t *data;
  size_t length;
  size_t position;
  uint64_t tensor_data_length;
  lrpfs_range *ranges;
  size_t range_count;
  size_t range_capacity;
  lrpfs_name *names;
  size_t name_count;
  size_t name_capacity;
} lrpfs_json;

static int lrpfs_read_exact(int fd, uint8_t *output, size_t length, off_t offset) {
  size_t cursor = 0;
  while (cursor < length) {
    ssize_t count = pread(fd, output + cursor, length - cursor, offset + (off_t)cursor);
    if (count > 0) {
      cursor += (size_t)count;
    } else if (count == 0) {
      return 0;
    } else if (errno != EINTR) {
      return 0;
    }
  }
  return 1;
}

static int lrpfs_utf8_valid(const uint8_t *data, size_t length) {
  size_t index = 0;
  while (index < length) {
    uint8_t first = data[index++];
    if (first < 0x80U) continue;
    uint32_t value;
    size_t continuation;
    uint32_t minimum;
    if ((first & 0xe0U) == 0xc0U) {
      value = first & 0x1fU;
      continuation = 1;
      minimum = 0x80U;
    } else if ((first & 0xf0U) == 0xe0U) {
      value = first & 0x0fU;
      continuation = 2;
      minimum = 0x800U;
    } else if ((first & 0xf8U) == 0xf0U) {
      value = first & 0x07U;
      continuation = 3;
      minimum = 0x10000U;
    } else {
      return 0;
    }
    if (continuation > length - index) return 0;
    for (size_t part = 0; part < continuation; part++) {
      uint8_t next = data[index++];
      if ((next & 0xc0U) != 0x80U) return 0;
      value = (value << 6U) | (next & 0x3fU);
    }
    if (value < minimum || value > 0x10ffffU ||
        (value >= 0xd800U && value <= 0xdfffU)) {
      return 0;
    }
  }
  return 1;
}

static void lrpfs_skip_space(lrpfs_json *parser) {
  while (parser->position < parser->length) {
    uint8_t c = parser->data[parser->position];
    if (c != ' ' && c != '\t' && c != '\n' && c != '\r') break;
    parser->position++;
  }
}

static int lrpfs_consume(lrpfs_json *parser, uint8_t expected) {
  lrpfs_skip_space(parser);
  if (parser->position >= parser->length ||
      parser->data[parser->position] != expected) {
    return 0;
  }
  parser->position++;
  return 1;
}

static int lrpfs_hex_digit(uint8_t value) {
  return (value >= '0' && value <= '9') ||
         (value >= 'a' && value <= 'f') ||
         (value >= 'A' && value <= 'F');
}

static int lrpfs_parse_string(
  lrpfs_json *parser,
  size_t *start,
  size_t *length,
  int *escaped
) {
  lrpfs_skip_space(parser);
  if (parser->position >= parser->length || parser->data[parser->position] != '"') {
    return 0;
  }
  parser->position++;
  *start = parser->position;
  *escaped = 0;
  while (parser->position < parser->length) {
    uint8_t c = parser->data[parser->position++];
    if (c == '"') {
      *length = parser->position - *start - 1U;
      return 1;
    }
    if (c < 0x20U) return 0;
    if (c == '\\') {
      *escaped = 1;
      if (parser->position >= parser->length) return 0;
      uint8_t escape = parser->data[parser->position++];
      if (escape == 'u') {
        if (parser->length - parser->position < 4U) return 0;
        for (size_t digit = 0; digit < 4; digit++) {
          if (!lrpfs_hex_digit(parser->data[parser->position++])) return 0;
        }
      } else if (escape != '"' && escape != '\\' && escape != '/' &&
                 escape != 'b' && escape != 'f' && escape != 'n' &&
                 escape != 'r' && escape != 't') {
        return 0;
      }
    }
  }
  return 0;
}

static int lrpfs_key_equals(
  const lrpfs_json *parser,
  size_t start,
  size_t length,
  int escaped,
  const char *expected
) {
  size_t expected_length = strlen(expected);
  return !escaped && length == expected_length &&
         memcmp(parser->data + start, expected, length) == 0;
}

static int lrpfs_parse_uint(lrpfs_json *parser, uint64_t *value) {
  lrpfs_skip_space(parser);
  if (parser->position >= parser->length) return 0;
  size_t start = parser->position;
  uint64_t result = 0;
  if (parser->data[parser->position] == '0') {
    parser->position++;
    if (parser->position < parser->length &&
        parser->data[parser->position] >= '0' &&
        parser->data[parser->position] <= '9') {
      return 0;
    }
  } else {
    while (parser->position < parser->length) {
      uint8_t c = parser->data[parser->position];
      if (c < '0' || c > '9') break;
      uint64_t digit = (uint64_t)(c - '0');
      if (result > (UINT64_MAX - digit) / 10U) return 0;
      result = result * 10U + digit;
      parser->position++;
    }
  }
  if (parser->position == start) return 0;
  *value = result;
  return 1;
}

static int lrpfs_dtype_size(const uint8_t *value, size_t length) {
  static const char *one[] = {
    "BOOL", "I8", "U8", "F8_E4M3", "F8_E4M3FN", "F8_E5M2"
  };
  static const char *two[] = { "I16", "U16", "F16", "BF16" };
  static const char *four[] = { "I32", "U32", "F32" };
  static const char *eight[] = { "I64", "U64", "F64" };
  const char **groups[] = { one, two, four, eight };
  const size_t counts[] = {
    sizeof(one) / sizeof(one[0]), sizeof(two) / sizeof(two[0]),
    sizeof(four) / sizeof(four[0]), sizeof(eight) / sizeof(eight[0])
  };
  const int sizes[] = { 1, 2, 4, 8 };
  for (size_t group = 0; group < 4; group++) {
    for (size_t index = 0; index < counts[group]; index++) {
      if (strlen(groups[group][index]) == length &&
          memcmp(value, groups[group][index], length) == 0) {
        return sizes[group];
      }
    }
  }
  return 0;
}

static int lrpfs_add_range(lrpfs_json *parser, uint64_t start, uint64_t end) {
  if (parser->range_count == parser->range_capacity) {
    size_t capacity = parser->range_capacity == 0 ? 16U : parser->range_capacity * 2U;
    if (capacity < parser->range_capacity ||
        capacity > SIZE_MAX / sizeof(lrpfs_range)) {
      return 0;
    }
    lrpfs_range *grown = (lrpfs_range *)realloc(
      parser->ranges, capacity * sizeof(lrpfs_range)
    );
    if (grown == NULL) return 0;
    parser->ranges = grown;
    parser->range_capacity = capacity;
  }
  parser->ranges[parser->range_count++] = (lrpfs_range){ start, end };
  return 1;
}

static int lrpfs_add_tensor_name(
  lrpfs_json *parser,
  size_t start,
  size_t length
) {
  for (size_t index = 0; index < parser->name_count; index++) {
    lrpfs_name name = parser->names[index];
    if (name.length == length &&
        memcmp(parser->data + name.start, parser->data + start, length) == 0) {
      return 0;
    }
  }
  if (parser->name_count == parser->name_capacity) {
    size_t capacity = parser->name_capacity == 0 ? 16U : parser->name_capacity * 2U;
    if (capacity < parser->name_capacity ||
        capacity > SIZE_MAX / sizeof(lrpfs_name)) {
      return 0;
    }
    lrpfs_name *grown = (lrpfs_name *)realloc(
      parser->names, capacity * sizeof(lrpfs_name)
    );
    if (grown == NULL) return 0;
    parser->names = grown;
    parser->name_capacity = capacity;
  }
  parser->names[parser->name_count++] = (lrpfs_name){ start, length };
  return 1;
}

static int lrpfs_parse_shape(lrpfs_json *parser, uint64_t *elements) {
  if (!lrpfs_consume(parser, '[')) return 0;
  lrpfs_skip_space(parser);
  uint64_t product = 1;
  if (parser->position < parser->length && parser->data[parser->position] == ']') {
    parser->position++;
    *elements = product;
    return 1;
  }
  for (;;) {
    uint64_t dimension;
    if (!lrpfs_parse_uint(parser, &dimension)) return 0;
    if (dimension != 0 && product > UINT64_MAX / dimension) return 0;
    product *= dimension;
    lrpfs_skip_space(parser);
    if (parser->position < parser->length && parser->data[parser->position] == ']') {
      parser->position++;
      *elements = product;
      return 1;
    }
    if (!lrpfs_consume(parser, ',')) return 0;
  }
}

static int lrpfs_parse_offsets(lrpfs_json *parser, uint64_t *start, uint64_t *end) {
  return lrpfs_consume(parser, '[') &&
         lrpfs_parse_uint(parser, start) &&
         lrpfs_consume(parser, ',') &&
         lrpfs_parse_uint(parser, end) &&
         lrpfs_consume(parser, ']');
}

static int lrpfs_parse_metadata(lrpfs_json *parser) {
  if (!lrpfs_consume(parser, '{')) return 0;
  lrpfs_skip_space(parser);
  if (parser->position < parser->length && parser->data[parser->position] == '}') {
    parser->position++;
    return 1;
  }
  for (;;) {
    size_t start, length;
    int escaped;
    if (!lrpfs_parse_string(parser, &start, &length, &escaped) ||
        !lrpfs_consume(parser, ':') ||
        !lrpfs_parse_string(parser, &start, &length, &escaped)) {
      return 0;
    }
    lrpfs_skip_space(parser);
    if (parser->position < parser->length && parser->data[parser->position] == '}') {
      parser->position++;
      return 1;
    }
    if (!lrpfs_consume(parser, ',')) return 0;
  }
}

static int lrpfs_parse_tensor(lrpfs_json *parser) {
  if (!lrpfs_consume(parser, '{')) return 0;
  int seen_dtype = 0;
  int seen_shape = 0;
  int seen_offsets = 0;
  int element_size = 0;
  uint64_t elements = 0;
  uint64_t start_offset = 0;
  uint64_t end_offset = 0;
  for (;;) {
    size_t key_start, key_length;
    int key_escaped;
    if (!lrpfs_parse_string(
          parser, &key_start, &key_length, &key_escaped
        ) || !lrpfs_consume(parser, ':')) {
      return 0;
    }
    if (lrpfs_key_equals(parser, key_start, key_length, key_escaped, "dtype")) {
      size_t value_start, value_length;
      int value_escaped;
      if (seen_dtype || !lrpfs_parse_string(
            parser, &value_start, &value_length, &value_escaped
          ) || value_escaped) {
        return 0;
      }
      element_size = lrpfs_dtype_size(parser->data + value_start, value_length);
      if (element_size == 0) return 0;
      seen_dtype = 1;
    } else if (lrpfs_key_equals(
                 parser, key_start, key_length, key_escaped, "shape"
               )) {
      if (seen_shape || !lrpfs_parse_shape(parser, &elements)) return 0;
      seen_shape = 1;
    } else if (lrpfs_key_equals(
                 parser, key_start, key_length, key_escaped, "data_offsets"
               )) {
      if (seen_offsets || !lrpfs_parse_offsets(
            parser, &start_offset, &end_offset
          )) {
        return 0;
      }
      seen_offsets = 1;
    } else {
      return 0;
    }
    lrpfs_skip_space(parser);
    if (parser->position < parser->length && parser->data[parser->position] == '}') {
      parser->position++;
      break;
    }
    if (!lrpfs_consume(parser, ',')) return 0;
  }
  if (!seen_dtype || !seen_shape || !seen_offsets ||
      start_offset > end_offset || end_offset > parser->tensor_data_length) {
    return 0;
  }
  uint64_t byte_count = end_offset - start_offset;
  if (elements > UINT64_MAX / (uint64_t)element_size ||
      elements * (uint64_t)element_size != byte_count) {
    return 0;
  }
  return lrpfs_add_range(parser, start_offset, end_offset);
}

static int lrpfs_range_compare(const void *left, const void *right) {
  const lrpfs_range *a = (const lrpfs_range *)left;
  const lrpfs_range *b = (const lrpfs_range *)right;
  if (a->start < b->start) return -1;
  if (a->start > b->start) return 1;
  if (a->end < b->end) return -1;
  if (a->end > b->end) return 1;
  return 0;
}

static int lrpfs_parse_header(lrpfs_json *parser) {
  if (!lrpfs_consume(parser, '{')) return 0;
  int seen_metadata = 0;
  lrpfs_skip_space(parser);
  if (parser->position < parser->length && parser->data[parser->position] == '}') {
    return 0;
  }
  for (;;) {
    size_t key_start, key_length;
    int key_escaped;
    if (!lrpfs_parse_string(
          parser, &key_start, &key_length, &key_escaped
        ) || !lrpfs_consume(parser, ':')) {
      return 0;
    }
    if (lrpfs_key_equals(
          parser, key_start, key_length, key_escaped, "__metadata__"
        )) {
      if (seen_metadata || !lrpfs_parse_metadata(parser)) return 0;
      seen_metadata = 1;
    } else if (key_escaped ||
               !lrpfs_add_tensor_name(parser, key_start, key_length) ||
               !lrpfs_parse_tensor(parser)) {
      return 0;
    }
    lrpfs_skip_space(parser);
    if (parser->position < parser->length && parser->data[parser->position] == '}') {
      parser->position++;
      break;
    }
    if (!lrpfs_consume(parser, ',')) return 0;
  }
  lrpfs_skip_space(parser);
  if (parser->position != parser->length || parser->range_count == 0) return 0;
  qsort(
    parser->ranges, parser->range_count, sizeof(lrpfs_range), lrpfs_range_compare
  );
  uint64_t cursor = 0;
  for (size_t index = 0; index < parser->range_count; index++) {
    if (parser->ranges[index].start != cursor) return 0;
    cursor = parser->ranges[index].end;
  }
  return cursor == parser->tensor_data_length;
}

int lrpfs_validate_safetensors_fd(int fd, int64_t file_size) {
  if (file_size < 9) return LRPFS_SAFETENSORS_INVALID;
  uint8_t prefix[8];
  if (!lrpfs_read_exact(fd, prefix, sizeof(prefix), 0)) return LRPFS_IO;
  uint64_t header_length = 0;
  for (size_t index = 0; index < 8; index++) {
    header_length |= (uint64_t)prefix[index] << (index * 8U);
  }
  if (header_length == 0 || header_length > 67108864U ||
      header_length > (uint64_t)file_size - 8U ||
      header_length > SIZE_MAX) {
    return LRPFS_SAFETENSORS_INVALID;
  }
  uint8_t *header = (uint8_t *)malloc((size_t)header_length);
  if (header == NULL) return LRPFS_IO;
  if (!lrpfs_read_exact(fd, header, (size_t)header_length, 8)) {
    free(header);
    return LRPFS_IO;
  }
  if (!lrpfs_utf8_valid(header, (size_t)header_length)) {
    free(header);
    return LRPFS_SAFETENSORS_INVALID;
  }
  lrpfs_json parser = {
    .data = header,
    .length = (size_t)header_length,
    .position = 0,
    .tensor_data_length = (uint64_t)file_size - 8U - header_length,
    .ranges = NULL,
    .range_count = 0,
    .range_capacity = 0,
    .names = NULL,
    .name_count = 0,
    .name_capacity = 0
  };
  int valid = lrpfs_parse_header(&parser);
  free(parser.names);
  free(parser.ranges);
  free(header);
  return valid ? LRPFS_OK : LRPFS_SAFETENSORS_INVALID;
}

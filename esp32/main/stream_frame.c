#include "stream_frame.h"

uint32_t stream_crc32(const uint8_t *data, size_t len) {
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < len; i++) {
        crc ^= data[i];
        for (int b = 0; b < 8; b++) {
            crc = (crc >> 1) ^ (0xEDB88320u & (uint32_t)(-(int32_t)(crc & 1u)));
        }
    }
    return ~crc;
}

// Fields are placed by hand rather than by casting a struct over the buffer, so
// the wire layout never depends on the compiler's padding or endianness.
static size_t put_u8(uint8_t *out, size_t at, uint8_t v) {
    out[at] = v;
    return at + 1;
}

static size_t put_u16(uint8_t *out, size_t at, uint16_t v) {
    out[at]     = (uint8_t)(v & 0xFFu);
    out[at + 1] = (uint8_t)(v >> 8);
    return at + 2;
}

static size_t put_u32(uint8_t *out, size_t at, uint32_t v) {
    out[at]     = (uint8_t)(v & 0xFFu);
    out[at + 1] = (uint8_t)((v >> 8) & 0xFFu);
    out[at + 2] = (uint8_t)((v >> 16) & 0xFFu);
    out[at + 3] = (uint8_t)((v >> 24) & 0xFFu);
    return at + 4;
}

size_t stream_build_frame(uint8_t *out, size_t cap, const stream_meta_t *meta,
                          const uint16_t *ymin, const uint16_t *ymax, size_t n_cols) {
    if (out == NULL || meta == NULL || ymin == NULL || ymax == NULL) {
        return 0;
    }
    if (n_cols == 0 || cap < stream_frame_len(n_cols)) {
        return 0;
    }

    size_t at = 0;
    at = put_u32(out, at, STREAM_MAGIC);
    at = put_u8(out, at, STREAM_VERSION);
    at = put_u8(out, at, meta->flags);
    at = put_u16(out, at, (uint16_t)n_cols);
    at = put_u32(out, at, meta->seq);
    at = put_u32(out, at, meta->sample_count);
    at = put_u16(out, at, meta->dec_factor);
    at = put_u16(out, at, meta->pre_count);
    at = put_u16(out, at, meta->post_count);
    at = put_u32(out, at, meta->trig_ptr);
    at = put_u16(out, at, meta->trig_level);
    at = put_u16(out, at, meta->overrange_cnt);
    at = put_u8(out, at, meta->afe_atten);
    at = put_u8(out, at, meta->afe_flags);
    at = put_u8(out, at, meta->lmh_atten);
    at = put_u8(out, at, 0);  // pad, keeps the column payload 16-bit aligned
    at = put_u16(out, at, meta->dac_offset);

    for (size_t c = 0; c < n_cols; c++) {
        at = put_u16(out, at, ymin[c]);
        at = put_u16(out, at, ymax[c]);
    }

    // The CRC covers everything after the magic word, so a host that resyncs
    // mid-stream can still validate the frame it landed on.
    at = put_u32(out, at, stream_crc32(out + 4, at - 4));
    return at;
}

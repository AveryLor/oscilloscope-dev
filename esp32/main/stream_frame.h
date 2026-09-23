#pragma once

/*
 * Frame packing for the host sample stream, kept free of ESP-IDF dependencies
 * so it builds and runs on a host compiler. The wire format is documented in
 * docs/STREAM.md and parsed by gui/src/frame.rs; keep all three in step.
 */

#include <stddef.h>
#include <stdint.h>

#define STREAM_MAGIC    0x53434F50u  // "SCOP", little-endian on the wire
#define STREAM_VERSION  1u
#define STREAM_HDR_BYTES 36u

// frame flags
#define STREAM_FLAG_PEAK      (1u << 0)  // record came from peak-detect mode
#define STREAM_FLAG_TRIGGERED (1u << 1)  // real trigger, not an AUTO timeout
#define STREAM_FLAG_OVERRANGE (1u << 2)  // at least one sample clipped

// afe_flags byte
#define STREAM_AFE_DC_COUPLED (1u << 0)  // else AC
#define STREAM_AFE_TERM_50R   (1u << 1)  // else 1 MOhm
#define STREAM_AFE_PREAMP_HG  (1u << 2)  // LMH6518 high-gain preamp

/* Everything in a frame except the column payload. */
typedef struct {
    uint8_t  flags;
    uint32_t seq;
    uint32_t sample_count;
    uint16_t dec_factor;
    uint16_t pre_count;
    uint16_t post_count;
    uint32_t trig_ptr;
    uint16_t trig_level;
    uint16_t overrange_cnt;
    uint8_t  afe_atten;
    uint8_t  afe_flags;
    uint8_t  lmh_atten;
    uint16_t dac_offset;
} stream_meta_t;

/* Bytes a frame of n_cols columns occupies. */
static inline size_t stream_frame_len(size_t n_cols) {
    return STREAM_HDR_BYTES + n_cols * 4u + 4u;
}

/*
 * Pack one frame into out. Returns the number of bytes written, or 0 if cap is
 * too small for stream_frame_len(n_cols).
 */
size_t stream_build_frame(uint8_t *out, size_t cap, const stream_meta_t *meta,
                          const uint16_t *ymin, const uint16_t *ymax, size_t n_cols);

/* CRC-32, reflected 0xEDB88320, init/final 0xFFFFFFFF. */
uint32_t stream_crc32(const uint8_t *data, size_t len);

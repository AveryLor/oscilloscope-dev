/*
 * Host-side tests for the wire-format packer. The matching decode side is
 * tested in gui/tests/c_interop.rs, which parses bytes this packer produced.
 */

#include <stdio.h>
#include <string.h>

#include "stream_frame.h"

static int failures;

static void check(int cond, const char *what) {
    if (!cond) {
        printf("  FAIL %s\n", what);
        failures++;
    }
}

static uint16_t rd_u16(const uint8_t *b, size_t at) {
    return (uint16_t)(b[at] | (b[at + 1] << 8));
}

static uint32_t rd_u32(const uint8_t *b, size_t at) {
    return (uint32_t)b[at] | ((uint32_t)b[at + 1] << 8)
         | ((uint32_t)b[at + 2] << 16) | ((uint32_t)b[at + 3] << 24);
}

/* The published reference value for the reflected CRC-32 of "123456789". */
static void crc_matches_reference_vector(void) {
    check(stream_crc32((const uint8_t *)"123456789", 9) == 0xCBF43926u,
          "CRC-32 matches the standard check value");
}

static void header_fields_land_at_documented_offsets(void) {
    enum { COLS = 4 };
    uint16_t ymin[COLS] = {1, 2, 3, 4};
    uint16_t ymax[COLS] = {11, 12, 13, 14};
    uint8_t buf[STREAM_HDR_BYTES + COLS * 4 + 4];

    stream_meta_t m = {
        .flags = STREAM_FLAG_TRIGGERED, .seq = 0x11223344,
        .sample_count = 0x55667788, .dec_factor = 0x0102,
        .pre_count = 0x0304, .post_count = 0x0506, .trig_ptr = 0x090A0B0C,
        .trig_level = 0x0708, .overrange_cnt = 0, .afe_atten = 2,
        .afe_flags = STREAM_AFE_TERM_50R, .lmh_atten = 9, .dac_offset = 0x0D0E,
    };

    size_t len = stream_build_frame(buf, sizeof(buf), &m, ymin, ymax, COLS);
    check(len == stream_frame_len(COLS), "frame length matches the helper");

    /* Offsets per docs/STREAM.md. */
    check(rd_u32(buf, 0) == STREAM_MAGIC, "magic at 0");
    check(buf[4] == STREAM_VERSION, "version at 4");
    check(buf[5] == STREAM_FLAG_TRIGGERED, "flags at 5");
    check(rd_u16(buf, 6) == COLS, "n_cols at 6");
    check(rd_u32(buf, 8) == 0x11223344u, "seq at 8");
    check(rd_u32(buf, 12) == 0x55667788u, "sample_count at 12");
    check(rd_u16(buf, 16) == 0x0102, "dec_factor at 16");
    check(rd_u16(buf, 18) == 0x0304, "pre_count at 18");
    check(rd_u16(buf, 20) == 0x0506, "post_count at 20");
    check(rd_u32(buf, 22) == 0x090A0B0Cu, "trig_ptr at 22");
    check(rd_u16(buf, 26) == 0x0708, "trig_level at 26");
    check(rd_u16(buf, 28) == 0, "overrange_cnt at 28");
    check(buf[30] == 2, "afe_atten at 30");
    check(buf[31] == STREAM_AFE_TERM_50R, "afe_flags at 31");
    check(buf[32] == 9, "lmh_atten at 32");
    check(buf[33] == 0, "pad at 33");
    check(rd_u16(buf, 34) == 0x0D0E, "dac_offset at 34");

    for (int c = 0; c < COLS; c++) {
        check(rd_u16(buf, STREAM_HDR_BYTES + c * 4) == ymin[c], "column min");
        check(rd_u16(buf, STREAM_HDR_BYTES + c * 4 + 2) == ymax[c], "column max");
    }

    size_t crc_at = STREAM_HDR_BYTES + COLS * 4;
    check(rd_u32(buf, crc_at) == stream_crc32(buf + 4, crc_at - 4),
          "trailing CRC covers everything after the magic word");
}

static void refuses_a_buffer_that_is_too_small(void) {
    uint16_t y[2] = {0, 0};
    uint8_t small[8];
    stream_meta_t m;
    memset(&m, 0, sizeof(m));
    check(stream_build_frame(small, sizeof(small), &m, y, y, 2) == 0,
          "undersized buffer is refused rather than overrun");
    check(stream_build_frame(small, sizeof(small), &m, y, y, 0) == 0,
          "zero columns is refused");
}

int main(void) {
    crc_matches_reference_vector();
    header_fields_land_at_documented_offsets();
    refuses_a_buffer_that_is_too_small();

    if (failures == 0) {
        printf("PASS test_stream_frame\n");
        return 0;
    }
    printf("FAIL test_stream_frame (%d checks failed)\n", failures);
    return 1;
}

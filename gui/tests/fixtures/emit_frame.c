/* Emits one frame built by the real firmware packer, for the Rust parser to
 * read back. Verifies the two implementations of the wire format agree. */
#include <stdio.h>
#include <stdlib.h>
#include "stream_frame.h"

#define N_COLS 1000

int main(void) {
    static uint16_t ymin[N_COLS], ymax[N_COLS];
    for (int c = 0; c < N_COLS; c++) {
        ymin[c] = (uint16_t)(400 + (c % 100));
        ymax[c] = (uint16_t)(600 + (c % 100));
    }

    stream_meta_t meta = {
        .flags         = STREAM_FLAG_TRIGGERED | STREAM_FLAG_OVERRANGE,
        .seq           = 0xDEADBEEF,
        .sample_count  = 16384,
        .dec_factor    = 7,
        .pre_count     = 1024,
        .post_count    = 2048,
        .trig_ptr      = 8192,
        .trig_level    = 512,
        .overrange_cnt = 0,
        .afe_atten     = 2,
        .afe_flags     = STREAM_AFE_DC_COUPLED | STREAM_AFE_PREAMP_HG,
        .lmh_atten     = 6,
        .dac_offset    = 2048,
    };

    static uint8_t buf[STREAM_HDR_BYTES + N_COLS * 4 + 4];
    size_t len = stream_build_frame(buf, sizeof(buf), &meta, ymin, ymax, N_COLS);
    if (len != stream_frame_len(N_COLS)) {
        fprintf(stderr, "bad length %zu\n", len);
        return 1;
    }

    /* Check the CRC implementation against the standard reference vector, the
     * same one gui/src/frame.rs asserts on. */
    if (stream_crc32((const uint8_t *)"123456789", 9) != 0xCBF43926u) {
        fprintf(stderr, "crc32 reference vector failed\n");
        return 1;
    }

    /* Lead with junk so the host has to resync on the magic word, and append a
     * second frame so the test covers back-to-back framing too. */
    const char junk[] = "I (123) stray log line\n";
    fwrite(junk, 1, sizeof(junk) - 1, stdout);
    fwrite(buf, 1, len, stdout);

    meta.seq = 0xDEADBEF0;
    len = stream_build_frame(buf, sizeof(buf), &meta, ymin, ymax, N_COLS);
    fwrite(buf, 1, len, stdout);
    return 0;
}

/*
 * Host-side tests for the column reduction. These build with a plain compiler,
 * no ESP-IDF required:
 *
 *   cd esp32 && make -C test
 */

#include <stdio.h>
#include <string.h>

#include "envelope.h"

static int failures;

static void check(int cond, const char *what) {
    if (!cond) {
        printf("  FAIL %s\n", what);
        failures++;
    }
}

/* One entry per column: each column keeps exactly its own sample. */
static void one_entry_per_column(void) {
    uint16_t ymin[4], ymax[4];
    envelope_acc_t a;
    envelope_begin(&a, ymin, ymax, 4, 4, 512);
    for (uint32_t i = 0; i < 4; i++) {
        envelope_push(&a, i, (uint16_t)(100 + i));
    }
    envelope_finish(&a);

    for (int c = 0; c < 4; c++) {
        check(ymin[c] == 100 + c, "single-sample column min");
        check(ymax[c] == 100 + c, "single-sample column max");
    }
}

/* Several entries per column: the column spans their min and max. */
static void many_entries_per_column(void) {
    uint16_t ymin[2], ymax[2];
    envelope_acc_t a;
    envelope_begin(&a, ymin, ymax, 2, 8, 512);

    /* First four entries land in column 0, last four in column 1. */
    uint16_t codes[8] = {500, 200, 900, 400, 50, 60, 70, 1000};
    for (uint32_t i = 0; i < 8; i++) {
        envelope_push(&a, i, codes[i]);
    }
    envelope_finish(&a);

    check(ymin[0] == 200, "column 0 keeps the lowest of its samples");
    check(ymax[0] == 900, "column 0 keeps the highest of its samples");
    check(ymin[1] == 50, "column 1 keeps the lowest of its samples");
    check(ymax[1] == 1000, "column 1 keeps the highest of its samples");
}

/*
 * A record shorter than the column count leaves gaps. Every column must still
 * be filled, by holding the previous value rather than falling back to the
 * fill code, or the trace would alternate between signal and mid-scale.
 */
static void record_shorter_than_columns_holds_values(void) {
    uint16_t ymin[10], ymax[10];
    envelope_acc_t a;
    envelope_begin(&a, ymin, ymax, 10, 3, 512);
    envelope_push(&a, 0, 100);
    envelope_push(&a, 1, 200);
    envelope_push(&a, 2, 300);
    envelope_finish(&a);

    for (int c = 0; c < 10; c++) {
        check(ymin[c] != 512 || ymax[c] != 512, "no column left at the fill value");
    }
    /* Entry 0 covers columns 0-2, entry 1 covers 3-5, entry 2 covers 6-9. */
    check(ymin[0] == 100 && ymin[2] == 100, "first sample held across its span");
    check(ymin[3] == 200 && ymin[5] == 200, "second sample held across its span");
    check(ymin[6] == 300 && ymin[9] == 300, "last sample held to the final column");
}

/* An empty record leaves every column at the fill value and does not crash. */
static void empty_record_is_defined(void) {
    uint16_t ymin[5], ymax[5];
    envelope_acc_t a;
    envelope_begin(&a, ymin, ymax, 5, 0, 512);
    envelope_push(&a, 0, 999);  /* must be ignored: total is 0 */
    envelope_finish(&a);

    for (int c = 0; c < 5; c++) {
        check(ymin[c] == 512 && ymax[c] == 512, "empty record stays at fill");
    }
}

/* More entries than columns, the normal case: nothing runs past the array. */
static void record_longer_than_columns_stays_in_bounds(void) {
    enum { COLS = 16, ENTRIES = 16384 };
    static uint16_t ymin[COLS + 1], ymax[COLS + 1];
    ymin[COLS] = 0xBEEF;
    ymax[COLS] = 0xBEEF;

    envelope_acc_t a;
    envelope_begin(&a, ymin, ymax, COLS, ENTRIES, 512);
    for (uint32_t i = 0; i < ENTRIES; i++) {
        envelope_push(&a, i, (uint16_t)(i % 1024));
    }
    envelope_finish(&a);

    check(ymin[COLS] == 0xBEEF && ymax[COLS] == 0xBEEF, "no write past the last column");
    for (int c = 0; c < COLS; c++) {
        check(ymin[c] <= ymax[c], "column min does not exceed its max");
    }
}

int main(void) {
    one_entry_per_column();
    many_entries_per_column();
    record_shorter_than_columns_holds_values();
    empty_record_is_defined();
    record_longer_than_columns_stays_in_bounds();

    if (failures == 0) {
        printf("PASS test_envelope\n");
        return 0;
    }
    printf("FAIL test_envelope (%d checks failed)\n", failures);
    return 1;
}

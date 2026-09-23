#pragma once

/*
 * Min/max column reduction, kept free of ESP-IDF dependencies so it builds and
 * runs on a host compiler.
 *
 * A record is folded into a fixed number of columns as the samples arrive, so
 * a 32 kB record never has to be held whole. Keeping both the minimum and the
 * maximum per column means a transient narrower than one column still shows as
 * height instead of disappearing, which is what plain subsampling would do.
 */

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint16_t *ymin;
    uint16_t *ymax;
    size_t    n_cols;
    uint32_t  total;    // entries the record will deliver
    size_t    cur_col;
    bool      col_seen;
    uint16_t  cur_min;
    uint16_t  cur_max;
} envelope_acc_t;

/*
 * Prepare an accumulator over n_cols columns for a record of `total` entries,
 * filling every column with `fill` so an empty or short record still leaves
 * defined output.
 */
void envelope_begin(envelope_acc_t *acc, uint16_t *ymin, uint16_t *ymax,
                    size_t n_cols, uint32_t total, uint16_t fill);

/* Fold entry `index` (0-based, < total) into its column. */
void envelope_push(envelope_acc_t *acc, uint32_t index, uint16_t code);

/* Flush the column in progress and hold it across any trailing columns. */
void envelope_finish(envelope_acc_t *acc);

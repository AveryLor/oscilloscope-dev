#include "envelope.h"

// Flush the column in progress, then hold its value across every column up to
// (not including) `upto`. A record shorter than n_cols skips columns, and
// holding keeps the trace continuous instead of alternating with the fill.
static void flush_through(envelope_acc_t *acc, size_t upto) {
    if (!acc->col_seen) {
        return;
    }
    acc->ymin[acc->cur_col] = acc->cur_min;
    acc->ymax[acc->cur_col] = acc->cur_max;
    for (size_t g = acc->cur_col + 1; g < upto; g++) {
        acc->ymin[g] = acc->cur_min;
        acc->ymax[g] = acc->cur_max;
    }
}

void envelope_begin(envelope_acc_t *acc, uint16_t *ymin, uint16_t *ymax,
                    size_t n_cols, uint32_t total, uint16_t fill) {
    acc->ymin     = ymin;
    acc->ymax     = ymax;
    acc->n_cols   = n_cols;
    acc->total    = total;
    acc->cur_col  = 0;
    acc->col_seen = false;
    acc->cur_min  = UINT16_MAX;
    acc->cur_max  = 0;

    for (size_t c = 0; c < n_cols; c++) {
        ymin[c] = fill;
        ymax[c] = fill;
    }
}

void envelope_push(envelope_acc_t *acc, uint32_t index, uint16_t code) {
    if (acc->total == 0 || acc->n_cols == 0) {
        return;
    }

    size_t col = (size_t)(((uint64_t)index * acc->n_cols) / acc->total);
    if (col >= acc->n_cols) {
        col = acc->n_cols - 1;
    }

    if (col != acc->cur_col) {
        flush_through(acc, col);
        acc->cur_col  = col;
        acc->col_seen = false;
        acc->cur_min  = UINT16_MAX;
        acc->cur_max  = 0;
    }

    if (code < acc->cur_min) acc->cur_min = code;
    if (code > acc->cur_max) acc->cur_max = code;
    acc->col_seen = true;
}

void envelope_finish(envelope_acc_t *acc) {
    flush_through(acc, acc->n_cols);
}

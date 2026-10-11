#include "deskew_find.h"

#include <stdbool.h>

#define TAP_MID 64

int deskew_find_crossover(const uint16_t *a, const uint16_t *b, const uint8_t *taps,
                          size_t n, uint32_t min_activity) {
    int last_b = -1; // index of the most recent B-dominant point
    for (size_t i = 0; i < n; i++) {
        if ((uint32_t)a[i] + b[i] < min_activity) {
            last_b = -1; // a dead point breaks the pair
            continue;
        }
        if (b[i] > a[i]) {
            last_b = (int)i;
        } else if (a[i] > b[i] && last_b >= 0) {
            return (taps[last_b] + taps[i] + 1) / 2;
        }
    }
    return DESKEW_NONE;
}

static int dist_from_mid(int tap) {
    return tap > TAP_MID ? tap - TAP_MID : TAP_MID - tap;
}

int deskew_pick_phase(const int16_t xover[DESKEW_PHASES][DESKEW_LANES],
                      const uint8_t active[DESKEW_LANES]) {
    int best = DESKEW_NONE;
    unsigned best_found = 0;
    int best_worst = 0;

    for (unsigned p = 0; p < DESKEW_PHASES; p++) {
        unsigned found = 0;
        int worst = 0;
        for (unsigned l = 0; l < DESKEW_LANES; l++) {
            if (!active[l] || xover[p][l] == DESKEW_NONE) {
                continue;
            }
            found++;
            int d = dist_from_mid(xover[p][l]);
            if (d > worst) worst = d;
        }
        if (found == 0) {
            continue;
        }
        if (found > best_found || (found == best_found && worst < best_worst)) {
            best       = (int)p;
            best_found = found;
            best_worst = worst;
        }
    }
    return best;
}

unsigned deskew_fill_taps(const int16_t xover[DESKEW_LANES], uint8_t taps_out[DESKEW_LANES]) {
    // Insertion-sort the found taps to take their median.
    int16_t sorted[DESKEW_LANES];
    unsigned n = 0;
    for (unsigned l = 0; l < DESKEW_LANES; l++) {
        if (xover[l] == DESKEW_NONE) {
            continue;
        }
        unsigned j = n++;
        while (j > 0 && sorted[j - 1] > xover[l]) {
            sorted[j] = sorted[j - 1];
            j--;
        }
        sorted[j] = xover[l];
    }
    const uint8_t fallback = n ? (uint8_t)sorted[n / 2] : 0;

    for (unsigned l = 0; l < DESKEW_LANES; l++) {
        taps_out[l] = (xover[l] == DESKEW_NONE) ? fallback : (uint8_t)xover[l];
    }
    return n;
}

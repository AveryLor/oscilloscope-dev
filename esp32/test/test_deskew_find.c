/*
 * Host-side tests for the ADC deskew decision logic (deskew_find.c): finding
 * the B->A eye crossover in a tap sweep, choosing the PLL phase, and filling
 * lanes that found no crossover.
 */

#include <stdio.h>
#include <string.h>

#include "deskew_find.h"

static int failures;

static void check(int cond, const char *what) {
    if (!cond) {
        printf("  FAIL %s\n", what);
        failures++;
    }
}

// Synthesise a coarse sweep where the lane's edge crosses the rising sample at
// tap rise_x (A->B) and the falling sample at tap fall_x (B->A).
static void synth(uint16_t *a, uint16_t *b, uint8_t *taps, size_t n, int step,
                  int rise_x, int fall_x, uint16_t act) {
    for (size_t i = 0; i < n; i++) {
        int t = (int)i * step;
        taps[i] = (uint8_t)t;
        int in_b = (t >= rise_x && t < fall_x);
        a[i] = in_b ? 0 : act;
        b[i] = in_b ? act : 0;
    }
}

static void crossover(void) {
    uint16_t a[32], b[32];
    uint8_t  t[32];

    synth(a, b, t, 32, 4, 10, 70, 500);
    check(deskew_find_crossover(a, b, t, 32, 64) == 70,
          "B->A crossover lands between the bracketing taps (68,72)");

    // Starts B-dominant (the rising-sample crossover is below tap 0).
    synth(a, b, t, 32, 4, -50, 30, 500);
    check(deskew_find_crossover(a, b, t, 32, 64) == 30, "crossover when sweep starts in B");

    // A->B only, no B->A within range.
    synth(a, b, t, 32, 4, 60, 500, 500);
    check(deskew_find_crossover(a, b, t, 32, 64) == DESKEW_NONE, "A->B alone is not a match");

    // A lane that never toggles.
    synth(a, b, t, 32, 4, 10, 70, 10);
    check(deskew_find_crossover(a, b, t, 32, 64) == DESKEW_NONE, "idle lane finds nothing");

    // A dead point between B and A breaks the pair.
    synth(a, b, t, 32, 4, 10, 70, 500);
    a[17] = 0; b[17] = 0;   // tap 68
    check(deskew_find_crossover(a, b, t, 32, 64) == DESKEW_NONE,
          "a dead point between B and A is not bridged");

    // Fine sweep, step 1.
    synth(a, b, t, 9, 1, -10, 5, 500);
    check(deskew_find_crossover(a, b, t, 9, 64) == 5, "fine sweep rounds the midpoint up");
}

static void pick_phase(void) {
    int16_t x[DESKEW_PHASES][DESKEW_LANES];
    uint8_t active[DESKEW_LANES];
    for (unsigned p = 0; p < DESKEW_PHASES; p++)
        for (unsigned l = 0; l < DESKEW_LANES; l++) x[p][l] = DESKEW_NONE;
    memset(active, 1, sizeof(active));
    active[10] = 0;   // adc_or idle

    check(deskew_pick_phase(x, active) == DESKEW_NONE, "nothing found -> no phase");

    // Phase 3 finds 9 lanes, phase 5 and 6 find all 10 active ones; phase 6 is
    // better centred.
    for (unsigned l = 0; l < 9; l++) x[3][l] = 64;
    for (unsigned l = 0; l < 10; l++) { x[5][l] = (int16_t)(20 + l); x[6][l] = (int16_t)(60 + l); }
    x[7][10] = 64;    // only the inactive lane: ignored
    check(deskew_pick_phase(x, active) == 6, "most lanes, then best centred");
}

static void fill(void) {
    int16_t x[DESKEW_LANES] = {40, 42, 44, DESKEW_NONE, 46, 48, 50, 52, 54, 56, DESKEW_NONE};
    uint8_t taps[DESKEW_LANES];
    unsigned n = deskew_fill_taps(x, taps);
    check(n == 9, "found-lane count");
    check(taps[0] == 40 && taps[9] == 56, "found lanes keep their crossover");
    check(taps[3] == 48 && taps[10] == 48, "missing lanes get the median");

    int16_t none[DESKEW_LANES];
    for (unsigned l = 0; l < DESKEW_LANES; l++) none[l] = DESKEW_NONE;
    check(deskew_fill_taps(none, taps) == 0 && taps[5] == 0, "nothing found -> tap 0");
}

int main(void) {
    crossover();
    pick_phase();
    fill();

    if (failures == 0) {
        printf("PASS test_deskew_find\n");
        return 0;
    }
    printf("FAIL test_deskew_find (%d checks failed)\n", failures);
    return 1;
}

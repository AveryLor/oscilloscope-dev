/*
 * Host-side tests for the vertical-scale ladder the knob walks.
 */

#include <stdio.h>

#include "vscale.h"

static int failures;

static void check(int cond, const char *what) {
    if (!cond) {
        printf("  FAIL %s\n", what);
        failures++;
    }
}

static int gain_of(vscale_step_t s) {
    return vscale_gain_ddb(s.atten, s.preamp, s.lmh_atten);
}

static void ladder_is_even_2db_steps(void) {
    check(gain_of(vscale_at(0)) == 388, "step 0 is 38.8 dB");
    check(gain_of(vscale_at(VSCALE_STEPS - 1)) == -412, "last step is -41.2 dB");
    for (int i = 1; i < VSCALE_STEPS; i++) {
        check(gain_of(vscale_at(i - 1)) - gain_of(vscale_at(i)) == VSCALE_STEP_DDB,
              "every step is exactly 2 dB below the previous one");
    }
}

static void fields_stay_legal(void) {
    for (int i = 0; i < VSCALE_STEPS; i++) {
        vscale_step_t s = vscale_at(i);
        check(s.atten <= 2, "atten in range");
        check(s.preamp <= 1, "preamp in range");
        check(s.lmh_atten <= 10, "ladder code in range");
    }
}

static void index_round_trips(void) {
    for (int i = 0; i < VSCALE_STEPS; i++) {
        vscale_step_t s = vscale_at(i);
        check(vscale_index_of(s.atten, s.preamp, s.lmh_atten) == i, "index_of(at(i)) == i");
    }
}

static void relays_move_only_twice(void) {
    int changes = 0;
    for (int i = 1; i < VSCALE_STEPS; i++) {
        if (vscale_at(i).atten != vscale_at(i - 1).atten) {
            changes++;
        }
        check(vscale_at(i).atten >= vscale_at(i - 1).atten, "divider never steps backwards");
    }
    check(changes == 2, "divider changes exactly twice across the range");
}

static void index_clamps(void) {
    check(gain_of(vscale_at(-5)) == gain_of(vscale_at(0)), "below range clamps to step 0");
    check(gain_of(vscale_at(1000)) == gain_of(vscale_at(VSCALE_STEPS - 1)),
          "above range clamps to the last step");
}

static void off_ladder_settings_map_by_gain(void) {
    // The power-on default: 100x, low gain, ladder 10.
    check(vscale_index_of(2, 0, 10) == VSCALE_STEPS - 1, "power-on default is the last step");
    // 10x with the high-gain preamp is 18.8 dB, the same gain as step 10.
    check(vscale_index_of(1, 1, 0) == 10, "10x HG ladder 0 maps to the 18.8 dB step");
    // 100x HG ladder 0 is -1.2 dB, the same gain as 1x LG ladder 10 (step 20).
    check(vscale_index_of(2, 1, 0) == 20, "100x HG ladder 0 maps to the -1.2 dB step");
    // 10x LG ladder 0 is -1.2 dB as well.
    check(vscale_index_of(1, 0, 0) == 20, "10x LG ladder 0 maps to the -1.2 dB step");
    // 1x HG ladder 10 duplicates 1x LG ladder 0.
    check(vscale_index_of(0, 1, 10) == 10, "1x HG ladder 10 maps to step 10");
}

int main(void) {
    ladder_is_even_2db_steps();
    fields_stay_legal();
    index_round_trips();
    relays_move_only_twice();
    index_clamps();
    off_ladder_settings_map_by_gain();

    if (failures) {
        printf("FAIL test_vscale (%d)\n", failures);
        return 1;
    }
    printf("PASS test_vscale\n");
    return 0;
}

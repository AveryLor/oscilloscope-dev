#include "vscale.h"

#define PREAMP_LG_DDB 188 // 18.8 dB
#define PREAMP_HG_DDB 388 // 38.8 dB
#define LADDER_DDB    20  // 2 dB per ladder code
#define DIVIDER_DDB   200 // 20 dB per divider decade
#define TOP_DDB       PREAMP_HG_DDB // gain at step 0

static int clamp_index(int index) {
    if (index < 0) {
        return 0;
    }
    if (index > VSCALE_STEPS - 1) {
        return VSCALE_STEPS - 1;
    }
    return index;
}

int vscale_gain_ddb(uint8_t atten, uint8_t preamp, uint8_t lmh_atten) {
    return (preamp ? PREAMP_HG_DDB : PREAMP_LG_DDB) - LADDER_DDB * (int)lmh_atten -
           DIVIDER_DDB * (int)atten;
}

int vscale_index_of(uint8_t atten, uint8_t preamp, uint8_t lmh_atten) {
    const int below_top = TOP_DDB - vscale_gain_ddb(atten, preamp, lmh_atten);
    // Round to the nearest step; below_top can be negative only for inputs
    // outside the legal field ranges, which clamp to step 0.
    int index;
    if (below_top >= 0) {
        index = (below_top + VSCALE_STEP_DDB / 2) / VSCALE_STEP_DDB;
    } else {
        index = 0;
    }
    return clamp_index(index);
}

vscale_step_t vscale_at(int index) {
    const int i = clamp_index(index);
    vscale_step_t s;
    if (i <= 9) {
        s = (vscale_step_t){.atten = 0, .preamp = 1, .lmh_atten = (uint8_t)i};
    } else if (i <= 20) {
        s = (vscale_step_t){.atten = 0, .preamp = 0, .lmh_atten = (uint8_t)(i - 10)};
    } else if (i <= 30) {
        s = (vscale_step_t){.atten = 1, .preamp = 0, .lmh_atten = (uint8_t)(i - 20)};
    } else {
        s = (vscale_step_t){.atten = 2, .preamp = 0, .lmh_atten = (uint8_t)(i - 30)};
    }
    return s;
}

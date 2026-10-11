#pragma once

/*
 * Pure decision logic for ADC deskew calibration, kept free of ESP-IDF so it
 * builds and runs on a host compiler (esp32/test/test_deskew_find.c). deskew.c
 * does the register traffic and feeds the measured eye counts in here.
 *
 * Background (docs/PROTOCOL.md "ADC deskew"): for one lane at one tap, the
 * FPGA's eye monitor counts A = edges in the half period before the rising
 * sample and B = edges in the half period after it. As the tap grows the
 * lane's edges move later; where the counts swing from B to A the edge sits on
 * the falling sample, so the rising sample is mid-eye. That tap is the target.
 */

#include <stddef.h>
#include <stdint.h>

#define DESKEW_LANES   11u   // adc_d[0..9], adc_or
#define DESKEW_TAPS    128u  // IODELAY taps 0..127
#define DESKEW_PHASES  16u   // rPLL PSDA steps
#define DESKEW_NONE    (-1)

/*
 * Finds the B->A crossover in a sweep of n points taken at increasing taps.
 * a[i], b[i] are the eye counts at taps[i]. A point only counts if it saw at
 * least min_activity edges (a + b). Returns the tap halfway between the last
 * B-dominant point and the first A-dominant point after it, or DESKEW_NONE if
 * the sweep has no such pair.
 */
int deskew_find_crossover(const uint16_t *a, const uint16_t *b, const uint8_t *taps,
                          size_t n, uint32_t min_activity);

/*
 * Picks the PLL phase to use from a full sweep. xover[p][l] is lane l's
 * crossover tap at phase p, or DESKEW_NONE. active[l] is nonzero for lanes
 * that toggled at all during calibration; inactive lanes (adc_or, normally)
 * are ignored. The phase that finds the most active lanes wins; a tie goes to
 * the phase whose worst crossover is closest to mid-range (tap 64), leaving
 * the most room for drift either way. Returns DESKEW_NONE if no phase found
 * any lane.
 */
int deskew_pick_phase(const int16_t xover[DESKEW_PHASES][DESKEW_LANES],
                      const uint8_t active[DESKEW_LANES]);

/*
 * Fills taps_out for a chosen phase. Lanes with a crossover get it; lanes
 * without one (inactive, or not found) get the median of the found lanes,
 * since their traces most likely skew like their neighbours. Returns the
 * number of lanes that had a crossover of their own.
 */
unsigned deskew_fill_taps(const int16_t xover[DESKEW_LANES], uint8_t taps_out[DESKEW_LANES]);

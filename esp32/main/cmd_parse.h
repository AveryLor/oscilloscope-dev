#pragma once

/*
 * Host -> ESP32 control command grammar, kept free of ESP-IDF dependencies so
 * it builds and runs on a host compiler. Parses one line at a time; see
 * docs/CONTROL.md for the full grammar and rationale.
 *
 * One command per line, space-separated fields, terminated by '\n' (a
 * trailing '\r' is tolerated and stripped by the caller before parsing).
 * There is no reply: a bad line is simply dropped, and the ESP32 -> host
 * sample stream (stream_frame.h) already echoes every field these commands
 * set, so the GUI confirms a command landed by watching the next frame.
 */

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum {
    CMD_SET_TIMEBASE,
    CMD_SET_HOFFSET,
    CMD_SET_TRIGGER,
    CMD_SET_VERTICAL,
    CMD_SET_COUPLING,
    CMD_SET_TERM,
} cmd_kind_t;

typedef struct {
    cmd_kind_t kind;
    union {
        struct {
            uint16_t dec_factor;
        } timebase;
        struct {
            uint16_t pre_count;
            uint16_t post_count;
        } hoffset;
        struct {
            uint16_t level;  // 0..1023
            uint8_t  src;    // 0=level 1=ext 2=force
            uint8_t  edge;   // 0=rising 1=falling 2=either
            uint8_t  hyst;
        } trigger;
        struct {
            uint8_t  atten;       // 0=1x 1=10x 2=100x
            uint8_t  preamp;      // 0=LG 1=HG
            uint8_t  lmh_atten;   // 0..10
            uint16_t offset_code; // 0..4095
        } vertical;
        struct {
            bool dc_coupled;
        } coupling;
        struct {
            bool term_50r;
        } term;
    } as;
} cmd_t;

/*
 * Parses exactly the len bytes at line (no NUL-termination assumed, never
 * reads line[len] or beyond). Returns false on any malformed input: unknown
 * keyword, wrong field count, a non-numeric token, an out-of-range value, or
 * trailing garbage after the last field. Never partially fills *out.
 */
bool cmd_parse_line(const char *line, size_t len, cmd_t *out);

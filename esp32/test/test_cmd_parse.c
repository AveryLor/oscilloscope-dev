/*
 * Host-side tests for the control-command line parser. The matching encode
 * side is tested in gui/tests/test_control.py.
 */

#include <stdio.h>
#include <string.h>

#include "cmd_parse.h"

static int failures;

static void check(int cond, const char *what) {
    if (!cond) {
        printf("  FAIL %s\n", what);
        failures++;
    }
}

static bool parse(const char *s, cmd_t *out) {
    return cmd_parse_line(s, strlen(s), out);
}

static void valid_timebase(void) {
    cmd_t c;
    check(parse("SET_TIMEBASE 1234", &c), "SET_TIMEBASE parses");
    check(c.kind == CMD_SET_TIMEBASE, "SET_TIMEBASE kind");
    check(c.as.timebase.dec_factor == 1234, "SET_TIMEBASE value");

    check(parse("SET_TIMEBASE 0", &c), "SET_TIMEBASE accepts 0");
    check(parse("SET_TIMEBASE 65535", &c), "SET_TIMEBASE accepts max u16");
    check(!parse("SET_TIMEBASE 65536", &c), "SET_TIMEBASE rejects overflow");
}

static void valid_hoffset(void) {
    cmd_t c;
    check(parse("SET_HOFFSET 100 200", &c), "SET_HOFFSET parses");
    check(c.kind == CMD_SET_HOFFSET, "SET_HOFFSET kind");
    check(c.as.hoffset.pre_count == 100, "SET_HOFFSET pre");
    check(c.as.hoffset.post_count == 200, "SET_HOFFSET post");
}

static void valid_trigger(void) {
    cmd_t c;
    check(parse("SET_TRIGGER 512 0 0 8", &c), "SET_TRIGGER parses");
    check(c.kind == CMD_SET_TRIGGER, "SET_TRIGGER kind");
    check(c.as.trigger.level == 512, "SET_TRIGGER level");
    check(c.as.trigger.src == 0, "SET_TRIGGER src");
    check(c.as.trigger.edge == 0, "SET_TRIGGER edge");
    check(c.as.trigger.hyst == 8, "SET_TRIGGER hyst");

    /* every src (0-2) and edge (0-2) value */
    for (int src = 0; src <= 2; src++) {
        char line[64];
        snprintf(line, sizeof(line), "SET_TRIGGER 100 %d 1 5", src);
        check(parse(line, &c) && c.as.trigger.src == (uint8_t)src, "trigger src range");
    }
    for (int edge = 0; edge <= 2; edge++) {
        char line[64];
        snprintf(line, sizeof(line), "SET_TRIGGER 100 1 %d 5", edge);
        check(parse(line, &c) && c.as.trigger.edge == (uint8_t)edge, "trigger edge range");
    }

    check(!parse("SET_TRIGGER 1024 0 0 8", &c), "SET_TRIGGER rejects level > 1023");
    check(!parse("SET_TRIGGER 100 3 0 8", &c), "SET_TRIGGER rejects src > 2");
    check(!parse("SET_TRIGGER 100 0 3 8", &c), "SET_TRIGGER rejects edge > 2");
    check(!parse("SET_TRIGGER 100 0 0 256", &c), "SET_TRIGGER rejects hyst > 255");
}

static void valid_vertical(void) {
    cmd_t c;
    check(parse("SET_VERTICAL 1 1 5 2048", &c), "SET_VERTICAL parses");
    check(c.kind == CMD_SET_VERTICAL, "SET_VERTICAL kind");
    check(c.as.vertical.atten == 1, "SET_VERTICAL atten");
    check(c.as.vertical.preamp == 1, "SET_VERTICAL preamp");
    check(c.as.vertical.lmh_atten == 5, "SET_VERTICAL lmh_atten");
    check(c.as.vertical.offset_code == 2048, "SET_VERTICAL offset_code");

    for (int atten = 0; atten <= 2; atten++) {
        char line[64];
        snprintf(line, sizeof(line), "SET_VERTICAL %d 0 0 0", atten);
        check(parse(line, &c) && c.as.vertical.atten == (uint8_t)atten, "vertical atten range");
    }
    check(!parse("SET_VERTICAL 3 0 0 0", &c), "SET_VERTICAL rejects atten > 2");
    check(!parse("SET_VERTICAL 0 2 0 0", &c), "SET_VERTICAL rejects preamp > 1");
    check(!parse("SET_VERTICAL 0 0 11 0", &c), "SET_VERTICAL rejects lmh_atten > 10");
    check(!parse("SET_VERTICAL 0 0 0 4096", &c), "SET_VERTICAL rejects offset_code > 4095");
}

static void valid_coupling_and_term(void) {
    cmd_t c;
    check(parse("SET_COUPLING 1", &c) && c.kind == CMD_SET_COUPLING && c.as.coupling.dc_coupled,
          "SET_COUPLING 1 -> DC");
    check(parse("SET_COUPLING 0", &c) && !c.as.coupling.dc_coupled,
          "SET_COUPLING 0 -> AC");
    check(!parse("SET_COUPLING 2", &c), "SET_COUPLING rejects out-of-range mode");

    check(parse("SET_TERM 1", &c) && c.kind == CMD_SET_TERM && c.as.term.term_50r,
          "SET_TERM 1 -> 50R");
    check(parse("SET_TERM 0", &c) && !c.as.term.term_50r,
          "SET_TERM 0 -> 1M");
    check(!parse("SET_TERM 2", &c), "SET_TERM rejects out-of-range mode");
}

static void malformed_lines_are_rejected(void) {
    cmd_t c;
    check(!parse("", &c), "empty line rejected");
    check(!parse("   ", &c), "whitespace-only line rejected");
    check(!parse("BOGUS_CMD 1 2 3", &c), "unknown keyword rejected");
    check(!parse("SET_TIMEBASE", &c), "missing field rejected");
    check(!parse("SET_TIMEBASE 1 2", &c), "trailing garbage rejected");
    check(!parse("SET_TIMEBASE abc", &c), "non-numeric token rejected");
    check(!parse("SET_TIMEBASE -1", &c), "negative token rejected");
    check(!parse("SET_HOFFSET 1", &c), "too few fields rejected");
}

static void crlf_is_tolerated(void) {
    /* cmd.c strips '\r' before calling cmd_parse_line; simulate that here by
     * feeding the parser a line with the '\r' still attached, which must be
     * rejected as trailing garbage -- proving the stripping has to happen
     * upstream, exactly as cmd.c does it. */
    cmd_t c;
    check(!parse("SET_TIMEBASE 5\r", &c), "parser itself does not strip CR");
    check(parse("SET_TIMEBASE 5", &c), "pre-stripped line parses");
}

static void never_reads_past_the_given_length(void) {
    /* Build a buffer with a valid command immediately followed by a canary
     * byte that would corrupt the result if the parser over-read. */
    char buf[32];
    size_t n = 0;
    memcpy(buf, "SET_TIMEBASE 42", 15);
    n = 15;
    buf[n] = 'X'; /* not part of the line; len below stops before it */

    cmd_t c;
    check(cmd_parse_line(buf, n, &c) && c.as.timebase.dec_factor == 42,
          "parses exactly len bytes, ignores data beyond it");
}

int main(void) {
    valid_timebase();
    valid_hoffset();
    valid_trigger();
    valid_vertical();
    valid_coupling_and_term();
    malformed_lines_are_rejected();
    crlf_is_tolerated();
    never_reads_past_the_given_length();

    if (failures == 0) {
        printf("PASS test_cmd_parse\n");
        return 0;
    }
    printf("FAIL test_cmd_parse (%d checks failed)\n", failures);
    return 1;
}

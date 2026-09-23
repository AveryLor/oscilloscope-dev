#include "cmd_parse.h"

// Bounded token scanning over [p, end) — never assumes NUL-termination, never
// reads at or past end.

static const char *skip_spaces(const char *p, const char *end) {
    while (p < end && *p == ' ') p++;
    return p;
}

// Finds the next run of non-space bytes starting at p (which must already be
// past any leading spaces). Returns the token via *tok/*tok_len and the
// position just after it; returns NULL (leaving *tok/*tok_len untouched) if
// there is no token before end.
static const char *next_token(const char *p, const char *end,
                              const char **tok, size_t *tok_len) {
    if (p >= end) {
        return NULL;
    }
    const char *start = p;
    while (p < end && *p != ' ') p++;
    *tok     = start;
    *tok_len = (size_t)(p - start);
    return p;
}

static bool token_is(const char *tok, size_t tok_len, const char *word) {
    size_t i = 0;
    for (; i < tok_len; i++) {
        if (word[i] == '\0' || word[i] != tok[i]) {
            return false;
        }
    }
    return word[i] == '\0';
}

// Decimal-only, no sign, no leading '+', rejects empty tokens and values that
// exceed max_val. Rejects anything but ASCII digits.
static bool parse_uint(const char *tok, size_t tok_len, uint32_t max_val, uint32_t *out) {
    if (tok_len == 0 || tok_len > 10) {
        return false;
    }
    uint32_t v = 0;
    for (size_t i = 0; i < tok_len; i++) {
        char c = tok[i];
        if (c < '0' || c > '9') {
            return false;
        }
        v = v * 10u + (uint32_t)(c - '0');
        if (v > max_val) {
            return false;
        }
    }
    *out = v;
    return true;
}

// Reads exactly n_fields unsigned decimal fields (each bounded by max[i])
// starting at p, requiring nothing but spaces between them and nothing but
// end-of-line after the last one. On success returns true with vals filled;
// on any failure returns false and vals is left partially written.
static bool parse_fields(const char *p, const char *end, const uint32_t *max,
                         size_t n_fields, uint32_t *vals) {
    for (size_t i = 0; i < n_fields; i++) {
        p = skip_spaces(p, end);
        const char *tok;
        size_t tok_len;
        p = next_token(p, end, &tok, &tok_len);
        if (p == NULL) {
            return false; // ran out of fields
        }
        if (!parse_uint(tok, tok_len, max[i], &vals[i])) {
            return false;
        }
    }
    p = skip_spaces(p, end);
    return p == end; // no trailing garbage
}

bool cmd_parse_line(const char *line, size_t len, cmd_t *out) {
    const char *p   = line;
    const char *end = line + len;

    p = skip_spaces(p, end);
    const char *kw;
    size_t kw_len;
    p = next_token(p, end, &kw, &kw_len);
    if (p == NULL) {
        return false; // blank line
    }

    uint32_t v[4];

    if (token_is(kw, kw_len, "SET_TIMEBASE")) {
        static const uint32_t max[] = {0xFFFFu};
        if (!parse_fields(p, end, max, 1, v)) return false;
        out->kind                    = CMD_SET_TIMEBASE;
        out->as.timebase.dec_factor  = (uint16_t)v[0];
        return true;
    }
    if (token_is(kw, kw_len, "SET_HOFFSET")) {
        static const uint32_t max[] = {0xFFFFu, 0xFFFFu};
        if (!parse_fields(p, end, max, 2, v)) return false;
        out->kind                   = CMD_SET_HOFFSET;
        out->as.hoffset.pre_count   = (uint16_t)v[0];
        out->as.hoffset.post_count  = (uint16_t)v[1];
        return true;
    }
    if (token_is(kw, kw_len, "SET_TRIGGER")) {
        static const uint32_t max[] = {1023u, 2u, 2u, 255u};
        if (!parse_fields(p, end, max, 4, v)) return false;
        out->kind             = CMD_SET_TRIGGER;
        out->as.trigger.level = (uint16_t)v[0];
        out->as.trigger.src   = (uint8_t)v[1];
        out->as.trigger.edge  = (uint8_t)v[2];
        out->as.trigger.hyst  = (uint8_t)v[3];
        return true;
    }
    if (token_is(kw, kw_len, "SET_VERTICAL")) {
        static const uint32_t max[] = {2u, 1u, 10u, 4095u};
        if (!parse_fields(p, end, max, 4, v)) return false;
        out->kind                     = CMD_SET_VERTICAL;
        out->as.vertical.atten        = (uint8_t)v[0];
        out->as.vertical.preamp       = (uint8_t)v[1];
        out->as.vertical.lmh_atten    = (uint8_t)v[2];
        out->as.vertical.offset_code  = (uint16_t)v[3];
        return true;
    }
    if (token_is(kw, kw_len, "SET_COUPLING")) {
        static const uint32_t max[] = {1u};
        if (!parse_fields(p, end, max, 1, v)) return false;
        out->kind                = CMD_SET_COUPLING;
        out->as.coupling.dc_coupled = (v[0] != 0);
        return true;
    }
    if (token_is(kw, kw_len, "SET_TERM")) {
        static const uint32_t max[] = {1u};
        if (!parse_fields(p, end, max, 1, v)) return false;
        out->kind           = CMD_SET_TERM;
        out->as.term.term_50r = (v[0] != 0);
        return true;
    }

    return false; // unknown keyword
}

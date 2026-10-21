/* SPDX-License-Identifier: MIT */
#pragma once

#include <stdbool.h>
#include <stdint.h>

enum scroll_axis { SCROLL_UNDECIDED, SCROLL_X, SCROLL_Y };

struct scroll_snap_state {
    int32_t pending_x, pending_y;
    int64_t last_motion;
    enum scroll_axis axis;
    bool has_motion;
};

static inline void scroll_snap_reset(struct scroll_snap_state *s) {
    *s = (struct scroll_snap_state){0};
}

static inline uint32_t scroll_magnitude(int32_t value) {
    return value < 0 ? 0U - (uint32_t)value : (uint32_t)value;
}

/* Called for X/Y events only. Decide at sync, after BOTH axes of the report.
 * Output is one axis per report; the suppressed axis is never replayed later. */
static inline int32_t scroll_snap_feed(struct scroll_snap_state *s, bool x_axis,
                                      int32_t value, bool sync, int64_t now,
                                      uint32_t distance, uint32_t idle_ms) {
    if (value != 0) {
        if (s->has_motion && now - s->last_motion >= idle_ms) {
            scroll_snap_reset(s);
        }
        s->last_motion = now;
        s->has_motion = true;
    }
    if (x_axis) {
        s->pending_x += value;
    } else {
        s->pending_y += value;
    }
    if (!sync) {
        return 0;
    }
    uint32_t x = scroll_magnitude(s->pending_x);
    uint32_t y = scroll_magnitude(s->pending_y);
    if (s->axis == SCROLL_UNDECIDED && (x >= distance || y >= distance)) {
        s->axis = x > y ? SCROLL_X : SCROLL_Y;
    }
    if (s->axis == SCROLL_UNDECIDED) {
        return 0;
    }
    int32_t output = s->axis == SCROLL_X ? s->pending_x : s->pending_y;
    s->pending_x = s->pending_y = 0;
    return output;
}

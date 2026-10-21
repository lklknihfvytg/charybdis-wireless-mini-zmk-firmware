/* SPDX-License-Identifier: MIT */
#pragma once

#include <stdbool.h>
#include <stdint.h>

/* Independent of the layer bindings: physical keys, not emitted keycodes,
 * block arming, including undecided home-row mods, combos and held keys. */
struct auto_mouse_guard {
    uint64_t held;
    int64_t last_typing, last_use, window_start;
    int32_t net_x, net_y;
    bool active, window_open;
};

static inline void auto_mouse_clear_motion(struct auto_mouse_guard *s) {
    s->net_x = s->net_y = 0;
    s->window_open = false;
}

static inline void auto_mouse_cancel(struct auto_mouse_guard *s) {
    s->active = false;
    auto_mouse_clear_motion(s);
}

static inline void auto_mouse_key(struct auto_mouse_guard *s, uint32_t position,
                                  bool pressed, int64_t now, uint64_t click_positions) {
    if (position >= 64) {
        return; /* Virtual behavior positions are not physical keys. */
    }
    uint64_t bit = UINT64_C(1) << position;
    if (pressed) {
        s->held |= bit;
    } else {
        s->held &= ~bit;
    }
    if (s->active && (click_positions & bit)) {
        s->last_use = now;
        return;
    }
    s->last_typing = now; /* Count releases too: a long-held key blocks arming. */
    auto_mouse_cancel(s);
}

static inline uint32_t auto_mouse_magnitude(int32_t value) {
    return value < 0 ? 0U - (uint32_t)value : (uint32_t)value;
}

static inline void auto_mouse_motion(struct auto_mouse_guard *s, bool x_axis,
                                     int32_t value, int64_t now, bool base_allowed,
                                     uint32_t prior_idle, uint32_t distance,
                                     uint32_t window_ms) {
    if (!base_allowed || (!s->active && (s->held || now - s->last_typing < prior_idle))) {
        auto_mouse_cancel(s);
        return;
    }
    if (value == 0) {
        return;
    }
    if (s->active) {
        s->last_use = now;
        return;
    }
    if (!s->window_open || now - s->window_start >= window_ms) {
        auto_mouse_clear_motion(s);
        s->window_open = true;
        s->window_start = now;
    }
    if (x_axis) {
        s->net_x += value;
    } else {
        s->net_y += value;
    }
    if (auto_mouse_magnitude(s->net_x) >= distance ||
        auto_mouse_magnitude(s->net_y) >= distance) {
        s->active = true;
        s->last_use = now;
        auto_mouse_clear_motion(s);
    }
}

static inline bool auto_mouse_expire(struct auto_mouse_guard *s, int64_t now,
                                     uint32_t timeout_ms) {
    if (s->active && !s->held && now - s->last_use >= timeout_ms) {
        auto_mouse_cancel(s);
        return true;
    }
    return false;
}

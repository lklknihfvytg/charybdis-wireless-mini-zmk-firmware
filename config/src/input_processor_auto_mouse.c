/* SPDX-License-Identifier: MIT */
#define DT_DRV_COMPAT charybdis_input_processor_auto_mouse

#include <zephyr/device.h>
#include <zephyr/kernel.h>
#include <zephyr/dt-bindings/input/input-event-codes.h>
#include <drivers/input_processor.h>
#include <zmk/keymap.h>
#include <zmk/events/layer_state_changed.h>
#include <zmk/events/position_state_changed.h>
#include "auto_mouse_guard.h"

BUILD_ASSERT(DT_NUM_INST_STATUS_OKAY(DT_DRV_COMPAT) == 1);
#define AUTO_LAYER DT_INST_PROP(0, layer)
#define CLICK_BIT(node, prop, idx) | (UINT64_C(1) << DT_PROP_BY_IDX(node, prop, idx))
#define CLICK_MASK (UINT64_C(0) DT_INST_FOREACH_PROP_ELEM(0, click_positions, CLICK_BIT))
#define IDLE_MS DT_INST_PROP(0, require_prior_idle_ms)
#define TIMEOUT_MS DT_INST_PROP(0, timeout_ms)
BUILD_ASSERT(AUTO_LAYER > 0 && AUTO_LAYER < ZMK_KEYMAP_LAYERS_LEN);
BUILD_ASSERT(IDLE_MS > 0 && TIMEOUT_MS > 0);
BUILD_ASSERT(DT_INST_PROP(0, activation_distance) > 0);
BUILD_ASSERT(DT_INST_PROP(0, activation_window_ms) > 0);

static struct auto_mouse_guard guard;
static bool owns_layer;
K_MUTEX_DEFINE(auto_mouse_lock);
static void auto_mouse_work_handler(struct k_work *work);
K_WORK_DELAYABLE_DEFINE(auto_mouse_work, auto_mouse_work_handler);

static uint8_t layer_id(void) { return zmk_keymap_layer_index_to_id(AUTO_LAYER); }

static bool base_allowed(void) {
    /* Test ALL layers, not just the highest; AUTO_MOUSE must not hide NAV/NUM. */
    return zmk_keymap_layer_default() == zmk_keymap_layer_index_to_id(0) &&
           !(zmk_keymap_layer_state() & ~(BIT(layer_id()) | BIT(0)));
}

/* Caller holds the recursive mutex. Layer changes can synchronously raise events. */
static void disable_layer(void) {
    auto_mouse_cancel(&guard);
    k_work_cancel_delayable(&auto_mouse_work);
    if (owns_layer) {
        owns_layer = false;
        zmk_keymap_layer_deactivate(layer_id(), false);
    }
}

static void auto_mouse_work_handler(struct k_work *work) {
    ARG_UNUSED(work);
    k_mutex_lock(&auto_mouse_lock, K_FOREVER);
    int64_t now = k_uptime_get();
    if (!base_allowed()) {
        disable_layer();
    } else {
        auto_mouse_expire(&guard, now, TIMEOUT_MS);
        if (!guard.active) {
            disable_layer();
        } else {
            if (!owns_layer) {
                owns_layer = true;
                if (zmk_keymap_layer_activate(layer_id(), false) < 0) {
                    disable_layer();
                }
            }
            if (guard.active && !guard.held) {
                int64_t remaining = TIMEOUT_MS - (now - guard.last_use);
                k_work_reschedule(&auto_mouse_work, K_MSEC(MAX(remaining, 1)));
            }
        }
    }
    k_mutex_unlock(&auto_mouse_lock);
}

static int auto_mouse_position(const zmk_event_t *eh) {
    const struct zmk_position_state_changed *ev = as_zmk_position_state_changed(eh);
    if (!ev || ev->position >= 64) {
        return ZMK_EV_EVENT_BUBBLE;
    }
    k_mutex_lock(&auto_mouse_lock, K_FOREVER);
    /* A click during a queued activation is still a normal base-layer key.
       Cancel that pending activation rather than changing layers mid-key. */
    uint64_t clicks = owns_layer && zmk_keymap_layer_active(layer_id()) ? CLICK_MASK : 0;
    auto_mouse_key(&guard, ev->position, ev->state, k_uptime_get(), clicks);
    if (!guard.active) {
        disable_layer();
    } else {
        k_work_reschedule(&auto_mouse_work, K_MSEC(TIMEOUT_MS));
    }
    k_mutex_unlock(&auto_mouse_lock);
    return ZMK_EV_EVENT_BUBBLE;
}

static int auto_mouse_layer_changed(const zmk_event_t *eh) {
    ARG_UNUSED(eh);
    k_mutex_lock(&auto_mouse_lock, K_FOREVER);
    if (!base_allowed() || (owns_layer && !zmk_keymap_layer_active(layer_id()))) {
        disable_layer();
    }
    k_mutex_unlock(&auto_mouse_lock);
    return ZMK_EV_EVENT_BUBBLE;
}

static int auto_mouse_listener(const zmk_event_t *eh) {
    return as_zmk_position_state_changed(eh) ? auto_mouse_position(eh)
                                           : auto_mouse_layer_changed(eh);
}
ZMK_LISTENER(charybdis_auto_mouse, auto_mouse_listener);
ZMK_SUBSCRIPTION(charybdis_auto_mouse, zmk_position_state_changed);
ZMK_SUBSCRIPTION(charybdis_auto_mouse, zmk_layer_state_changed);

static int auto_mouse_input(const struct device *dev, struct input_event *event,
                            uint32_t param1, uint32_t param2,
                            struct zmk_input_processor_state *state) {
    ARG_UNUSED(dev);
    ARG_UNUSED(param1);
    ARG_UNUSED(param2);
    ARG_UNUSED(state);
    /* Sensor wake/zero reports must not postpone the inactivity timer. */
    if (event->value == 0 || event->type != INPUT_EV_REL ||
        (event->code != INPUT_REL_X && event->code != INPUT_REL_Y)) {
        return ZMK_INPUT_PROC_CONTINUE;
    }
    k_mutex_lock(&auto_mouse_lock, K_FOREVER);
    auto_mouse_motion(&guard, event->code == INPUT_REL_X, event->value, k_uptime_get(),
                       base_allowed(), IDLE_MS, DT_INST_PROP(0, activation_distance),
                       DT_INST_PROP(0, activation_window_ms));
    if (guard.active) {
        k_work_reschedule(&auto_mouse_work, owns_layer ? K_MSEC(TIMEOUT_MS) : K_NO_WAIT);
    } else if (owns_layer) {
        k_work_reschedule(&auto_mouse_work, K_NO_WAIT);
    }
    k_mutex_unlock(&auto_mouse_lock);
    return ZMK_INPUT_PROC_CONTINUE; /* The original XY event remains unchanged. */
}

static const struct zmk_input_processor_driver_api auto_mouse_api = {
    .handle_event = auto_mouse_input,
};
DEVICE_DT_INST_DEFINE(0, NULL, NULL, NULL, NULL, POST_KERNEL,
                      CONFIG_KERNEL_INIT_PRIORITY_DEFAULT, &auto_mouse_api);

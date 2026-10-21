/* SPDX-License-Identifier: MIT */
#define DT_DRV_COMPAT charybdis_input_processor_scroll_snap

#include <zephyr/device.h>
#include <zephyr/kernel.h>
#include <zephyr/dt-bindings/input/input-event-codes.h>
#include <drivers/input_processor.h>
#include <zmk/events/layer_state_changed.h>
#include "scroll_snap.h"

struct snap_config { uint32_t distance, idle_ms; };
struct snap_data {
    struct k_spinlock lock;
    struct scroll_snap_state state;
};

static int snap_event(const struct device *dev, struct input_event *event,
                      uint32_t param1, uint32_t param2,
                      struct zmk_input_processor_state *state) {
    ARG_UNUSED(param1);
    ARG_UNUSED(param2);
    ARG_UNUSED(state);
    if (event->type != INPUT_EV_REL ||
        (event->code != INPUT_REL_X && event->code != INPUT_REL_Y)) {
        return ZMK_INPUT_PROC_CONTINUE;
    }
    const struct snap_config *cfg = dev->config;
    struct snap_data *data = dev->data;
    k_spinlock_key_t key = k_spin_lock(&data->lock);
    event->value = scroll_snap_feed(&data->state, event->code == INPUT_REL_X,
                                    event->value, event->sync, k_uptime_get(),
                                    cfg->distance, cfg->idle_ms);
    if (event->sync && data->state.axis != SCROLL_UNDECIDED) {
        event->code = data->state.axis == SCROLL_X ? INPUT_REL_X : INPUT_REL_Y;
    }
    k_spin_unlock(&data->lock, key);
    return ZMK_INPUT_PROC_CONTINUE;
}

static const struct zmk_input_processor_driver_api snap_api = {.handle_event = snap_event};

#define SNAP_INST(n)                                                                                \
    BUILD_ASSERT(DT_INST_PROP(n, activation_distance) > 0);                                        \
    BUILD_ASSERT(DT_INST_PROP(n, idle_reset_ms) > 0);                                               \
    static struct snap_data snap_data_##n;                                                         \
    static const struct snap_config snap_config_##n = {                                            \
        .distance = DT_INST_PROP(n, activation_distance),                                         \
        .idle_ms = DT_INST_PROP(n, idle_reset_ms),                                                 \
    };                                                                                             \
    DEVICE_DT_INST_DEFINE(n, NULL, NULL, &snap_data_##n, &snap_config_##n, POST_KERNEL,             \
                          CONFIG_KERNEL_INIT_PRIORITY_DEFAULT, &snap_api);
DT_INST_FOREACH_STATUS_OKAY(SNAP_INST)

/* Releasing SCROLL and immediately entering it again starts a fresh gesture. */
#define RESET_SNAP(n)                                                                               \
    {                                                                                              \
        struct snap_data *data = DEVICE_DT_INST_GET(n)->data;                                     \
        k_spinlock_key_t key = k_spin_lock(&data->lock);                                            \
        scroll_snap_reset(&data->state);                                                           \
        k_spin_unlock(&data->lock, key);                                                           \
    }
static int snap_layer_changed(const zmk_event_t *eh) {
    ARG_UNUSED(eh);
    DT_INST_FOREACH_STATUS_OKAY(RESET_SNAP)
    return ZMK_EV_EVENT_BUBBLE;
}
ZMK_LISTENER(charybdis_scroll_snap, snap_layer_changed);
ZMK_SUBSCRIPTION(charybdis_scroll_snap, zmk_layer_state_changed);

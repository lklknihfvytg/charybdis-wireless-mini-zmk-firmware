/* Copyright (c) 2026 The ZMK Contributors
 * SPDX-License-Identifier: MIT
 */

#define DT_DRV_COMPAT zmk_behavior_battery_text

#include <zephyr/device.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/util.h>

#include <drivers/behavior.h>
#include <dt-bindings/zmk/hid_usage.h>
#include <dt-bindings/zmk/hid_usage_pages.h>

#include <zmk/behavior.h>
#if !IS_ENABLED(CONFIG_ZMK_SPLIT) || IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)
#include <zmk/events/keycode_state_changed.h>
#define BATTERY_TEXT_CAN_EMIT_KEYS 1
#else
#define BATTERY_TEXT_CAN_EMIT_KEYS 0
#endif

#if BATTERY_TEXT_CAN_EMIT_KEYS && \
    IS_ENABLED(CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING) && \
    defined(CONFIG_ZMK_SPLIT_BLE_CENTRAL_PERIPHERALS) && \
    CONFIG_ZMK_SPLIT_BLE_CENTRAL_PERIPHERALS >= 2
#include <zmk/split/central.h>
#define BATTERY_TEXT_HAS_TWO_PERIPHERALS 1
#else
#define BATTERY_TEXT_HAS_TWO_PERIPHERALS 0
#endif

LOG_MODULE_DECLARE(zmk, CONFIG_ZMK_LOG_LEVEL);

#define BATTERY_TEXT_MAX_KEYS 8
#define BATTERY_TEXT_KEY_INTERVAL K_MSEC(8)

#if BATTERY_TEXT_HAS_TWO_PERIPHERALS

struct battery_text_state {
    uint32_t keys[BATTERY_TEXT_MAX_KEYS];
    size_t key_count;
    size_t key_index;
    bool key_pressed;
    bool busy;
};

static struct battery_text_state state;
static void battery_text_work_handler(struct k_work *work);
K_WORK_DELAYABLE_DEFINE(battery_text_work, battery_text_work_handler);

static const uint8_t digit_usages[] = {
    HID_USAGE_KEY_KEYBOARD_0_AND_RIGHT_PARENTHESIS,
    HID_USAGE_KEY_KEYBOARD_1_AND_EXCLAMATION,
    HID_USAGE_KEY_KEYBOARD_2_AND_AT,
    HID_USAGE_KEY_KEYBOARD_3_AND_HASH,
    HID_USAGE_KEY_KEYBOARD_4_AND_DOLLAR,
    HID_USAGE_KEY_KEYBOARD_5_AND_PERCENT,
    HID_USAGE_KEY_KEYBOARD_6_AND_CARET,
    HID_USAGE_KEY_KEYBOARD_7_AND_AMPERSAND,
    HID_USAGE_KEY_KEYBOARD_8_AND_ASTERISK,
    HID_USAGE_KEY_KEYBOARD_9_AND_LEFT_PARENTHESIS,
};

static void append_digit(uint8_t digit) {
    state.keys[state.key_count++] = ZMK_HID_USAGE(HID_USAGE_KEY, digit_usages[digit]);
}

static void append_percentage(uint8_t level) {
    if (level > 100) {
        level = 100;
    }

    if (level >= 100) {
        append_digit(1);
        append_digit(0);
        append_digit(0);
    } else if (level >= 10) {
        append_digit(level / 10);
        append_digit(level % 10);
    } else {
        append_digit(level);
    }
}

static void battery_text_work_handler(struct k_work *work) {
    ARG_UNUSED(work);

    if (state.key_index >= state.key_count) {
        state.busy = false;
        return;
    }

    uint32_t encoded = state.keys[state.key_index];
    int err = raise_zmk_keycode_state_changed_from_encoded(encoded, !state.key_pressed,
                                                            k_uptime_get());
    if (err < 0) {
        LOG_ERR("Failed to type battery level key (err %d)", err);
        state.busy = false;
        return;
    }

    if (state.key_pressed) {
        state.key_pressed = false;
        state.key_index++;
    } else {
        state.key_pressed = true;
    }

    k_work_schedule(&battery_text_work, BATTERY_TEXT_KEY_INTERVAL);
}

#endif // BATTERY_TEXT_HAS_TWO_PERIPHERALS

static int on_battery_text_binding_pressed(struct zmk_behavior_binding *binding,
                                           struct zmk_behavior_binding_event event) {
    ARG_UNUSED(binding);
    ARG_UNUSED(event);
#if BATTERY_TEXT_HAS_TWO_PERIPHERALS
    if (state.busy) {
        return ZMK_BEHAVIOR_OPAQUE;
    }

    uint8_t left = 0;
    uint8_t right = 0;
    if (event.source > 1) {
        LOG_WRN("Could not identify the left half battery slot (source %u)", event.source);
        return ZMK_BEHAVIOR_OPAQUE;
    }
    int err = zmk_split_central_get_peripheral_battery_level(event.source, &left);
    if (err == 0) {
        err = zmk_split_central_get_peripheral_battery_level(1 - event.source, &right);
    }
    if (err < 0) {
        LOG_WRN("Could not read split battery levels (err %d)", err);
        return ZMK_BEHAVIOR_OPAQUE;
    }

    state.key_count = 0;
    state.key_index = 0;
    state.key_pressed = false;
    append_percentage(left);
    state.keys[state.key_count++] = ZMK_HID_USAGE(HID_USAGE_KEY, HID_USAGE_KEY_KEYBOARD_SPACEBAR);
    append_percentage(right);
    state.busy = true;
    k_work_schedule(&battery_text_work, K_NO_WAIT);
#else
    LOG_WRN("Battery text output needs a central with two battery-reporting peripherals");
#endif

    return ZMK_BEHAVIOR_OPAQUE;
}

static int on_battery_text_binding_released(struct zmk_behavior_binding *binding,
                                            struct zmk_behavior_binding_event event) {
    ARG_UNUSED(binding);
    ARG_UNUSED(event);
    return ZMK_BEHAVIOR_OPAQUE;
}

static const struct behavior_driver_api battery_text_driver_api = {
    .binding_pressed = on_battery_text_binding_pressed,
    .binding_released = on_battery_text_binding_released,
    .locality = BEHAVIOR_LOCALITY_CENTRAL,
};

BEHAVIOR_DT_INST_DEFINE(0, NULL, NULL, NULL, NULL, POST_KERNEL,
                        CONFIG_KERNEL_INIT_PRIORITY_DEFAULT, &battery_text_driver_api);

"""Run the real battery behavior with a fake event sink, without keyboard input."""

import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SHIM = r'''
#pragma once
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <dt-bindings/zmk/hid_usage.h>
#include <dt-bindings/zmk/hid_usage_pages.h>
#define CONFIG_ZMK_SPLIT 1
#ifndef CONFIG_ZMK_SPLIT_ROLE_CENTRAL
#define CONFIG_ZMK_SPLIT_ROLE_CENTRAL 1
#endif
#define CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING 1
#ifndef CONFIG_ZMK_SPLIT_BLE_CENTRAL_PERIPHERALS
#define CONFIG_ZMK_SPLIT_BLE_CENTRAL_PERIPHERALS 2
#endif
#define IS_ENABLED(x) (x)
#define ARG_UNUSED(x) (void)(x)
#define LOG_MODULE_DECLARE(...)
#define LOG_ERR(...) ((void)0)
#define LOG_WRN(...) ((void)0)
#define K_MSEC(x) (x)
#define K_NO_WAIT 0
#define ZMK_BEHAVIOR_OPAQUE 0
#define BEHAVIOR_LOCALITY_CENTRAL 0
#define BEHAVIOR_DT_INST_DEFINE(...) static const void *driver_reference __attribute__((used)) = &battery_text_driver_api
struct k_work {int unused;};
struct k_work_delayable {int unused;};
#define K_WORK_DELAYABLE_DEFINE(name, handler) struct k_work_delayable name
struct zmk_behavior_binding {int unused;};
struct zmk_behavior_binding_event {uint8_t source;};
struct behavior_driver_api {
    int (*binding_pressed)(struct zmk_behavior_binding *, struct zmk_behavior_binding_event);
    int (*binding_released)(struct zmk_behavior_binding *, struct zmk_behavior_binding_event);
    int locality;
};
static bool scheduled;
static uint8_t levels[2];
static int fail_source = -1;
static int64_t clock_ms;
static uint32_t events[32];
static bool event_states[32];
static size_t event_count;
static int k_work_schedule(struct k_work_delayable *work, int delay) {
    (void)work; (void)delay; scheduled = true; return 0;
}
static int64_t k_uptime_get(void) { return clock_ms; }
static int zmk_split_central_get_peripheral_battery_level(uint8_t source, uint8_t *level) {
    if (source > 1 || source == fail_source) return -1;
    *level = levels[source]; return 0;
}
static int raise_zmk_keycode_state_changed_from_encoded(uint32_t key, bool down, int64_t time) {
    (void)time; assert(event_count < 32);
    events[event_count] = key; event_states[event_count++] = down; return 0;
}
'''

TEST = r'''
static void drain(void) {
    unsigned ticks = 0;
    while (scheduled) {
        assert(++ticks < 32); scheduled = false; clock_ms += 8;
        battery_text_work_handler(NULL);
    }
    assert(!state.busy && !state.key_pressed);
}
static void check(uint8_t left, uint8_t right, uint8_t source) {
    memset(&state, 0, sizeof(state)); scheduled = false; event_count = 0;
    levels[source] = left; levels[1-source] = right;
    struct zmk_behavior_binding_event trigger = {.source = source};
    on_battery_text_binding_pressed(NULL, trigger);
    /* A duplicate trigger while printing must not restart or corrupt output. */
    on_battery_text_binding_pressed(NULL, trigger);
    on_battery_text_binding_released(NULL, trigger);
    drain();
    assert(event_count % 2 == 0);
    char actual[9] = {0};
    for (size_t i = 0; i < event_count; i += 2) {
        assert(event_states[i] && !event_states[i+1]);
        assert(events[i] == events[i+1]);
        assert(ZMK_HID_USAGE_PAGE(events[i]) == HID_USAGE_KEY);
        unsigned usage = ZMK_HID_USAGE_ID(events[i]);
        if (usage == HID_USAGE_KEY_KEYBOARD_SPACEBAR) actual[i/2] = ' ';
        else if (usage == HID_USAGE_KEY_KEYBOARD_0_AND_RIGHT_PARENTHESIS) actual[i/2] = '0';
        else {
            assert(usage >= HID_USAGE_KEY_KEYBOARD_1_AND_EXCLAMATION && usage <= HID_USAGE_KEY_KEYBOARD_9_AND_LEFT_PARENTHESIS);
            actual[i/2] = '1' + usage - HID_USAGE_KEY_KEYBOARD_1_AND_EXCLAMATION;
        }
    }
    char expected[9]; snprintf(expected, sizeof(expected), "%u %u", left > 100 ? 100 : left, right > 100 ? 100 : right);
    assert(strcmp(actual, expected) == 0);
}
int main(void) {
    for (unsigned source = 0; source < 2; source++)
        for (unsigned left = 0; left <= 100; left++)
            for (unsigned right = 0; right <= 100; right++) check(left, right, source);
    check(255, 200, 0);
    for (unsigned source = 2; source <= 255; source++) {
        event_count = 0; scheduled = false;
        on_battery_text_binding_pressed(NULL, (struct zmk_behavior_binding_event){.source = source});
        assert(!scheduled && event_count == 0);
    }
    for (int fail = 0; fail < 2; fail++) {
        fail_source = fail; event_count = 0; scheduled = false;
        on_battery_text_binding_pressed(NULL, (struct zmk_behavior_binding_event){.source = 0});
        assert(!scheduled && event_count == 0);
    }
    puts("PASS: 20,402 level/slot combinations, clamping, balanced key releases, duplicate trigger and invalid sources/read errors");
}
'''

COMBO_TEST = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#define CONFIG_ZMK_SPLIT 1
#define IS_ENABLED(x) (x)
#define ZMK_POSITION_STATE_CHANGE_SOURCE_LOCAL UINT8_MAX
#define ZMK_VIRTUAL_KEY_POSITION_COMBO(index) (1000 + (index))
struct zmk_behavior_binding {int unused;};
struct zmk_behavior_binding_event {uint32_t position; int64_t timestamp; uint8_t source;};
struct combo_cfg {bool pass_source; struct zmk_behavior_binding behavior;};
static int64_t last_combo_timestamp;
static struct zmk_behavior_binding_event observed;
static bool observed_pressed;
static int zmk_behavior_invoke_binding(const struct zmk_behavior_binding *binding,
                                     struct zmk_behavior_binding_event event, bool pressed) {
    (void)binding; observed = event; observed_pressed = pressed; return 0;
}
%FUNCTIONS%
int main(void) {
    for (unsigned pass = 0; pass < 2; pass++) {
        struct combo_cfg combo = {.pass_source = pass};
        for (unsigned source = 0; source <= 255; source++) {
            press_combo_behavior(3, &combo, 1234, source);
            assert(observed.source == (pass ? source : UINT8_MAX));
            assert(observed.position == 1003 && observed.timestamp == 1234 && observed_pressed);
            assert(last_combo_timestamp == 1234);
            release_combo_behavior(3, &combo, 1256, source);
            assert(observed.source == (pass ? source : UINT8_MAX));
            assert(observed.position == 1003 && observed.timestamp == 1256 && !observed_pressed);
        }
    }
    puts("PASS: combo press/release source forwarding is opt-in; default semantics preserved for all source IDs");
}
'''


def extract_function(source, name):
    start = source.index("static inline int " + name + "(")
    body = source.index("{", start)
    depth = 1
    for end in range(body + 1, len(source)):
        depth += (source[end] == "{") - (source[end] == "}")
        if depth == 0:
            return source[start:end + 1]
    raise ValueError(f"Unterminated function: {name}")


def main():
    with tempfile.TemporaryDirectory(prefix="battery-text-") as directory:
        tmp = Path(directory)
        (tmp / "shim.h").write_text(SHIM)
        for header in (
            "zephyr/device.h", "zephyr/kernel.h", "zephyr/logging/log.h", "zephyr/sys/util.h",
            "drivers/behavior.h", "zmk/behavior.h", "zmk/events/keycode_state_changed.h", "zmk/split/central.h",
        ):
            path = tmp / header
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('#include "shim.h"\n')
        source = tmp / "test.c"
        behavior = (ROOT / "config/src/behavior_battery_text.c").as_posix()
        source.write_text(f'#include "{behavior}"\n' + TEST)
        executable = tmp / "battery-test"
        subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined",
                        "-I", str(tmp), "-I", str(ROOT / "zmk/app/include"), str(source), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
        source.write_text(f'#include "{behavior}"\n' + r'''
int main(void) {
    struct zmk_behavior_binding_event event = {.source = 0};
    on_battery_text_binding_pressed(NULL, event);
    on_battery_text_binding_released(NULL, event);
    assert(!scheduled && event_count == 0);
    puts("PASS: unsupported role emits no keys");
}
''')
        for role, peers in ((0, 2), (1, 1)):
            subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror",
                            "-Wno-unused-function", "-Wno-unused-variable",
                            f"-DCONFIG_ZMK_SPLIT_ROLE_CENTRAL={role}",
                            f"-DCONFIG_ZMK_SPLIT_BLE_CENTRAL_PERIPHERALS={peers}",
                            "-I", str(tmp), "-I", str(ROOT / "zmk/app/include"),
                            str(source), "-o", str(executable)], check=True)
            subprocess.run([str(executable)], check=True)
        combo = (ROOT / "zmk/app/src/combo.c").read_text()
        functions = "\n".join(extract_function(combo, name) for name in
                              ("press_combo_behavior", "release_combo_behavior"))
        source.write_text(COMBO_TEST.replace("%FUNCTIONS%", functions))
        subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined",
                        str(source), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()

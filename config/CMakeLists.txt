zephyr_library()
zephyr_include_directories(${APPLICATION_SOURCE_DIR}/include)
zephyr_library_sources_ifdef(CONFIG_ZMK_BEHAVIOR_BATTERY_TEXT src/behavior_battery_text.c)
zephyr_library_sources_ifdef(CONFIG_CHARYBDIS_SCROLL_SNAP src/input_processor_scroll_snap.c)

# Added to app BEFORE ZMK adds hold-tap, combo and keymap subscriptions.
# A normal key must cancel the automatic layer before resolving its binding.
target_sources_ifdef(CONFIG_CHARYBDIS_AUTO_MOUSE app PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src/input_processor_auto_mouse.c)

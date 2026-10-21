"""Reject firmware configurations missing ZMK board support before compilation."""

import argparse
import re
from pathlib import Path


def node_body(dts, name):
    match = re.search(r"\b" + re.escape(name) + r"(?:\s*:\s*[\w@,.-]+)?\s*\{", dts)
    if not match:
        return ""
    start = match.end()
    depth = 1
    for end in range(start, len(dts)):
        depth += (dts[end] == "{") - (dts[end] == "}")
        if depth == 0:
            return dts[start:end]
    return ""


def validate(build_dir, mode, side):
    config = dict(re.findall(r"^(CONFIG_\w+)=(.*)$", (build_dir / "zephyr/.config").read_text(), re.M))
    dts = (build_dir / "zephyr/zephyr.dts").read_text()
    errors = []

    def require(key, value="y"):
        if config.get(key, "n") != value:
            errors.append(f"{key}: expected {value}, got {config.get(key, 'n')}")

    for key in ("BOARD_NICE_NANO_NRF52840_ZMK", "FLASH", "FLASH_MAP", "NVS", "SETTINGS_NVS"):
        require("CONFIG_" + key)
    require("CONFIG_SETTINGS_NONE", "n")

    if mode == "reset":
        require("CONFIG_ZMK_SETTINGS_RESET_ON_START")
    else:
        for key in ("ZMK_BLE", "ZMK_SPLIT", "ZMK_SPLIT_BLE"):
            require("CONFIG_" + key)
        central = side == "dongle" or (mode == "bt" and side == "right")
        require("CONFIG_ZMK_SPLIT_ROLE_CENTRAL", "y" if central else "n")
        require("CONFIG_ZMK_USB", "y" if central else "n")
        if central:
            require("CONFIG_USB_DEVICE_HID")
        if side == "dongle":
            require("CONFIG_ZMK_SPLIT_BLE_CENTRAL_PERIPHERALS", "2")
            require("CONFIG_ZMK_INPUT_SPLIT")
            require("CONFIG_ZMK_INPUT_LISTENER")
            # The dongle must contain a BLE proxy, not physical sensor hardware.
            if node_body(dts, "trackball"):
                errors.append("Dongle DTS unexpectedly contains a physical trackball node")
            proxy = node_body(dts, "trackball_split")
            listener = node_body(dts, "trackball_listener")
            if 'compatible = "zmk,input-split"' not in proxy:
                errors.append("Dongle has no trackball split proxy")
            if "&trackball_split" not in listener or 'status = "disabled"' in listener:
                errors.append("Dongle trackball listener is missing or disabled")
        if side == "right":
            for key in ("ZMK_EXT_POWER", "PMW3610_ALT", "SPI", "ZMK_POINTING"):
                require("CONFIG_" + key)
            power = node_body(dts, "EXT_POWER")
            if not re.search(r"control-gpios\s*=\s*<\s*&gpio0\s+(?:0xd|13)\s+0x0\s*>", power):
                errors.append("Right half has no active-high P0.13 EXT_POWER supply control")
            if 'status = "disabled"' in power:
                errors.append("Right half EXT_POWER supply node is disabled")
            sensor = node_body(dts, "trackball")
            if 'compatible = "pixart,pmw3610-alt"' not in sensor or 'status = "disabled"' in sensor:
                errors.append("Right half PMW3610 sensor is missing or disabled")
            if mode == "dongle":
                require("CONFIG_ZMK_INPUT_SPLIT")
                if "&trackball" not in node_body(dts, "trackball_split"):
                    errors.append("Right half split proxy is not bound to the sensor")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build_dir", type=Path)
    parser.add_argument("--format", choices=("bt", "dongle", "reset"), required=True)
    parser.add_argument("--side", choices=("left", "right", "dongle", "reset"), required=True)
    args = parser.parse_args()
    try:
        errors = validate(args.build_dir, args.format, args.side)
    except OSError as exc:
        parser.exit(1, f"Cannot validate build: {exc}\n")
    if errors:
        parser.exit(1, "Firmware configuration rejected:\n" + "".join(f"  - {error}\n" for error in errors))
    print(f"Validated {args.format}/{args.side}: ZMK board variant, persistent settings and input path")


if __name__ == "__main__":
    main()

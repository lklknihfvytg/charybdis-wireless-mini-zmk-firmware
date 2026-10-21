"""Check generated firmware configuration against a captured working baseline."""

import argparse
import re
from pathlib import Path

from validate_build import node_body


def config(path):
    return dict(re.findall(r'^(CONFIG_\w+)=(.*)$', path.read_text(), re.M))


def normalized_dts(text):
    text = re.sub(r'/\*.*?\*/|//[^\n]*', '', text, flags=re.S)
    text = re.sub(r'\b(?:swap-xy|invert-x|invert-y)\s*;', '', text)
    return re.sub(r'\s+', '', text)


def compare(baseline, build_dir, orientation=False, module=False, battery=False):
    old_config = config(baseline / '.config')
    new_config = config(build_dir / 'zephyr/.config')
    old_dts = (baseline / 'zephyr.dts').read_text()
    new_dts = (build_dir / 'zephyr/zephyr.dts').read_text()
    allowed = set()
    if orientation:
        for suffix in ('SWAP_XY', 'INVERT_X', 'INVERT_Y'):
            allowed.add('CONFIG_PMW3610_ALT_' + suffix)
    if module:
        allowed.update(key for key in old_config.keys() | new_config.keys() if key.startswith('CONFIG_SHIELD_'))
        allowed.add('CONFIG_ZEPHYR_CHARYBDIS_BOARDS_MODULE')
    if battery:
        allowed.update(('CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING',
                        'CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_QUEUE_SIZE'))
    differences = {key: (old_config.get(key, 'n'), new_config.get(key, 'n'))
                   for key in old_config.keys() | new_config.keys()
                   if old_config.get(key, 'n') != new_config.get(key, 'n')}
    unexpected = {key: value for key, value in differences.items() if key not in allowed}
    if unexpected:
        raise ValueError(f'Unexpected Kconfig differences: {unexpected}')
    for before, after in ((old_dts, old_config), (new_dts, new_config)):
        sensor = node_body(before, 'trackball')
        if sensor:
            bits = 0
            for prop, suffix, mask in (('swap-xy', 'SWAP_XY', 0x80),
                                       ('invert-x', 'INVERT_X', 0x40),
                                       ('invert-y', 'INVERT_Y', 0x20)):
                if re.search(r'\b' + prop + r'\s*;', sensor) or after.get('CONFIG_PMW3610_ALT_' + suffix) == 'y':
                    bits |= mask
            if bits != 0xE0:
                raise ValueError(f'Sensor orientation changed: {bits:#x}')
    if normalized_dts(old_dts) != normalized_dts(new_dts):
        raise ValueError('Generated DTS changed beyond sensor orientation properties')
    return differences


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('build_dir', type=Path)
    parser.add_argument('--orientation-dts', action='store_true')
    parser.add_argument('--module', action='store_true')
    parser.add_argument('--battery', action='store_true')
    args = parser.parse_args()
    try:
        changes = compare(args.baseline, args.build_dir, args.orientation_dts, args.module, args.battery)
    except (OSError, ValueError) as exc:
        parser.exit(1, f'Baseline comparison failed: {exc}\n')
    print(f'Baseline preserved; allowed Kconfig changes: {changes}')

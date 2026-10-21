"""Validate a built UF2 against its Zephyr configuration and binary payload."""

import argparse
import hashlib
import struct
from pathlib import Path

from validate_build import validate


def verify(build_dir, artifact, mode, side):
    errors = validate(build_dir, mode, side)
    if errors:
        raise ValueError('; '.join(errors))
    data = artifact.read_bytes()
    if not data or len(data) % 512:
        raise ValueError('UF2 length must be a nonzero multiple of 512')
    if data != (build_dir / 'zephyr/zmk.uf2').read_bytes():
        raise ValueError('Published UF2 differs from the build output')
    binary = (build_dir / 'zephyr/zmk.bin').read_bytes()
    payload = bytearray()
    for offset in range(0, len(data), 512):
        block = data[offset:offset + 512]
        magic1, magic2, flags, address, size, number, count, family = struct.unpack('<8I', block[:32])
        if (magic1, magic2, struct.unpack('<I', block[-4:])[0]) != (0x0A324655, 0x9E5D5157, 0x0AB16F30):
            raise ValueError('Invalid UF2 magic')
        if not flags & 0x2000 or family != 0xADA52840:
            raise ValueError('UF2 must target nRF52840')
        if number != offset // 512 or count != len(data) // 512:
            raise ValueError('Invalid UF2 block sequence')
        if not 0 < size <= 476 or address != 0x26000 + len(payload) or address + size > 0xEC000:
            raise ValueError('UF2 payload is outside the application partition or has gaps')
        payload.extend(block[32:32 + size])
    if payload[:len(binary)] != binary:
        raise ValueError('UF2 payload differs from zmk.bin')
    return {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build_dir', type=Path)
    parser.add_argument('artifact', type=Path)
    parser.add_argument('--format', required=True, choices=('bt', 'dongle', 'reset'))
    parser.add_argument('--side', required=True, choices=('left', 'right', 'dongle', 'reset'))
    args = parser.parse_args()
    try:
        result = verify(args.build_dir, args.artifact, args.format, args.side)
    except (OSError, ValueError) as exc:
        parser.exit(1, f'Firmware rejected: {exc}\n')
    print(f'Validated {args.format}/{args.side}: {result["bytes"]} bytes, SHA256 {result["sha256"]}')

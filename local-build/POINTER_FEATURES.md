# Trackball scrolling and automatic mouse layer

## Scroll Snap

While holding the existing SCROLL key (M), the first 4 net sensor counts choose
the dominant axis of the complete XY report. Scrolling stays on that axis until
200 ms without movement, or a layer change. Release and hold SCROLL again to
choose a new direction immediately. Ties choose vertical scrolling. Both
positive and negative scrolling work; the other axis is discarded, never queued
for a later burst.

Axis detection runs before the existing 1/16 scale, XY-to-scroll mapping and
vertical inversion. Normal pointer movement, SLOW, CPI, sensor timing, BLE,
sleep settings, pairing and battery printing retain their existing settings.

The idea was evaluated against [kot149/zmk-scroll-snap](https://github.com/kot149/zmk-scroll-snap)
at `2feeb988f5b5a3c2b5e09ba6472e86e6902463a2`. This is a small local
implementation, not a dependency on that module: it handles a complete XY frame
before choosing a direction and has no unfinished diagonal mode. No extra
polling, periodic timer, dependency download or sensor wake period is added.

Configuration: `config/charybdis_pointer.dtsi`, node `scroll_snap`:

- `activation-distance`: raw counts before choosing an axis (4).
- `idle-reset-ms`: pause that starts a new gesture (200 ms).

Native algorithm checks in the existing build container:

```sh
gcc -std=c11 -Wall -Wextra -Werror -Iconfig/src local-build/tests/test_scroll_snap.c -o build/test-scroll-snap
build/test-scroll-snap
```

These checks cover axis selection after a complete frame, sparse X-only reports,
signs, diagonal input, suppressed-axis leakage, accumulated small movements,
idle reset and explicit reset. Compilation and UF2 validation do not replace a
hardware check of the scrolling feel.

Before the changes, the published three-file firmware set and generated configs
were copied to `build/pointer-features-baseline/` for rollback. The tracked
`firmwares/known-good/` archive is untouched.

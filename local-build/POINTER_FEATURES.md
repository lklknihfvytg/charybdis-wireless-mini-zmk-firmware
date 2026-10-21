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
The Scroll Snap-only dongle UF2 is also preserved at
`build/scroll-snap-only/charybdis_dongle.uf2` (SHA256
`9c2b65b5289d989dd43e830cd52561a395f7e81df0acd1034503be31ee2837a5`).

## Guarded automatic mouse layer (QWERTY)

J/K/L become left/right/middle click after deliberate trackball movement.
Every other position is transparent. Space and the thumb keys keep their normal
functions. The original manually held MOUSE/SLOW/SCROLL layers are unchanged.
The existing H+J bracket and J+K language combos retain their original eight
layers but are excluded from AUTO_MOUSE, so automatic clicks are neither delayed
by those combos nor turned into a language-switch shortcut when clicked together.

Protection against movements while typing:

- All physical presses AND releases restart a 1000 ms typing cooldown, including
  combos and undecided home-row modifiers. Holding any key blocks initial activation.
- After the cooldown, activation requires 80 net raw sensor counts along one
  axis within 200 ms. Back-and-forth vibration cancels; slow drift cannot accumulate
  indefinitely. At 800 CPI, 80 counts are about 2.54 mm of sensed surface travel.
- Motion received during typing or the cooldown does not count toward activation.
- A normal physical key turns the automatic layer off BEFORE hold-tap, combos
  and keymap lookup see that same press. Its ordinary binding is preserved.
- The automatic layer cannot activate over NUM/NAV/MEDIA/ADJUST or the manual
  MOUSE/SLOW/SCROLL layers. It is a separate layer, so automatic timeout cannot
  turn off a manually held mouse layer.
- After 800 ms without motion/clicks it switches off. A held mouse button keeps
  it active during a drag; the timer restarts after release. Keymap's original
  press-layer tracking still delivers mouse-up if another key cancels the layer.

Limitation: if the automatic layer is active and the first text key is J/K/L,
that key is a click. Firmware cannot infer whether the user intended a letter
or a mouse button. This familiar mapping was explicitly selected by the user.

Configuration: `config/charybdis_auto_mouse.dtsi`. The cursor keeps moving
immediately even below the activation threshold. The processor never changes
XY values, sensor polling, radio parameters, sleep or battery reporting. There
is no periodic polling task: delayed work runs only for activation/expiry.

`local-build/verify_firmware.py` verifies from the final linker map that the
physical-key guard is registered before hold-tap, combos and keymap. Publishing
fails if that ordering is lost. The guard is linked into the existing `app`
target before ZMK registers those listeners; no ZMK source patch is needed.

Additional native checks:

```sh
gcc -std=c11 -Wall -Wextra -Werror -Iconfig/src local-build/tests/test_auto_mouse_guard.c -o build/test-auto-mouse
build/test-auto-mouse
```

These cover held HRM, cooldown after release, blocked motion, vibration, drift,
normal-key cancellation, click/drag, timeout, manual layers and a click arriving
before queued activation. Actual false-activation rate requires hardware use.

## Build verification (2026-10-21)

Both native algorithm tests passed with AddressSanitizer and UndefinedBehaviorSanitizer.
All three QWERTY dongle targets compiled and passed the existing board/role/power,
UF2 structure and binary-payload checks. The final dongle passed the additional
listener-order check. Generated configurations and device trees were compared
against the pre-change snapshot: the original eight layers, hardware, radio,
sensor and power settings are retained. The two click-related combos keep their
old scope on layers 0 through 7. Battery printing remains enabled; rebuilding
the left peripheral also includes the already-existing inactive battery-text stub.

The final dongle UF2 SHA256 is
`905d22ba6e41c5b0b7ba21d9b0472b4e0c52a5a14e2edaa8b6d8ce2148bc36e5`.
Files are in `firmwares/charybdis_dongle/qwerty/`. Only the dongle needs flashing
for these features; current peripheral firmware remains compatible. Settings
reset is not required. The right UF2 is byte-identical to its pre-change file.
Hardware confirmation of axis-lock feel and typing protection is still pending.

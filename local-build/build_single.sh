#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=/workspaces/zmk
ZMK_APP="$REPO_ROOT/zmk/app"
KEYMAP="${1:-qwerty}"
FORMAT="${2:-bt}"
CONFIGURE_ONLY="${CONFIGURE_ONLY:-0}"
case "$FORMAT" in
  bt) sides=(left right) ;;
  dongle) sides=(dongle left right) ;;
  *) echo "Unsupported format: $FORMAT (use bt or dongle)" >&2; exit 2 ;;
esac
[[ -z "${3:-}" ]] || sides=("$3")
KEYMAP_FILE="$REPO_ROOT/config/keymap/$KEYMAP.keymap"
[[ -f "$KEYMAP_FILE" ]] || { echo "Keymap not found: $KEYMAP_FILE" >&2; exit 2; }

cd "$REPO_ROOT"
if [[ ! -d .west ]]; then
  west init -l config
  west update
fi
PMW_PATCH="$REPO_ROOT/patches/pmw3610-wakeup-source.patch"
PMW_DRIVER="$REPO_ROOT/zmk-pmw3610-driver"
if ! git -C "$PMW_DRIVER" apply --ignore-space-change --reverse --check "$PMW_PATCH" >/dev/null 2>&1; then
  git -C "$PMW_DRIVER" apply --ignore-space-change "$PMW_PATCH"
fi
west zephyr-export

for side in "${sides[@]}"; do
  case "$FORMAT/$side" in
    bt/left) shield=charybdis_left_bt ;;
    bt/right) shield=charybdis_right_bt ;;
    dongle/left) shield=charybdis_left_dongle ;;
    dongle/right) shield=charybdis_right_dongle ;;
    dongle/dongle) shield=charybdis_dongle_central ;;
    *) echo "Unsupported target: $FORMAT/$side" >&2; exit 2 ;;
  esac
  # New shield names avoid stale copies from historical injection-based builds.
  build_dir="$REPO_ROOT/build/module-zmk-$FORMAT-$KEYMAP-$side"
  args=(-d "$build_dir" -b nice_nano@2.0.0/nrf52840/zmk)
  extra_conf="$REPO_ROOT/config/charybdis.conf"
  if [[ "$side" == left || "$side" == right ]]; then
    extra_conf+=";$REPO_ROOT/config/charybdis_$side.conf"
  fi
  if [[ "$FORMAT/$side" == bt/right ]]; then
    args+=(-S studio-rpc-usb-uart)
  fi
  echo "Building $KEYMAP / $FORMAT / $side from the boards module"
  (cd "$ZMK_APP" && west build "${args[@]}" --cmake-only -- \
    "-DZMK_CONFIG=$REPO_ROOT/config" \
    "-DZMK_EXTRA_MODULES=$REPO_ROOT/boards" \
    "-DSHIELD=$shield" \
    "-DEXTRA_CONF_FILE=$extra_conf" \
    "-DEXTRA_DTC_OVERLAY_FILE=" \
    "-DKEYMAP_FILE=$KEYMAP_FILE")
  python3 "$REPO_ROOT/local-build/validate_build.py" "$build_dir" --format "$FORMAT" --side "$side"
  [[ "$CONFIGURE_ONLY" != 1 ]] || continue
  cmake --build "$build_dir"
  python3 "$REPO_ROOT/local-build/verify_firmware.py" "$build_dir" "$build_dir/zephyr/zmk.uf2" --format "$FORMAT" --side "$side"
  output="$REPO_ROOT/firmwares/charybdis_$FORMAT/$KEYMAP"
  mkdir -p "$output"
  cp "$build_dir/zephyr/zmk.uf2" "$output/charybdis_$side.uf2"
done
if [[ "$CONFIGURE_ONLY" == 1 ]]; then
  echo "Configuration validated; firmware compilation was not run."
else
  echo "Firmware files: $REPO_ROOT/firmwares/charybdis_$FORMAT/$KEYMAP/"
fi

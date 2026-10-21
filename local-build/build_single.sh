#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=/workspaces/zmk
ZMK_APP="$REPO_ROOT/zmk/app"
KEYMAP="${1:-qwerty}"
FORMAT="${2:-bt}"
CONFIGURE_ONLY="${CONFIGURE_ONLY:-0}"
if [[ -n "${3:-}" ]]; then
  sides=("$3")
elif [[ "$FORMAT" == dongle ]]; then
  sides=(dongle left right)
else
  sides=(left right)
fi

cd "$REPO_ROOT"

copy_if_changed() {
  local source="$1" destination="$2"
  mkdir -p "$(dirname "$destination")"
  if [[ ! -f "$destination" ]] || ! cmp -s "$source" "$destination"; then
    cp "$source" "$destination"
  fi
}

copy_tree_if_changed() {
  local source_dir="$1" destination_dir="$2" source_file relative_path
  mkdir -p "$destination_dir"
  while IFS= read -r -d '' source_file; do
    relative_path="${source_file#"$source_dir"/}"
    copy_if_changed "$source_file" "$destination_dir/$relative_path"
  done < <(find "$source_dir" -type f -print0)
}

if [[ ! -d "$REPO_ROOT/.west" ]]; then
  west init -l config
  west update
fi

PMW_PATCH="$REPO_ROOT/patches/pmw3610-wakeup-source.patch"
PMW_DRIVER="$REPO_ROOT/zmk-pmw3610-driver"
if ! git -C "$PMW_DRIVER" apply --ignore-space-change --reverse --check "$PMW_PATCH" >/dev/null 2>&1; then
  git -C "$PMW_DRIVER" apply --ignore-space-change "$PMW_PATCH"
fi

west zephyr-export

case "$FORMAT" in
  bt|dongle) ;;
  *) echo "Unsupported format: $FORMAT (use bt or dongle)" >&2; exit 2 ;;
esac

KEYMAP_FILE="$REPO_ROOT/config/keymap/$KEYMAP.keymap"
SHIELD_SOURCE="$REPO_ROOT/boards/shields/charybdis_$FORMAT"
if [[ ! -f "$KEYMAP_FILE" ]]; then
  echo "Keymap not found: $KEYMAP_FILE" >&2
  exit 2
fi
if [[ ! -d "$SHIELD_SOURCE" ]]; then
  echo "Shield not found: $SHIELD_SOURCE" >&2
  exit 2
fi

mkdir -p "$ZMK_APP/overlays"
copy_if_changed "$KEYMAP_FILE" "$ZMK_APP/overlays/charybdis.keymap"
for helper in "$REPO_ROOT"/config/keymap/*.dtsi; do
  [[ -f "$helper" ]] && copy_if_changed "$helper" "$ZMK_APP/overlays/$(basename "$helper")"
done

for side in "${sides[@]}"; do
  if [[ "$side" != left && "$side" != right && "$side" != dongle ]]; then
    echo "Unsupported target: $side (use left, right, or dongle)" >&2
    exit 2
  fi
  shield="charybdis_$side"
  output_shield="$shield"
  if [[ "$FORMAT" == dongle && "$side" == right ]]; then
    shield=charybdis_dongle_right
  fi
  dest="$ZMK_APP/boards/shields/charybdis_$FORMAT"
  mkdir -p "$ZMK_APP/boards/shields"
  mkdir -p "$dest"
  copy_tree_if_changed "$SHIELD_SOURCE" "$dest"

  for helper in charybdis-layouts.dtsi charybdis_pmw3610.dtsi charybdis_pointer.dtsi; do
    if [[ -f "$REPO_ROOT/config/$helper" ]]; then
      copy_if_changed "$REPO_ROOT/config/$helper" "$dest/$helper"
    fi
  done

  # The base nice_nano target omits ZMK flash storage and the P0.13 power rail.
  # A new directory avoids reusing CMake's cached base-board configuration.
  build_dir="$REPO_ROOT/build/nice-nano-zmk-$FORMAT-$KEYMAP-$side"
  args=(-d "$build_dir" -b nice_nano@2.0.0/nrf52840/zmk)
  # Clear diagnostic overlays/configs retained in the CMake cache.
  extra_conf_args=("-DEXTRA_CONF_FILE=" "-DEXTRA_DTC_OVERLAY_FILE=")
  if [[ "$FORMAT" == dongle && "$side" == right ]]; then
    extra_conf_args[0]="-DEXTRA_CONF_FILE=$REPO_ROOT/config/charybdis.conf;$REPO_ROOT/config/charybdis_right.conf"
  fi
  if [[ "$FORMAT" == bt && "$side" == right ]]; then
    args+=(-S studio-rpc-usb-uart)
  fi

  echo "Building $KEYMAP / $FORMAT / $side"
  (cd "$ZMK_APP" && west build "${args[@]}" --cmake-only -- \
    "-DZMK_CONFIG=$REPO_ROOT/config" \
    "-DSHIELD=$shield" \
    "${extra_conf_args[@]}" \
    -DKEYMAP_FILE=overlays/charybdis.keymap)

  python3 "$REPO_ROOT/local-build/validate_build.py" "$build_dir" --format "$FORMAT" --side "$side"
  if [[ "$CONFIGURE_ONLY" == 1 ]]; then
    continue
  fi
  cmake --build "$build_dir"

  output="$REPO_ROOT/firmwares/charybdis_$FORMAT/$KEYMAP"
  mkdir -p "$output"
  cp "$build_dir/zephyr/zmk.uf2" "$output/$output_shield.uf2"
done

if [[ "$CONFIGURE_ONLY" == 1 ]]; then
  echo "Configuration validated; firmware compilation was not run."
else
  echo "Firmware files: $REPO_ROOT/firmwares/charybdis_$FORMAT/$KEYMAP/"
fi

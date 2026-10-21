#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
ZMK_APP="$REPO_ROOT/zmk/app"
KEYMAP="${1:-qwerty}"
FORMAT="${2:-bt}"
CONFIGURE_ONLY="${CONFIGURE_ONLY:-0}"
[[ "$FORMAT" != reset ]] || KEYMAP=default
selector=(--format "$FORMAT" --keymap "$KEYMAP")
[[ -z "${3:-}" ]] || selector+=(--side "$3")
selected=$(python3 "$REPO_ROOT/scripts/generate_matrix.py" "${selector[@]}" --sides)
mapfile -t sides <<< "$selected"

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
# Preserve the originating peripheral only for combos explicitly opting in.
# PercentPrint uses the left-hand trigger to keep output ordered left/right.
COMBO_PATCH="$REPO_ROOT/patches/zmk-combo-pass-source.patch"
if ! git -C "$REPO_ROOT/zmk" apply --reverse --check "$COMBO_PATCH" >/dev/null 2>&1; then
  git -C "$REPO_ROOT/zmk" apply --check "$COMBO_PATCH"
  git -C "$REPO_ROOT/zmk" apply "$COMBO_PATCH"
fi
west zephyr-export

built=()
destinations=()
for side in "${sides[@]}"; do
  target_info=$(python3 "$REPO_ROOT/scripts/generate_matrix.py" --format "$FORMAT" --side "$side" --keymap "$KEYMAP" --target-lines)
  mapfile -t target <<< "$target_info"
  board="${target[0]}"
  shield="${target[1]}"
  extra_conf=""
  IFS=';' read -r -a conf_files <<< "${target[2]}"
  for conf in "${conf_files[@]}"; do
    extra_conf+="${extra_conf:+;}$REPO_ROOT/config/$conf"
  done
  build_dir="$REPO_ROOT/build/module-zmk-$FORMAT-$KEYMAP-$side"
  args=(-d "$build_dir" -b "$board")
  [[ -z "${target[3]}" ]] || args+=(-S "${target[3]}")
  cmake_args=("-DZMK_CONFIG=$REPO_ROOT/config"
    "-DZMK_EXTRA_MODULES=$REPO_ROOT/boards"
    "-DSHIELD=$shield"
    "-DEXTRA_CONF_FILE=$extra_conf"
    "-DEXTRA_DTC_OVERLAY_FILE=")
  if [[ "$FORMAT" != reset ]]; then
    cmake_args+=("-DKEYMAP_FILE=$REPO_ROOT/config/keymap/$KEYMAP.keymap")
    output="$REPO_ROOT/firmwares/charybdis_$FORMAT/$KEYMAP/${target[4]}"
  else
    output="$REPO_ROOT/firmwares/${target[4]}"
  fi
  echo "Building $KEYMAP / $FORMAT / $side from build.yaml"
  (cd "$ZMK_APP" && west build "${args[@]}" --cmake-only -- "${cmake_args[@]}")
  python3 "$REPO_ROOT/local-build/validate_build.py" "$build_dir" --format "$FORMAT" --side "$side"
  [[ "$CONFIGURE_ONLY" != 1 ]] || continue
  cmake --build "$build_dir"
  python3 "$REPO_ROOT/local-build/verify_firmware.py" "$build_dir" "$build_dir/zephyr/zmk.uf2" --format "$FORMAT" --side "$side"
  built+=("$build_dir/zephyr/zmk.uf2")
  destinations+=("$output")
done
if [[ "$CONFIGURE_ONLY" == 1 ]]; then
  echo "Configuration validated; firmware compilation was not run."
else
  # Leave the previous bundle intact if any target failed to compile or validate.
  for i in "${!built[@]}"; do
    mkdir -p "$(dirname -- "${destinations[$i]}")"
    cp "${built[$i]}" "${destinations[$i]}"
    echo "Firmware: ${destinations[$i]}"
  done
fi

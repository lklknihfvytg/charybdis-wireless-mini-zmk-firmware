#!/usr/bin/env bash
# Compatibility entry point; use the cached, module-based builder.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/build_single.sh" "$@"

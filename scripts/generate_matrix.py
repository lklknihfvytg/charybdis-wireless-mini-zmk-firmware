"""Resolve both local build targets and the Actions matrix from build.yaml."""

import argparse
import json
import re
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
SIDES = {"bt": {"left", "right"}, "dongle": {"dongle", "left", "right"}, "reset": {"reset"}}
TOKEN = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.-]*\Z")


def load_targets(root=ROOT):
    data = yaml.safe_load((root / "build.yaml").read_text(encoding="utf-8"))
    board = data["board"]
    if not isinstance(board, str) or not re.fullmatch(r"[\w@./-]+", board):
        raise ValueError("Invalid board target")
    targets = data["include"]
    if not isinstance(targets, list) or not targets:
        raise ValueError("No build targets")
    seen = set()
    outputs = set()
    for target in targets:
        mode, side = target["format"], target["side"]
        if mode not in SIDES or side not in SIDES[mode]:
            raise ValueError(f"Invalid target: {mode}/{side}")
        if (mode, side) in seen:
            raise ValueError(f"Duplicate target: {mode}/{side}")
        seen.add((mode, side))
        for key in ("shield", "output"):
            if not isinstance(target[key], str) or not TOKEN.fullmatch(target[key]):
                raise ValueError(f"Invalid {key}: {target[key]}")
        output = target["output"]
        if not output.endswith(".uf2") or (mode, output) in outputs:
            raise ValueError(f"Invalid or duplicate output: {mode}/{output}")
        expected_output = "settings_reset.uf2" if mode == "reset" else f"charybdis_{side}.uf2"
        if output != expected_output:
            raise ValueError(f"Invalid output for {mode}/{side}: expected {expected_output}")
        outputs.add((mode, output))
        snippet = target.get("snippet", "")
        if snippet and not TOKEN.fullmatch(snippet):
            raise ValueError(f"Invalid snippet: {snippet}")
        confs = target["extra_conf_files"]
        if not isinstance(confs, list):
            raise ValueError("extra_conf_files must be a list")
        for name in confs:
            if not isinstance(name, str) or not TOKEN.fullmatch(name) or not (root / "config" / name).is_file():
                raise ValueError(f"Invalid or missing configuration: {name}")
    expected = {(mode, side) for mode, sides in SIDES.items() for side in sides}
    if seen != expected:
        raise ValueError(f"Missing targets: {expected - seen}")
    return board, targets


def keymap_path(keymap, root=ROOT):
    if not TOKEN.fullmatch(keymap) or not (root / "config/keymap" / f"{keymap}.keymap").is_file():
        raise ValueError(f"Invalid or missing keymap: {keymap}")
    return root / "config/keymap" / f"{keymap}.keymap"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--format", choices=tuple(SIDES))
    parser.add_argument("--side")
    parser.add_argument("--keymap", default="qwerty")
    parser.add_argument("--sides", action="store_true")
    parser.add_argument("--target-lines", action="store_true")
    args = parser.parse_args()
    try:
        board, targets = load_targets()
        if args.sides or args.target_lines:
            if not args.format:
                raise ValueError("--format is required")
            if args.format != "reset":
                keymap_path(args.keymap)
            chosen = [t for t in targets if t["format"] == args.format and (not args.side or t["side"] == args.side)]
            if not chosen:
                raise ValueError(f"Unsupported target: {args.format}/{args.side}")
            if args.sides:
                print("\n".join(t["side"] for t in chosen))
            else:
                if len(chosen) != 1:
                    raise ValueError("--side must select exactly one target")
                t = chosen[0]
                print("\n".join((board, t["shield"], ";".join(t["extra_conf_files"]), t.get("snippet", ""), t["output"])))
            return
        keymaps = sorted(p.stem for p in (ROOT / "config/keymap").glob("*.keymap"))
        if not keymaps:
            raise ValueError("No keymaps found")
        groups = []
        for keymap in keymaps:
            keymap_path(keymap)
            for mode in ("bt", "dongle"):
                groups.append(dict(keymap=keymap, format=mode, name=f"{keymap}-{mode}",
                                   board=board, artifact_path=f"firmwares/charybdis_{mode}/{keymap}/*.uf2"))
        groups.append(dict(keymap="default", format="reset", name="reset-nanov2", board=board,
                           artifact_path="firmwares/settings_reset.uf2"))
        print(json.dumps(groups))
    except (OSError, ValueError, KeyError, TypeError, yaml.YAMLError) as exc:
        parser.exit(2, f"Invalid build description: {exc}\n")


if __name__ == "__main__":
    main()

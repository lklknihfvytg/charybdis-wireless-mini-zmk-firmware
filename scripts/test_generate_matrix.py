"""Guard against selecting wrong targets or overwriting another firmware file."""

import shutil
import tempfile
import unittest
from pathlib import Path

import yaml

from generate_matrix import ROOT, keymap_path, load_targets


class BuildDescriptionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "config/keymap").mkdir(parents=True)
        shutil.copyfile(ROOT / "build.yaml", self.root / "build.yaml")
        self.data = yaml.safe_load((self.root / "build.yaml").read_text())
        for name in {n for t in self.data["include"] for n in t["extra_conf_files"]}:
            (self.root / "config" / name).touch()

    def save(self):
        (self.root / "build.yaml").write_text(yaml.safe_dump(self.data))

    def test_duplicate_target_rejected(self):
        self.data["include"].append(self.data["include"][0].copy())
        self.save()
        with self.assertRaisesRegex(ValueError, "Duplicate target"):
            load_targets(self.root)

    def test_missing_half_rejected(self):
        self.data["include"] = [t for t in self.data["include"] if (t["format"], t["side"]) != ("dongle", "left")]
        self.save()
        with self.assertRaisesRegex(ValueError, "Missing targets"):
            load_targets(self.root)

    def test_output_cannot_escape_bundle_or_overwrite_other_half(self):
        first, second = self.data["include"][:2]
        for output in ("../charybdis_left.uf2", first["output"]):
            with self.subTest(output=output):
                second["output"] = output
                self.save()
                with self.assertRaisesRegex(ValueError, "output"):
                    load_targets(self.root)

    def test_missing_conf_rejected(self):
        self.data["include"][0]["extra_conf_files"].append("missing.conf")
        self.save()
        with self.assertRaisesRegex(ValueError, "configuration"):
            load_targets(self.root)

    def test_swapped_half_filenames_rejected(self):
        first, second = self.data["include"][:2]
        first["output"], second["output"] = second["output"], first["output"]
        self.save()
        with self.assertRaisesRegex(ValueError, "output"):
            load_targets(self.root)

    def test_keymap_cannot_escape_directory(self):
        for keymap in ("../qwerty", "missing"):
            with self.subTest(keymap=keymap), self.assertRaisesRegex(ValueError, "keymap"):
                keymap_path(keymap, self.root)


if __name__ == "__main__":
    unittest.main()

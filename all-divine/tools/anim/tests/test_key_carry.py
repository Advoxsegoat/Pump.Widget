"""Tests for tools/anim/key_carry.py: it writes the same layers every time, `--check` says whether the committed layers are what
it makes, and the committed layers are."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]  # the all-divine folder
SCRIPT = ROOT / "tools" / "anim" / "key_carry.py"


def run(*args):
    done = subprocess.run([sys.executable, "-I", str(SCRIPT), *args], capture_output=True, text=True)
    return done.returncode, done.stdout + done.stderr


class KeyCarry(unittest.TestCase):
    def test_the_committed_layers_are_what_it_makes(self):
        status, output = run("--check")
        self.assertEqual(status, 0, output)

    def test_check_finds_a_layer_that_differs_or_is_missing_and_writes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            status, output = run("--check", "--layers", tmp)
            self.assertEqual(status, 1, "an empty folder is wrong")
            self.assertEqual(list(Path(tmp).iterdir()), [], "--check writes nothing")
            self.assertEqual(run("--layers", tmp)[0], 0)
            self.assertEqual(run("--check", "--layers", tmp)[0], 0, "what it wrote is what it checks")
            (Path(tmp) / "blade_idle.json").write_text("{}\n")
            status, output = run("--check", "--layers", tmp)
            self.assertEqual(status, 1)
            self.assertIn("blade_idle.json", output)


if __name__ == "__main__":
    unittest.main()

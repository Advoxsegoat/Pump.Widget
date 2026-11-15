"""Nothing in tools/ writes into assets/portraits/ but the sketch tool (and, later, the tool that makes a stand-in card).
The old exporter of the earlier game's 48 x 48 portraits did, and would have overwritten the owner's drawing; it is gone,
and this keeps another from arriving. A file under tools/ that names the folder is either one of the writers below or a
test that only reads the picture.

Run: python3 -I -m unittest discover -s tools/portraits/tests   (from all-divine/)
"""
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.abspath(os.path.join(HERE, "..", ".."))
# the tools allowed to write there (paths under tools/)
WRITERS = {"portraits/sketch_to_portrait.py"}
# the tests of the portraits tools read the committed picture; they write only into temporary folders
READERS = "portraits/tests/"
TEXT = (".py", ".mjs", ".js", ".gd", ".sh", ".json", ".cfg", ".md", ".txt", ".yml", ".yaml")


class OneWriterTest(unittest.TestCase):
    def test_only_the_sketch_tool_writes_into_the_portraits_folder(self):
        found = []
        for root, dirs, files in os.walk(TOOLS):
            dirs[:] = [d for d in dirs if d not in ("__pycache__", ".venv", "node_modules")]
            for name in files:
                if not name.endswith(TEXT):
                    continue
                path = os.path.join(root, name)
                relative = os.path.relpath(path, TOOLS).replace(os.sep, "/")
                if relative in WRITERS or relative.startswith(READERS):
                    continue
                with open(path, encoding="utf-8", errors="replace") as handle:
                    if "assets/portraits" in handle.read():
                        found.append(relative)
        self.assertEqual(found, [], "a tool names assets/portraits and is not the sketch tool: %s (a second writer there can overwrite "
                         "the owner's drawing; add it to WRITERS only if it is meant to)" % ", ".join(found))

    def test_the_old_exporter_is_gone(self):
        self.assertFalse(os.path.exists(os.path.join(TOOLS, "portraits", "export_portraits.mjs")),
                         "tools/portraits/export_portraits.mjs writes 48 x 48 pictures over the owner's drawing")


if __name__ == "__main__":
    unittest.main()

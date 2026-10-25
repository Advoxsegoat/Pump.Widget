"""Tests for tools/assets/import_kenney.py (copying Kenney pieces). Standard library only."""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import import_kenney  # noqa: E402


class ImportKenney(unittest.TestCase):
    def setUp(self):
        holder = tempfile.TemporaryDirectory()
        self.addCleanup(holder.cleanup)
        tmp = Path(holder.name)
        self.src = tmp / "extract"
        glb = self.src / "Models" / "GLB format"
        (glb / "Textures").mkdir(parents=True)
        (glb / "wall.glb").write_bytes(b"wall")
        (glb / "tree.glb").write_bytes(b"tree")
        (glb / "other.glb").write_bytes(b"not listed")
        (glb / "Textures" / "colormap.png").write_bytes(b"png")
        self.dest = tmp / "assets" / "env" / "kenney_town"
        self.pieces = tmp / "pieces.txt"
        self.pieces.write_text("# walls\nwall\n\n  tree  \n")

    def test_copies_listed_pieces_and_the_texture_keeping_its_relative_path(self):
        copied = import_kenney.import_pieces(self.src, self.dest, self.pieces)
        self.assertEqual(sorted(copied), ["Textures/colormap.png", "tree.glb", "wall.glb"])
        self.assertEqual((self.dest / "wall.glb").read_bytes(), b"wall")
        self.assertEqual((self.dest / "Textures" / "colormap.png").read_bytes(), b"png")
        self.assertFalse((self.dest / "other.glb").exists(), "only listed pieces are copied")

    def test_a_piece_missing_from_the_pack_is_an_error_and_nothing_is_copied(self):
        self.pieces.write_text("wall\nno-such-piece\n")
        with self.assertRaises(FileNotFoundError) as caught:
            import_kenney.import_pieces(self.src, self.dest, self.pieces)
        self.assertIn("no-such-piece", str(caught.exception))
        self.assertFalse(self.dest.exists())

    def test_running_twice_is_harmless(self):
        import_kenney.import_pieces(self.src, self.dest, self.pieces)
        import_kenney.import_pieces(self.src, self.dest, self.pieces)
        self.assertEqual((self.dest / "tree.glb").read_bytes(), b"tree")


if __name__ == "__main__":
    unittest.main()

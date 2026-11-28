"""Tests for tools/test/shard_weights.py: run as `python3 -I -m unittest discover -s tools/test/tests` from all-divine/."""
import contextlib
import io
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import shard_weights  # noqa: E402

LOG = """2026-11-15T10:00:00.1234567Z PASS res://tests/bot/test_combat_bot.gd::test_a
2026-11-15T10:00:00.2234567Z PASS res://tests/bot/test_combat_bot.gd::test_b
2026-11-15T10:03:21.0000000Z FILE-SECONDS 201.4 bot/test_combat_bot.gd
2026-11-15T10:03:22.0000000Z FILE-SECONDS 0.8 core/test_tiny.gd
\x1b[0mFILE-SECONDS 33.0 story/test_cine_camera.gd
FILE-SECONDS nonsense bot/test_bad.gd
FILE-SECONDS 12.0
12 passed, 0 failed
"""


class ReadLog(unittest.TestCase):
    def test_takes_the_seconds_of_each_files_line_from_a_ci_log(self):
        self.assertEqual(shard_weights.read_log(LOG), {
            "bot/test_combat_bot.gd": 201.4, "core/test_tiny.gd": 0.8, "story/test_cine_camera.gd": 33.0})

    def test_a_file_in_two_logs_takes_the_longer_time(self):
        merged = shard_weights.merge([{"a/test_x.gd": 10.0, "a/test_y.gd": 4.0}, {"a/test_x.gd": 30.0}])
        self.assertEqual(merged, {"a/test_x.gd": 30.0, "a/test_y.gd": 4.0})


class Weights(unittest.TestCase):
    def test_a_file_under_the_default_weight_is_left_out_and_the_rest_are_rounded_up_slowest_first(self):
        text = shard_weights.render({"core/test_tiny.gd": 0.8, "bot/test_combat_bot.gd": 201.4, "a/test_five.gd": 5.0, "b/test_six.gd": 5.2},
                                    "# header\n")
        lines = [l for l in text.split("\n") if l and not l.startswith("#")]
        self.assertEqual([l.split()[:2] for l in lines], [["202", "bot/test_combat_bot.gd"], ["6", "b/test_six.gd"]])
        self.assertTrue(text.startswith("# header\n"))

    def test_the_output_is_what_the_game_reads_back(self):
        # TestRunner.read_weights: `<seconds> <path>` with a # comment after; both words are there on every weight line
        text = shard_weights.render({"bot/test_combat_bot.gd": 201.4}, "")
        weighed = [line for line in text.split("\n") if line and not line.startswith("#")]
        self.assertEqual(len(weighed), 1)
        words = weighed[0].split("#")[0].split()
        self.assertEqual(len(words), 2)
        self.assertGreater(float(words[0]), 0)

    def test_a_file_that_is_gone_is_dropped_and_a_file_not_in_the_logs_keeps_its_old_weight(self):
        with tempfile.TemporaryDirectory() as tests:
            os.makedirs(os.path.join(tests, "bot"))
            for name in ("bot/test_here.gd", "bot/test_unseen.gd"):
                open(os.path.join(tests, name), "w").close()
            old = "# header\n100  bot/test_unseen.gd   # render log\n50  bot/test_gone.gd   # render log\n"
            text = shard_weights.update(old, [{"bot/test_here.gd": 40.0, "bot/test_gone.gd": 60.0}], tests)
            lines = [l.split("#")[0].split() for l in text.split("\n") if l and not l.startswith("#")]
            self.assertEqual(lines, [["100", "bot/test_unseen.gd"], ["40", "bot/test_here.gd"]])
            self.assertTrue(text.startswith("# header\n"))
            # the weight kept from before still says where it came from; the measured one says it was measured
            comments = {l.split("#")[0].split()[1]: l.split("#", 1)[1].strip() for l in text.split("\n") if l and not l.startswith("#")}
            self.assertEqual(comments["bot/test_unseen.gd"], "render log")
            self.assertEqual(comments["bot/test_here.gd"], "measured in a render shard")

    def test_the_header_is_the_comment_lines_before_the_first_weight(self):
        old = "# one\n#\n# two\n\n575  a/test_x.gd   # render log\n# not header\n"
        self.assertEqual(shard_weights.header_of(old), "# one\n#\n# two\n\n")


class RunKind(unittest.TestCase):
    def test_a_log_says_what_kind_of_run_it_is_from_its_run_kind_line(self):
        self.assertEqual(shard_weights.run_kind("2026-11-15T10:00:00Z RUN-KIND render\nPASS x\n"), "render")
        self.assertEqual(shard_weights.run_kind("RUN-KIND headless\nFILE-SECONDS 85.0 bot/test_x.gd\n"), "headless")
        self.assertIsNone(shard_weights.run_kind("FILE-SECONDS 85.0 bot/test_x.gd\n"), "a log from before the line says nothing")

    def test_only_a_render_runs_log_is_taken(self):
        with tempfile.TemporaryDirectory() as folder:
            paths = {}
            for name, text in (("render", "RUN-KIND render\nFILE-SECONDS 85.0 bot/test_x.gd\n"),
                               ("headless", "RUN-KIND headless\nFILE-SECONDS 8.0 bot/test_x.gd\n"),
                               ("bare", "FILE-SECONDS 8.0 bot/test_x.gd\n")):
                paths[name] = os.path.join(folder, name + ".log")
                with open(paths[name], "w") as handle:
                    handle.write(text)
            weights = os.path.join(folder, "weights.txt")
            with open(weights, "w") as handle:
                handle.write("# header\n")
            self.assertEqual(shard_weights.main([paths["render"], "--tests", folder, "--weights", weights]), 0)
            for name in ("headless", "bare"):
                stderr = io.StringIO()
                with contextlib.redirect_stderr(stderr):
                    self.assertEqual(shard_weights.main([paths["render"], paths[name], "--tests", folder, "--weights", weights]), 1)
                self.assertIn("not a render run's log", stderr.getvalue())
                self.assertIn(paths[name], stderr.getvalue())


if __name__ == "__main__":
    unittest.main()

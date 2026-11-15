#!/usr/bin/env python3
"""Makes tests/shard_weights.txt from the logs of CI's render shards.

A test run prints one line for each test file, `FILE-SECONDS <seconds> <path under tests/>` (tools/test/test_runner.gd,
time_line), and CI's log of a render shard keeps them. The weights file deals the files to the shards (TestRunner.shard), so
it holds each slow file's seconds in a render shard: this turns the logs into it.

    python3 -I tools/test/shard_weights.py [--tests tests] [--weights tests/shard_weights.txt] [--write] LOG [LOG ...]

Prints the new file (or, with --write, replaces `--weights` with it). A file is taken at the longest time any log gives it. A
file not in the logs keeps the weight it had; a file that no longer exists under --tests is dropped; a file at the default
weight (5 s) or under is left out, since a file not named there weighs that. The header (the comment lines before the first
weight) is kept as it was. Give it only render shards' logs: the headless job's times are an eighth of these.
"""
import argparse
import math
import os
import re
import sys

#: What a file not named in the weights file weighs (TestRunner.DEFAULT_WEIGHT).
DEFAULT_WEIGHT = 5.0
MEASURED = "measured in a render shard"
_LINE = re.compile(r"FILE-SECONDS (\d+(?:\.\d+)?) (\S+)")


def read_log(text):
    """The seconds of each test file a CI log names: {path under tests/: seconds}."""
    found = {}
    for line in text.split("\n"):
        match = _LINE.search(line)
        if match:
            found[match.group(2)] = float(match.group(1))
    return found


def merge(logs):
    """The files of several logs together, each at its longest time."""
    merged = {}
    for log in logs:
        for path, seconds in log.items():
            merged[path] = max(seconds, merged.get(path, 0.0))
    return merged


def header_of(text):
    """The comment and blank lines before the first weight."""
    lines = text.split("\n")
    count = 0
    for line in lines:
        if line.strip() and not line.startswith("#"):
            break
        count += 1
    return "".join(line + "\n" for line in lines[:count])


def render(weights, header, notes=None):
    """The file: `header`, then a line `<seconds, rounded up> <path>   # <note>` for each file over the default weight, slowest first.
    A file's note is `notes[path]` (where an older weight came from) or else that it was measured."""
    notes = notes or {}
    heavy = sorted(((s, p) for p, s in weights.items() if s > DEFAULT_WEIGHT), key=lambda item: (-item[0], item[1]))
    return header + "".join("%-4d %s   # %s\n" % (math.ceil(s), p, notes.get(p, MEASURED)) for s, p in heavy)


def _old_weights(text):
    """{path: (seconds, note)} of the weight lines of a weights file."""
    old = {}
    for line in text.split("\n"):
        words = line.split("#")[0].split()
        if len(words) == 2:
            try:
                old[words[1]] = (float(words[0]), line.partition("#")[2].strip() or MEASURED)
            except ValueError:
                pass
    return old


def update(old_text, logs, tests_dir):
    """The new weights file: what the logs measured over what `old_text` had, files gone from `tests_dir` dropped."""
    old = _old_weights(old_text)
    weights = {p: seconds for p, (seconds, _) in old.items()}
    notes = {p: note for p, (_, note) in old.items()}
    for path, seconds in merge(logs).items():
        weights[path] = seconds
        notes.pop(path, None)
    weights = {p: s for p, s in weights.items() if os.path.exists(os.path.join(tests_dir, p))}
    return render(weights, header_of(old_text), notes)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("logs", nargs="+")
    parser.add_argument("--tests", default="tests")
    parser.add_argument("--weights", default="tests/shard_weights.txt")
    parser.add_argument("--write", action="store_true", help="replace the weights file instead of printing the new one")
    args = parser.parse_args(argv)
    logs = []
    for path in args.logs:
        with open(path, encoding="utf-8", errors="replace") as handle:
            logs.append(read_log(handle.read()))
    if not any(logs):
        print("shard_weights: no FILE-SECONDS line in any log: not render shards' logs of a run with the times?", file=sys.stderr)
        return 1
    with open(args.weights, encoding="utf-8") as handle:
        old = handle.read()
    text = update(old, logs, args.tests)
    if args.write:
        with open(args.weights, "w", encoding="utf-8") as handle:
            handle.write(text)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

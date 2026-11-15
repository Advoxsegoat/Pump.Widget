"""The owner's side of the sketch tool works where they run it: `tools/setup.sh --portraits` makes (or extends) the project's venv
with the pinned Pillow and numpy and says how to run the tool with that Python (a plain `pip install` goes to the user's site folder,
which `python3 -I` does not read: CI hit that); the tool, started without its libraries, says so in one line and exits 2; and the
README's two commands use the venv's Python.

The script is run here on a copy, in a made folder, with stand-ins for python3 and the downloaders on the path: it must make the
venv, install the pinned libraries into it, say how to run the tool, and not download Godot.

Run: python3 -I -m unittest discover -s tools/portraits/tests   (from all-divine/)
"""
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
REPO = os.path.dirname(PROJECT)
SETUP = os.environ.get("SETUP_SCRIPT", os.path.join(PROJECT, "tools", "setup.sh"))
TOOL = os.path.join(PROJECT, "tools", "portraits", "sketch_to_portrait.py")
README = os.path.join(REPO, "docs", "art", "owner", "README.md")
WORKFLOW = os.path.join(REPO, ".github", "workflows", "all-divine.yml")
PINS = ("pillow==12.3.0", "numpy==2.5.3")

STAND_IN_PYTHON3 = """#!/bin/bash
echo "python3 $*" >> "$LOG"
if [ "$1" = "-m" ] && [ "$2" = "venv" ]; then
  mkdir -p "$3/bin"
  cat > "$3/bin/python" <<'EOF'
#!/bin/bash
echo "venv-python $*" >> "$LOG"
exit 0
EOF
  chmod +x "$3/bin/python"
  exit 0
fi
exit 0
"""
REFUSED = """#!/bin/bash
echo "$(basename "$0") $*" >> "$LOG"
exit 99
"""


def write_executable(path, text):
    with open(path, "w") as handle:
        handle.write(text)
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)


class SetupScriptTest(unittest.TestCase):
    def run_script(self, root, *args):
        bin_dir = os.path.join(root, "bin")
        os.makedirs(bin_dir, exist_ok=True)
        if not os.path.exists(os.path.join(bin_dir, "python3")):
            write_executable(os.path.join(bin_dir, "python3"), STAND_IN_PYTHON3)
            for name in ("curl", "unzip"):   # a download of Godot must not happen
                write_executable(os.path.join(bin_dir, name), REFUSED)
        env = {"PATH": bin_dir + ":/usr/bin:/bin", "LOG": os.path.join(root, "log.txt"), "HOME": root}
        return subprocess.run(["bash", os.path.join(root, "tools", "setup.sh")] + list(args), env=env, capture_output=True, text=True, timeout=60)

    def made_root(self):
        root = tempfile.mkdtemp()
        self.addCleanup(lambda: shutil.rmtree(root, ignore_errors=True))
        os.makedirs(os.path.join(root, "tools"))
        shutil.copy(SETUP, os.path.join(root, "tools", "setup.sh"))
        return root

    def log(self, root):
        path = os.path.join(root, "log.txt")
        if not os.path.exists(path):
            return ""
        with open(path) as handle:
            return handle.read()

    def test_the_script_parses_and_knows_the_flag(self):
        self.assertEqual(subprocess.run(["bash", "-n", SETUP], capture_output=True, text=True).returncode, 0)
        root = self.made_root()
        result = self.run_script(root, "--nonsense")
        self.assertEqual(result.returncode, 2)
        self.assertIn("--portraits", result.stderr, "the usage line does not list --portraits: %s" % result.stderr)

    def test_the_pins_are_the_ones_ci_uses(self):
        with open(SETUP) as handle:
            script = handle.read()
        with open(WORKFLOW) as handle:
            workflow = handle.read()
        for pin in PINS:
            self.assertIn(pin, workflow.lower(), "CI's Python step does not pin %s" % pin)
        self.assertRegex(script, r'PILLOW_VERSION="12\.3\.0"')
        self.assertRegex(script, r'NUMPY_VERSION="2\.5\.3"')

    def test_portraits_makes_the_venv_installs_the_pins_and_says_how_to_run_the_tool(self):
        root = self.made_root()
        result = self.run_script(root, "--portraits")
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self.log(root)
        self.assertRegex(log, r"python3 -m venv .*tools/\.venv", "the venv was not made: %s" % log)
        install = [line for line in log.splitlines() if "pip install" in line]
        self.assertEqual(len(install), 1, log)
        for pin in PINS:
            self.assertIn(pin, install[0])
        self.assertIn("venv-python -m pip install", install[0], "the libraries were not installed into the venv's own Python")
        self.assertIn("tools/.venv/bin/python -I tools/portraits/sketch_to_portrait.py", result.stdout, "the output does not say how to run the tool")
        self.assertNotIn("curl", log, "--portraits on its own fetched something (Godot)")
        self.assertNotIn("unzip", log)

    def test_a_second_run_adds_to_the_venv_it_finds(self):
        root = self.made_root()
        self.assertEqual(self.run_script(root, "--portraits").returncode, 0)
        before = self.log(root).count("-m venv")
        self.assertEqual(self.run_script(root, "--portraits").returncode, 0)
        log = self.log(root)
        self.assertEqual(log.count("-m venv"), before, "the second run made the venv again")
        self.assertEqual(len([line for line in log.splitlines() if "pip install" in line]), 2)


class MissingLibrariesTest(unittest.TestCase):
    def test_the_tool_without_numpy_says_so_in_one_line_and_exits_2(self):
        # `sys.modules[name] = None` makes `import name` fail, as it does on a Python that has not got the library
        for missing in ("numpy", "PIL"):
            code = "import sys, runpy; sys.modules[%r] = None; sys.argv = ['sketch_to_portrait.py', '--help']; runpy.run_path(%r, run_name='__main__')" % (missing, TOOL)
            result = subprocess.run([sys.executable, "-I", "-c", code], capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 2, "%s missing: %s" % (missing, result.stderr))
            self.assertEqual(len(result.stderr.strip().splitlines()), 1, "%s missing: %r" % (missing, result.stderr))
            self.assertNotIn("Traceback", result.stderr)
            self.assertIn("tools/setup.sh --portraits", result.stderr)
            self.assertIn("tools/.venv/bin/python", result.stderr)
            self.assertIn("Pillow and numpy", result.stderr)


class ReadmeTest(unittest.TestCase):
    def test_adding_a_drawing_uses_the_venvs_python_in_both_commands(self):
        with open(README) as handle:
            text = handle.read()
        section = text[text.index("## Adding a drawing"):]
        section = section.split("\n## ")[0]
        self.assertIn("tools/setup.sh --portraits", section)
        commands = [line for line in section.splitlines() if "sketch_to_portrait.py" in line and ("--init-recipe" in line or "--sketch" in line)]
        self.assertEqual(len(commands), 2, commands)
        for command in commands:
            self.assertIn("tools/.venv/bin/python -I tools/portraits/sketch_to_portrait.py", command)
            self.assertNotRegex(command, r"(?<![./\w])python3 -I")


if __name__ == "__main__":
    unittest.main()

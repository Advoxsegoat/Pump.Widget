"""Tests for tools/assets/fetch.py. Standard library only, and no network beyond 127.0.0.1.

Run from the repository root:
    python3 -I -m unittest discover -s all-divine/tools/assets/tests -v
"""
import contextlib
import hashlib
import io
import json
import sys
import tempfile
import threading
import unittest
import urllib.parse
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# -I leaves the script's own folder off sys.path; this is our code, not downloaded code.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import fetch  # noqa: E402


def make_zip(path, members):
    """Writes a zip whose member names are used exactly as given (no sanitising)."""
    with zipfile.ZipFile(path, "w") as z:
        for name, data in members:
            z.writestr(zipfile.ZipInfo(name), data)


class TempDirCase(unittest.TestCase):
    def setUp(self):
        holder = tempfile.TemporaryDirectory()
        self.addCleanup(holder.cleanup)
        self.tmp = Path(holder.name)


class SafeExtract(TempDirCase):
    def test_refuses_parent_and_absolute_members(self):
        for bad in ["../evil.txt", "/abs.txt", "a/../../evil.txt", "..\\evil.txt", "C:/evil.txt", "C:\\evil.txt"]:
            with self.subTest(member=bad):
                work = self.tmp / ("case_" + hashlib.sha1(bad.encode()).hexdigest()[:8])
                work.mkdir()
                archive = work / "bad.zip"
                dest = work / "dest"
                # A harmless member comes first: the bad one must stop everything, not just itself.
                make_zip(archive, [("ok.txt", b"fine"), (bad, b"evil")])
                with self.assertRaises(ValueError):
                    fetch.safe_extract(archive, dest)
                self.assertFalse((work / "evil.txt").exists(), "wrote outside dest")
                self.assertFalse(Path("/abs.txt").exists(), "wrote to the filesystem root")
                self.assertEqual(list(dest.rglob("*")) if dest.exists() else [], [], "nothing is extracted when any member is bad")

    def test_extracts_paths_with_spaces_and_brackets(self):
        name = "Universal Base Characters[Standard]/a b.txt"
        payload = bytes(range(256)) + b"\r\n bytes stay intact \x00"
        archive = self.tmp / "ok.zip"
        make_zip(archive, [(name, payload), ("Universal Base Characters[Standard]/sub dir/", b""), ("top.txt", b"t")])
        dest = self.tmp / "dest"
        extracted = fetch.safe_extract(archive, dest)
        self.assertEqual((dest / name).read_bytes(), payload)
        self.assertEqual(sorted(extracted), sorted([name, "top.txt"]))
        self.assertTrue((dest / "Universal Base Characters[Standard]" / "sub dir").is_dir())

    def test_extracts_into_an_existing_folder(self):
        archive = self.tmp / "ok.zip"
        make_zip(archive, [("a/b.txt", b"x")])
        dest = self.tmp / "dest"
        dest.mkdir()
        self.assertEqual(fetch.safe_extract(archive, dest), ["a/b.txt"])
        self.assertEqual((dest / "a" / "b.txt").read_bytes(), b"x")


class Parsing(unittest.TestCase):
    def test_csrf_and_upload_ids(self):
        html = '<input name="csrf_token" value="T0K"> <a data-upload_id="123">x</a><a data-upload_id="456">'
        self.assertEqual(fetch.parse_csrf(html), "T0K")
        self.assertEqual(fetch.parse_upload_ids(html), ["123", "456"])

    def test_csrf_in_the_meta_tag_itch_really_serves(self):
        token = "WyJzMzRkIiwxNzkyOTI2OTIxLCJkZGZmTnRZaWhyajVHaVciXQ==.Olbb3GMafCptOM+kM8/AveLw9zc="
        html = '<head><meta name="csrf_token" value="%s" /></head>' % token
        self.assertEqual(fetch.parse_csrf(html), token)
        self.assertEqual(fetch.parse_csrf('<input value="V4L" type="hidden" name="csrf_token">'), "V4L")

    def test_csrf_missing_raises(self):
        with self.assertRaises(ValueError):
            fetch.parse_csrf("<html><input name='other' value='x'></html>")

    def test_upload_ids_are_listed_once_in_page_order(self):
        html = '<a data-upload_id="9"></a><a data-upload_id="7"></a><a data-upload_id="9"></a>'
        self.assertEqual(fetch.parse_upload_ids(html), ["9", "7"])
        self.assertEqual(fetch.parse_upload_ids("<p>no downloads</p>"), [])

    def test_kenney_zip_link(self):
        html = '<a href="https://kenney.nl/media/pages/assets/fantasy-town-kit/efe948d309-1754222374/kenney_fantasy-town-kit_2.0.zip">'
        self.assertTrue(fetch.parse_kenney_zip(html).endswith("kenney_fantasy-town-kit_2.0.zip"))

    def test_kenney_zip_link_as_the_page_really_writes_it(self):
        html = ("<a id='donate-text' href='https://kenney.nl/media/pages/assets/fantasy-town-kit/efe948d309-1754222374/"
                "kenney_fantasy-town-kit_2.0.zip' onclick='initiateDownload()' data-lity-close>Continue</a>")
        self.assertEqual(
            fetch.parse_kenney_zip(html),
            "https://kenney.nl/media/pages/assets/fantasy-town-kit/efe948d309-1754222374/kenney_fantasy-town-kit_2.0.zip",
        )

    def test_kenney_zip_link_missing_raises(self):
        with self.assertRaises(ValueError):
            fetch.parse_kenney_zip('<a href="/assets/other.html">nope</a>')


class Verify(TempDirCase):
    def setUp(self):
        super().setUp()
        self.path = self.tmp / "pack.zip"
        self.path.write_bytes(b"pack bytes")
        self.actual = hashlib.sha256(b"pack bytes").hexdigest()

    def test_mismatch_raises_unless_accept_new(self):
        self.assertEqual(fetch.verify(self.path, self.actual, False), self.actual)
        self.assertEqual(fetch.verify(self.path, self.actual.upper(), False), self.actual)
        with self.assertRaises(fetch.HashMismatch) as caught:
            fetch.verify(self.path, "0" * 64, False)
        self.assertEqual(caught.exception.actual, self.actual)
        self.assertEqual(caught.exception.expected, "0" * 64)
        self.assertEqual(fetch.verify(self.path, "0" * 64, True), self.actual)

    def test_a_missing_recorded_hash_needs_accept_new_too(self):
        with self.assertRaises(fetch.HashMismatch):
            fetch.verify(self.path, "", False)
        self.assertEqual(fetch.verify(self.path, "", True), self.actual)


class FakeSite:
    """A Kenney-style page and an itch-style download flow, served on 127.0.0.1 from a thread."""

    TOKEN = "T0K+/=.sig"

    def __init__(self, zip_bytes):
        self.zip_bytes = zip_bytes
        self.upload_ids = ["42"]
        self.external = False
        self.requests = []
        site = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def _send(self, body, kind="text/html"):
                data = body if isinstance(body, bytes) else body.encode()
                self.send_response(200)
                self.send_header("Content-Type", kind)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def _form(self):
                length = int(self.headers.get("Content-Length") or 0)
                return self.rfile.read(length).decode()

            def do_GET(self):
                site.requests.append(("GET", self.path))
                base = site.base
                if self.path == "/kenney/page":
                    self._send("<a id='x' href='%s/files/pack.zip' onclick='go()'>Continue</a>" % base)
                elif self.path == "/files/pack.zip":
                    self._send(site.zip_bytes, "application/zip")
                elif self.path == "/itch/page":
                    self._send('<meta name="csrf_token" value="%s" />' % site.TOKEN)
                elif self.path == "/itch/page/download/KEY":
                    links = "".join('<a data-upload_id="%s" class="download_btn">Download</a>' % i for i in site.upload_ids)
                    self._send('<meta name="csrf_token" value="%s" />%s' % (site.TOKEN, links))
                else:
                    self.send_error(404)

            def do_POST(self):
                site.requests.append(("POST", self.path))
                form = self._form()
                if "csrf_token=" not in form or site.TOKEN not in urllib.parse.unquote_plus(form):
                    self.send_error(403)
                elif self.path == "/itch/page/download_url":
                    self._send(json.dumps({"url": site.base + "/itch/page/download/KEY"}), "application/json")
                elif self.path == "/itch/page/file/42?source=game_download":
                    self._send(json.dumps({"external": site.external, "url": site.base + "/files/pack.zip"}), "application/json")
                else:
                    self.send_error(404)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.base = "http://127.0.0.1:%d" % self.server.server_address[1]
        threading.Thread(target=lambda: self.server.serve_forever(poll_interval=0.02), daemon=True).start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()

    def zip_gets(self):
        return sum(1 for r in self.requests if r == ("GET", "/files/pack.zip"))


class Cli(TempDirCase):
    """fetch.main end to end against a local fake site, in a throwaway project root."""

    def setUp(self):
        super().setUp()
        self.zip_path = self.tmp / "served.zip"
        make_zip(self.zip_path, [("Models/a b.glb", b"glb-bytes"), ("License.txt", b"CC0")])
        self.site = FakeSite(self.zip_path.read_bytes())
        self.addCleanup(self.site.close)
        self.root = self.tmp / "root"
        (self.root / "tools" / "assets").mkdir(parents=True)
        self.sources = self.root / "tools" / "assets" / "sources.json"
        self.sources.write_text(json.dumps({
            "kenney_town": {"kind": "kenney", "page": self.site.base + "/kenney/page"},
            "ubc": {"kind": "itch", "page": self.site.base + "/itch/page", "sha256": ""},
        }, indent=2) + "\n")
        self.opener = fetch.make_opener(proxies={})

    def run_main(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = fetch.main(list(argv), root=self.root, opener=self.opener)
        return code, out.getvalue(), err.getvalue()

    def recorded(self, source_id):
        return json.loads(self.sources.read_text())[source_id].get("sha256", "")

    def test_first_fetch_without_accept_new_exits_2_and_changes_nothing(self):
        before = self.sources.read_text()
        code, _, err = self.run_main("fetch", "kenney_town")
        self.assertEqual(code, 2, err)
        self.assertEqual(self.sources.read_text(), before)
        self.assertFalse((self.root / ".cache" / "extract" / "kenney_town").exists())

    def test_accept_new_records_the_hash_and_extracts(self):
        code, _, err = self.run_main("fetch", "kenney_town", "--accept-new")
        self.assertEqual(code, 0, err)
        self.assertEqual(self.recorded("kenney_town"), hashlib.sha256(self.zip_path.read_bytes()).hexdigest())
        self.assertEqual(json.loads(self.sources.read_text())["ubc"]["sha256"], "", "other sources are left alone")
        code, out, _ = self.run_main("path", "kenney_town")
        self.assertEqual(code, 0)
        extract = Path(out.strip())
        self.assertEqual(extract, self.root / ".cache" / "extract" / "kenney_town")
        self.assertEqual((extract / "Models" / "a b.glb").read_bytes(), b"glb-bytes")
        self.assertTrue((self.root / ".cache" / "downloads" / "kenney_town.zip").is_file())

    def test_a_verified_download_is_not_fetched_again(self):
        self.run_main("fetch", "kenney_town", "--accept-new")
        self.assertEqual(self.site.zip_gets(), 1)
        code, _, err = self.run_main("fetch", "kenney_town")
        self.assertEqual(code, 0, err)
        self.assertEqual(self.site.zip_gets(), 1, "the cached zip matched its hash, so no second download")

    def test_a_cached_zip_that_no_longer_matches_is_downloaded_again(self):
        self.run_main("fetch", "kenney_town", "--accept-new")
        cached = self.root / ".cache" / "downloads" / "kenney_town.zip"
        good = cached.read_bytes()
        make_zip(cached, [("Models/a b.glb", b"tampered")])
        code, _, err = self.run_main("fetch", "kenney_town")
        self.assertEqual(code, 0, err)
        self.assertEqual(self.site.zip_gets(), 2)
        self.assertEqual(cached.read_bytes(), good)

    def test_a_usage_mistake_exits_1_because_2_means_hash_mismatch(self):
        for argv in (["fetch"], ["bogus"], []):
            with self.subTest(argv=argv), contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as caught:
                fetch.main(argv, root=self.root, opener=self.opener)
            self.assertEqual(caught.exception.code, 1)

    def test_changed_upstream_exits_2_until_accepted(self):
        self.run_main("fetch", "kenney_town", "--accept-new")
        recorded = self.recorded("kenney_town")
        (self.root / ".cache" / "downloads" / "kenney_town.zip").unlink()
        make_zip(self.zip_path, [("Models/a b.glb", b"NEW-bytes")])
        self.site.zip_bytes = self.zip_path.read_bytes()

        code, _, err = self.run_main("fetch", "kenney_town")
        self.assertEqual(code, 2, err)
        self.assertEqual(self.recorded("kenney_town"), recorded)
        extract = self.root / ".cache" / "extract" / "kenney_town"
        self.assertEqual((extract / "Models" / "a b.glb").read_bytes(), b"glb-bytes", "the old extract is untouched by a refused pack")

        code, _, err = self.run_main("fetch", "kenney_town", "--accept-new")
        self.assertEqual(code, 0, err)
        self.assertEqual(self.recorded("kenney_town"), hashlib.sha256(self.site.zip_bytes).hexdigest())
        self.assertEqual((extract / "Models" / "a b.glb").read_bytes(), b"NEW-bytes")
        self.assertFalse((extract / "License.txt").exists(), "files from the old pack are gone")

    def test_itch_flow_downloads_through_csrf_and_the_upload_id(self):
        code, _, err = self.run_main("fetch", "ubc", "--accept-new")
        self.assertEqual(code, 0, err)
        self.assertEqual(self.recorded("ubc"), hashlib.sha256(self.zip_path.read_bytes()).hexdigest())
        self.assertIn(("POST", "/itch/page/file/42?source=game_download"), self.site.requests)

    def test_an_itch_page_with_several_files_is_refused_rather_than_guessed(self):
        self.site.upload_ids = ["42", "43"]
        code, _, err = self.run_main("fetch", "ubc", "--accept-new")
        self.assertEqual(code, 1)
        self.assertIn("42", err)
        self.assertIn("43", err)
        self.assertEqual(self.site.zip_gets(), 0)

    def test_a_file_hosted_outside_itch_is_refused(self):
        self.site.external = True
        code, _, err = self.run_main("fetch", "ubc", "--accept-new")
        self.assertEqual(code, 1)
        self.assertIn("not hosted by itch.io", err)
        self.assertEqual(self.site.zip_gets(), 0)

    def test_fetch_all_handles_every_source(self):
        code, _, err = self.run_main("fetch", "all", "--accept-new")
        self.assertEqual(code, 0, err)
        self.assertNotEqual(self.recorded("ubc"), "")
        self.assertNotEqual(self.recorded("kenney_town"), "")

    def test_unknown_id_and_path_before_fetch_are_errors(self):
        code, _, err = self.run_main("fetch", "nope")
        self.assertEqual(code, 1)
        self.assertIn("nope", err)
        code, out, err = self.run_main("path", "kenney_town")
        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertIn("kenney_town", err)

    def test_a_download_that_is_not_a_zip_is_an_error_not_a_crash(self):
        self.site.zip_bytes = b"<html>not a zip</html>"
        code, _, err = self.run_main("fetch", "kenney_town", "--accept-new")
        self.assertEqual(code, 1, err)
        self.assertEqual(self.recorded("kenney_town"), "", "a broken download is never recorded")


class Urls(unittest.TestCase):
    def test_only_https_or_loopback_http_is_followed(self):
        fetch.require_web_url("https://example.com/x.zip")
        fetch.require_web_url("http://127.0.0.1:8000/x.zip")
        for bad in ["file:///etc/passwd", "ftp://example.com/x", "http://example.com/x.zip", "javascript:alert(1)"]:
            with self.subTest(url=bad), self.assertRaises(ValueError):
                fetch.require_web_url(bad)


if __name__ == "__main__":
    unittest.main()

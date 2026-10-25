#!/usr/bin/env python3
"""Downloads the asset packs listed in sources.json, checks them against recorded hashes, and
extracts them safely. Standard library only; run it as `python3 -I tools/assets/fetch.py ...`.

    fetch.py fetch <id|all> [--accept-new]   download, verify, extract
    fetch.py path <id>                       print the folder a pack is extracted into

A pack is downloaded to .cache/downloads/<id>.zip and extracted to .cache/extract/<id>/
(both git-ignored; Godot skips dot-folders). A verified zip that is already cached is not
downloaded again.

Exit status: 0 done, 1 failed (network, parsing, bad archive, unknown id), 2 the downloaded pack
does not match the sha256 recorded in sources.json. A pack with no recorded hash counts as a
mismatch. --accept-new records the new hash instead; use it for the first fetch, and again only
after deciding that a changed pack is one you trust.

Downloaded files are untrusted data: nothing here runs them, and safe_extract refuses any archive
member that would land outside its folder.
"""
import argparse
import hashlib
import html as htmllib
import http.client
import http.cookiejar
import json
import os
import re
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # the all-divine folder

USER_AGENT = "all-divine-asset-fetch/1.0"
EXIT_FAILED = 1
EXIT_MISMATCH = 2
ATTEMPTS = 3  # a signed itch.io link lives about a minute, so a retry starts the whole flow again
TIMEOUT = 120  # seconds, for each wait on the network
PROGRESS_EVERY = 64 * 1024 * 1024  # bytes between progress lines on a long download


class FetchError(Exception):
    """Something went wrong getting a pack that is not a hash mismatch."""


class HashMismatch(Exception):
    def __init__(self, path, expected, actual):
        self.path, self.expected, self.actual = path, expected, actual
        super().__init__(f"sha256 of {path} is {actual}, recorded {expected or '(nothing)'}")


# --- locations ---

def sources_path(root=ROOT):
    return Path(root) / "tools" / "assets" / "sources.json"


def downloads_dir(root=ROOT):
    return Path(root) / ".cache" / "downloads"


def extract_dir(root, source_id):
    return Path(root) / ".cache" / "extract" / source_id


# --- parsing (pure) ---

def parse_csrf(html):
    """The csrf_token value of the first <input> or <meta> tag named csrf_token."""
    for tag in re.findall(r"<[^<>]*\bcsrf_token\b[^<>]*>", html):
        if not re.search(r"""\bname\s*=\s*["']csrf_token["']""", tag):
            continue
        found = re.search(r"""\bvalue\s*=\s*(?:"([^"]*)"|'([^']*)')""", tag)
        if found:
            value = htmllib.unescape(found.group(1) if found.group(1) is not None else found.group(2))
            if value:
                return value
    raise ValueError("no csrf_token in the page")


def parse_upload_ids(html):
    """Every data-upload_id on a download page, once each, in page order."""
    ids = []
    for found in re.findall(r"""\bdata-upload_id\s*=\s*["'](\d+)["']""", html):
        if found not in ids:
            ids.append(found)
    return ids


def parse_kenney_zip(html):
    """The first .zip link on a Kenney asset page (the page writes it with single quotes)."""
    found = re.search(r"""\bhref\s*=\s*(?:"([^"]+\.zip)"|'([^']+\.zip)')""", html, re.IGNORECASE)
    if not found:
        raise ValueError("no .zip link in the page")
    return htmllib.unescape(found.group(1) if found.group(1) is not None else found.group(2))


# --- hashing ---

def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify(path, sha256, accept_new):
    """Returns the file's sha256. If it differs from `sha256` (or none is recorded), raises
    HashMismatch, unless accept_new is set, in which case the caller records the returned hash."""
    actual = sha256_file(path)
    if actual != (sha256 or "").strip().lower() and not accept_new:
        raise HashMismatch(path, sha256, actual)
    return actual


# --- extraction ---

def _member_path(name):
    """The member's name as a safe relative POSIX path, or ValueError."""
    if not name or "\x00" in name:
        raise ValueError(f"bad archive member name {name!r}")
    posix = name.replace("\\", "/")
    if posix.startswith("/") or re.match(r"^[A-Za-z]:", posix):
        raise ValueError(f"absolute path in archive: {name!r}")
    if ".." in posix.split("/"):
        raise ValueError(f"'..' in archive path: {name!r}")
    return posix


def safe_extract(zip_path, dest):
    """Extracts the zip into `dest` and returns the names of the files written. Every member
    is checked before anything is written; an absolute path or one containing '..' (with / or \\
    as the separator) raises ValueError and extracts nothing."""
    dest = Path(dest)
    with zipfile.ZipFile(zip_path) as z:
        plan = []
        for info in z.infolist():
            posix = _member_path(info.filename)
            plan.append((info, posix, dest / posix))
        dest.mkdir(parents=True, exist_ok=True)
        written = []
        for info, posix, target in plan:
            if info.is_dir() or posix.endswith("/"):
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with z.open(info) as src, open(target, "wb") as out:
                shutil.copyfileobj(src, out, 1 << 20)
            written.append(posix)
    return written


# --- network ---

def require_web_url(url):
    """https always; http only to this machine (the tests' local server). Anything else, such as
    file:// or ftp://, is refused so a reply from a web server cannot point us at local files."""
    parts = urllib.parse.urlsplit(url)
    if parts.scheme == "https" and parts.hostname:
        return
    if parts.scheme == "http" and parts.hostname in ("127.0.0.1", "localhost", "::1"):
        return
    raise ValueError(f"refusing to fetch {url!r}: only https links are followed")


class _CheckedRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        require_web_url(urllib.parse.urljoin(req.full_url, newurl))
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def make_opener(proxies=None):
    """A URL opener with a cookie jar (itch.io ties its csrf token to a cookie). `proxies` is
    None for the environment's HTTPS_PROXY, or a dict (the tests pass {})."""
    handlers = [urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()), _CheckedRedirects()]
    if proxies is not None:
        handlers.append(urllib.request.ProxyHandler(proxies))
    opener = urllib.request.build_opener(*handlers)
    opener.addheaders = [("User-Agent", USER_AGENT)]
    return opener


def http_get(opener, url):
    require_web_url(url)
    with opener.open(url, timeout=TIMEOUT) as reply:
        return reply.read().decode("utf-8", errors="replace")


def http_post_json(opener, url, form, referer):
    require_web_url(url)
    request = urllib.request.Request(
        url,
        data=urllib.parse.urlencode(form).encode(),
        headers={"X-Requested-With": "XMLHttpRequest", "Referer": referer},
    )
    with opener.open(request, timeout=TIMEOUT) as reply:
        return json.loads(reply.read().decode("utf-8"))


def itch_file_url(page, opener):
    """The signed link to the one file on an itch.io page. The flow: read the csrf token off the
    page; POST it to {page}/download_url for the download page; read the upload id there; POST the
    token to {page}/file/{id} for the link. (Packs bought with a download key add &key=..., which
    these free packs do not need.)"""
    page = page.rstrip("/")
    token = parse_csrf(http_get(opener, page))
    download_page_url = http_post_json(opener, page + "/download_url", {"csrf_token": token}, page).get("url")
    if not download_page_url:
        raise FetchError(f"{page}: itch.io gave no download page")
    download_page = http_get(opener, download_page_url)
    ids = parse_upload_ids(download_page)
    if len(ids) != 1:
        raise FetchError(f"{page}: expected exactly one file to download, the page lists {ids or 'none'}")
    token = parse_csrf(download_page)
    reply = http_post_json(opener, f"{page}/file/{ids[0]}?source=game_download", {"csrf_token": token}, download_page_url)
    if reply.get("external") or not reply.get("url"):
        raise FetchError(f"{page}: the file is not hosted by itch.io, or itch.io gave no link ({reply})")
    return reply["url"]


def kenney_file_url(page, opener):
    return urllib.parse.urljoin(page, parse_kenney_zip(http_get(opener, page)))


def download_file(opener, url, dest, label):
    """Streams `url` to `dest` through a .part file; a short read is an OSError."""
    require_web_url(url)
    part = dest.with_name(dest.name + ".part")
    part.parent.mkdir(parents=True, exist_ok=True)
    written = 0
    next_report = PROGRESS_EVERY
    try:
        with opener.open(url, timeout=TIMEOUT) as reply, open(part, "wb") as out:
            expected = reply.headers.get("Content-Length")
            while True:
                chunk = reply.read(1 << 20)
                if not chunk:
                    break
                out.write(chunk)
                written += len(chunk)
                if written >= next_report:
                    log(f"{label}: {written >> 20} MiB so far")
                    next_report += PROGRESS_EVERY
        if expected is not None and written != int(expected):
            raise OSError(f"download stopped after {written} of {expected} bytes")
        os.replace(part, dest)
    finally:
        part.unlink(missing_ok=True)
    return written


def _transient(error):
    """Worth another try: the network dropped, or the server had a bad moment."""
    if isinstance(error, urllib.error.HTTPError):
        return error.code >= 500 or error.code == 429
    return isinstance(error, (OSError, http.client.HTTPException))


def download_pack(source_id, source, dest, opener):
    """Downloads the pack's zip to `dest`, trying up to ATTEMPTS times. Raises FetchError if the
    result is not a zip."""
    for attempt in range(1, ATTEMPTS + 1):
        try:
            if source["kind"] == "itch":
                url = itch_file_url(source["page"], opener)
            else:
                url = kenney_file_url(source["page"], opener)
            log(f"{source_id}: downloading from {urllib.parse.urlsplit(url).netloc}")
            size = download_file(opener, url, dest, source_id)
            break
        except (OSError, http.client.HTTPException) as error:
            if attempt == ATTEMPTS or not _transient(error):
                raise FetchError(f"{source_id}: {error}") from error
            log(f"{source_id}: {error}; trying again ({attempt}/{ATTEMPTS - 1} retries used)")
            time.sleep(2 * attempt)
        except (ValueError, KeyError) as error:
            raise FetchError(f"{source_id}: {error}") from error
    if not zipfile.is_zipfile(dest):
        dest.unlink(missing_ok=True)
        raise FetchError(f"{source_id}: what was downloaded ({size} bytes) is not a zip file")


# --- sources.json ---

def load_sources(path):
    sources = json.loads(Path(path).read_text(encoding="utf-8"))
    for source_id, source in sources.items():
        if not re.fullmatch(r"[A-Za-z0-9_]+", source_id):
            raise FetchError(f"sources.json: bad pack id {source_id!r}")
        if source.get("kind") not in ("itch", "kenney") or not source.get("page"):
            raise FetchError(f"sources.json: {source_id} needs a kind of itch or kenney, and a page")
    return sources


def record_hash(path, source_id, sha256):
    """Sets sources.json's `sha256` for one pack, leaving everything else as it was."""
    path = Path(path)
    sources = json.loads(path.read_text(encoding="utf-8"))
    sources[source_id]["sha256"] = sha256
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(sources, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(tmp, path)


# --- fetching ---

def log(message):
    print(message, file=sys.stderr, flush=True)


def acquire(source_id, source, root, accept_new, opener):
    """Gets the pack's zip into .cache/downloads (or finds the verified one already there) and
    returns (zip_path, sha256). Raises HashMismatch, or FetchError."""
    zip_path = downloads_dir(root) / f"{source_id}.zip"
    recorded = (source.get("sha256") or "").strip().lower()
    if recorded and zip_path.is_file() and sha256_file(zip_path) == recorded:
        log(f"{source_id}: cached download matches its recorded hash")
    else:
        download_pack(source_id, source, zip_path, opener)
    return zip_path, verify(zip_path, recorded, accept_new)


def extract_pack(source_id, zip_path, sha256, root):
    """Extracts into .cache/extract/<id>/, replacing what was there, unless that folder already
    holds this very zip. The new files are built beside it and swapped in, so a refused or broken
    archive leaves the old extract alone."""
    target = extract_dir(root, source_id)
    marker = target.with_name(source_id + ".sha256")
    if target.is_dir() and marker.is_file() and marker.read_text().strip() == sha256:
        log(f"{source_id}: already extracted")
        return
    staging = target.with_name(source_id + ".tmp")
    shutil.rmtree(staging, ignore_errors=True)
    try:
        names = safe_extract(zip_path, staging)
    except (ValueError, zipfile.BadZipFile) as error:
        shutil.rmtree(staging, ignore_errors=True)
        raise FetchError(f"{source_id}: {error}") from error
    marker.unlink(missing_ok=True)
    shutil.rmtree(target, ignore_errors=True)
    os.replace(staging, target)
    marker.write_text(sha256 + "\n")
    log(f"{source_id}: extracted {len(names)} files to {target}")


def build_parser():
    class Parser(argparse.ArgumentParser):
        def error(self, message):  # argparse would exit 2, which here means "hash mismatch"
            self.print_usage(sys.stderr)
            self.exit(EXIT_FAILED, f"{self.prog}: error: {message}\n")

    parser = Parser(prog="fetch.py", description="Download, verify and extract the asset packs in sources.json.")
    commands = parser.add_subparsers(dest="command", required=True)
    fetch_cmd = commands.add_parser("fetch", help="download, verify and extract a pack")
    fetch_cmd.add_argument("id", help="a pack id from sources.json, or 'all'")
    fetch_cmd.add_argument("--accept-new", action="store_true", help="record the downloaded pack's hash instead of failing on a mismatch")
    path_cmd = commands.add_parser("path", help="print the folder a pack is extracted into")
    path_cmd.add_argument("id")
    return parser


def main(argv=None, root=ROOT, opener=None):
    args = build_parser().parse_args(argv)
    try:
        sources = load_sources(sources_path(root))
    except (OSError, ValueError, FetchError) as error:
        log(f"fetch.py: {error}")
        return EXIT_FAILED
    if args.id != "all" and args.id not in sources:
        log(f"fetch.py: no pack called '{args.id}'; sources.json has: {', '.join(sources)}")
        return EXIT_FAILED

    if args.command == "path":
        target = extract_dir(root, args.id)
        if args.id == "all" or not target.is_dir():
            log(f"fetch.py: {args.id} is not extracted yet; run: python3 -I tools/assets/fetch.py fetch {args.id}")
            return EXIT_FAILED
        print(target)
        return 0

    opener = opener or make_opener()
    mismatched = failed = False
    for source_id in (sources if args.id == "all" else [args.id]):
        source = sources[source_id]
        try:
            zip_path, actual = acquire(source_id, source, root, args.accept_new, opener)
            if actual != (source.get("sha256") or "").strip().lower():
                record_hash(sources_path(root), source_id, actual)
                log(f"{source_id}: recorded sha256 {actual}")
            extract_pack(source_id, zip_path, actual, root)
        except HashMismatch as error:
            mismatched = True
            log(f"{source_id}: the downloaded pack does not match sources.json\n"
                f"  recorded:   {error.expected or '(nothing yet)'}\n"
                f"  downloaded: {error.actual}\n"
                f"  If this is the pack you meant to get, rerun with --accept-new to record it.")
        except (FetchError, OSError, ValueError, http.client.HTTPException, zipfile.BadZipFile) as error:
            failed = True
            log(f"{source_id}: failed: {error}")
    return EXIT_MISMATCH if mismatched else EXIT_FAILED if failed else 0


if __name__ == "__main__":
    sys.exit(main())

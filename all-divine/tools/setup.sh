#!/usr/bin/env bash
# Installs the pinned toolchain for all-divine/. Safe to run again.
#   tools/setup.sh [--templates] [--bpy]
#     (default)    Godot into .tools/godot/, checked against SHA512-SUMS.txt
#     --templates  export templates into ~/.local/share/godot/export_templates/4.7.2.stable/
#     --bpy        tools/.venv (Python 3.13) with bpy==5.2.3
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VERSION="4.7.2"
TAG="${VERSION}-stable"
VERSION_STRING="4.7.2.stable.official.ed1daf0bf"
BASE_URL="https://github.com/godotengine/godot/releases/download/${TAG}"
BIN_NAME="Godot_v${TAG}_linux.x86_64"
BIN_ZIP="${BIN_NAME}.zip"
TEMPLATES_TPZ="Godot_v${TAG}_export_templates.tpz"
BPY_VERSION="5.2.3"
PYTHON_VERSION="3.13"

CACHE="$ROOT/.cache/godot"
GODOT_DIR="$ROOT/.tools/godot"
GODOT_BIN="$GODOT_DIR/$BIN_NAME"
TEMPLATES_DIR="${HOME}/.local/share/godot/export_templates/${VERSION}.stable"
VENV="$ROOT/tools/.venv"

want_templates=0
want_bpy=0
for arg in "$@"; do
	case "$arg" in
		--templates) want_templates=1 ;;
		--bpy) want_bpy=1 ;;
		*) echo "setup.sh: unknown argument '$arg' (use --templates and/or --bpy)" >&2; exit 2 ;;
	esac
done

die() { echo "setup.sh: $*" >&2; exit 1; }

# download <url> <dest>: writes to <dest>.part first so a broken download is never mistaken for a good one.
download() {
	echo "Downloading $1"
	curl -fsSL --retry 3 --retry-delay 2 -o "$2.part" "$1"
	mv "$2.part" "$2"
}

# verify <file> <name>: compares the file's SHA-512 with the line for <name> in SHA512-SUMS.txt.
# A file that does not match is deleted and the script exits 1.
verify() {
	local file="$1" name="$2" want got
	want="$(awk -v n="$name" '{ f = $2; sub(/^\*/, "", f); if (f == n) { print $1; exit } }' "$CACHE/SHA512-SUMS.txt")"
	[ -n "$want" ] || die "$name is not listed in SHA512-SUMS.txt"
	got="$(sha512sum "$file" | awk '{ print $1 }')"
	if [ "$got" != "$want" ]; then
		rm -f "$file"
		die "checksum mismatch for $name (wanted ${want:0:16}..., got ${got:0:16}...); deleted the download"
	fi
	echo "Checksum ok: $name"
}

# fetch_verified <name>: makes sure $CACHE/<name> exists and matches SHA512-SUMS.txt.
fetch_verified() {
	local name="$1"
	mkdir -p "$CACHE"
	download "$BASE_URL/SHA512-SUMS.txt" "$CACHE/SHA512-SUMS.txt"
	if [ ! -f "$CACHE/$name" ]; then
		download "$BASE_URL/$name" "$CACHE/$name"
	fi
	verify "$CACHE/$name" "$name"
}

installed_version() {
	[ -x "$GODOT_BIN" ] && "$GODOT_BIN" --version 2>/dev/null || true
}

install_godot() {
	if [ "$(installed_version)" = "$VERSION_STRING" ]; then
		echo "Godot already installed at $GODOT_BIN"
		return
	fi
	fetch_verified "$BIN_ZIP"
	rm -rf "$GODOT_DIR"
	mkdir -p "$GODOT_DIR"
	unzip -q -o "$CACHE/$BIN_ZIP" -d "$GODOT_DIR"
	chmod +x "$GODOT_BIN"
	[ "$(installed_version)" = "$VERSION_STRING" ] \
		|| die "installed Godot reports '$(installed_version)', expected '$VERSION_STRING'"
}

install_templates() {
	if [ "$(cat "$TEMPLATES_DIR/version.txt" 2>/dev/null || true)" = "${VERSION}.stable" ]; then
		echo "Export templates already installed in $TEMPLATES_DIR"
		return
	fi
	fetch_verified "$TEMPLATES_TPZ"
	local tmp
	tmp="$(mktemp -d "$CACHE/templates.XXXXXX")"
	unzip -q -o "$CACHE/$TEMPLATES_TPZ" -d "$tmp"
	[ -f "$tmp/templates/version.txt" ] || { rm -rf "$tmp"; die "$TEMPLATES_TPZ has no templates/version.txt"; }
	rm -rf "$TEMPLATES_DIR"
	mkdir -p "$(dirname "$TEMPLATES_DIR")"
	mv "$tmp/templates" "$TEMPLATES_DIR"
	rm -rf "$tmp"
	echo "Export templates installed in $TEMPLATES_DIR"
}

install_bpy() {
	command -v uv >/dev/null 2>&1 || die "uv is required for --bpy (https://docs.astral.sh/uv/)"
	if [ ! -x "$VENV/bin/python" ]; then
		uv venv --python "$PYTHON_VERSION" "$VENV"
	fi
	uv pip install --python "$VENV/bin/python" "bpy==${BPY_VERSION}"
	echo "bpy ${BPY_VERSION} ready in $VENV"
}

install_godot
if [ "$want_templates" = 1 ]; then install_templates; fi
if [ "$want_bpy" = 1 ]; then install_bpy; fi
echo "Godot $(installed_version) ready"

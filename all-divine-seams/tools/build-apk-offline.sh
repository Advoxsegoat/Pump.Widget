#!/usr/bin/env bash
# Builds the signed APK without the Android SDK, using only Maven Central artifacts:
#   aapt2 + framework resources (Apktool), Android 15 classes (Robolectric android-all),
#   dx (AOSP, repackaged) and apksig (Google).
# Meant for machines that cannot reach dl.google.com (some cloud sandboxes). Anywhere else,
# use Gradle: cd all-divine-seams/android && ./gradlew assembleRelease
#
# Usage: all-divine-seams/tools/build-apk-offline.sh [out.apk]
# Needs: JDK 17+, curl, unzip, zip. Tools are cached in $OFFLINE_TOOLS (~/.cache/apk-offline-tools).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
app=$here/../android/app
web=$here/../web
out=${1:-$app/build/offline/between-the-rooms.apk}
cache=${OFFLINE_TOOLS:-$HOME/.cache/apk-offline-tools}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# app/build.gradle owns these; read them from it so the two builds cannot drift
gradle_value() { sed -n "s/^ *$1 '\{0,1\}\([^' ]*\)'\{0,1\} *$/\1/p" "$app/build.gradle" | head -1; }
pkg=$(gradle_value applicationId)
min_sdk=$(gradle_value minSdk)
target_sdk=$(gradle_value targetSdk)
version_code=${VERSION_CODE:-1}
version_name=${VERSION_NAME:-1.0.0}

central=https://repo.maven.apache.org/maven2
fetch() { # path under Maven Central -> cached file, checked against Central's SHA-1
  local f
  f=$cache/$(basename "$1")
  if [ ! -f "$f" ]; then
    mkdir -p "$cache"
    curl -sSfL --retry 6 --retry-delay 20 --retry-all-errors -o "$f.part" "$central/$1"
    if [ "$(sha1sum < "$f.part" | cut -c1-40)" != "$(curl -sSfL --retry 6 --retry-all-errors "$central/$1.sha1" | cut -c1-40)" ]; then
      echo "checksum mismatch: $1" >&2
      exit 1
    fi
    mv "$f.part" "$f"
  fi
  echo "$f"
}
apktool=$(fetch org/apktool/apktool-lib/3.0.3/apktool-lib-3.0.3.jar)
android_all=$(fetch org/robolectric/android-all/15-robolectric-12650502/android-all-15-robolectric-12650502.jar)
dx=$(fetch com/jakewharton/android/repackaged/dalvik-dx/16.0.1/dalvik-dx-16.0.1.jar)
apksig=$(fetch com/android/tools/build/apksig/2.3.0/apksig-2.3.0.jar)

unzip -q -o "$apktool" prebuilt/linux/aapt2 prebuilt/android-framework.jar -d "$work"
aapt2=$work/prebuilt/linux/aapt2
chmod +x "$aapt2"

echo "== resources ($pkg, minSdk $min_sdk, targetSdk $target_sdk, version $version_name/$version_code)"
# Gradle's manifest merge adds the package attribute; do the same
sed "s|<manifest |<manifest package=\"$pkg\" |" "$app/src/main/AndroidManifest.xml" > "$work/AndroidManifest.xml"
mkdir -p "$work/assets"
cp -R "$app/src/main/assets/." "$web/." "$work/assets/"
"$aapt2" compile --dir "$app/src/main/res" -o "$work/res.zip"
"$aapt2" link -o "$work/app.apk" -I "$work/prebuilt/android-framework.jar" \
  --manifest "$work/AndroidManifest.xml" -A "$work/assets" \
  --min-sdk-version "$min_sdk" --target-sdk-version "$target_sdk" \
  --version-code "$version_code" --version-name "$version_name" \
  "$work/res.zip"

echo "== code"
mkdir -p "$work/classes"
# Java 8 bytecode, which dx reads
find "$app/src/main/java" -name '*.java' > "$work/sources"
javac -Xlint:-options -nowarn --release 8 -cp "$android_all" -d "$work/classes" @"$work/sources"
java -cp "$dx" com.android.dx.command.Main --dex --min-sdk-version="$min_sdk" \
  --output="$work/classes.dex" "$work/classes"
(cd "$work" && zip -q app.apk classes.dex)

echo "== sign"
mkdir -p "$(dirname "$out")"
# this 2017 apksig touches a JDK-internal class even when only signing v2
java --add-exports java.base/sun.security.x509=ALL-UNNAMED \
  -cp "$apksig" "$here/SignApk.java" "$work/app.apk" "$out" \
  "$app/sideload.keystore" android sideload "$min_sdk"

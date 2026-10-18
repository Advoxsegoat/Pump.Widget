# All-Divine Tactics for Android

The web game, *The All-Divine: Tactics of the Open Hand*, packaged as a native Android app.
It runs fully offline and asks for no permissions.

| Path | What it is |
|---|---|
| [`web/index.html`](web/index.html) | The game, exactly as exported from its artifact. Replace this file to update the app. |
| [`android/`](android/) | The Android app: a full-screen WebView around the game, plus [`android-shell.js`](android/app/src/main/assets/android-shell.js) for the touch layout, clipboard and haptics. |
| [`tools/render-icons.mjs`](tools/render-icons.mjs) | Redraws the launcher icon from the game's own pixel art (Abarax, Rose Divine). |
| [`tools/build-apk-offline.sh`](tools/build-apk-offline.sh) | Builds the APK on a machine without the Android SDK. |

## Install it on a phone

1. Get the `.apk`: from a [GitHub Release](https://github.com/Advoxsegoat/Pump.Widget/releases), or
   from the **Artifacts** box of the latest
   [*All-Divine Tactics APK* run](https://github.com/Advoxsegoat/Pump.Widget/actions/workflows/all-divine-tactics-apk.yml)
   (that one is a zip; open it first).
2. Open the file on the phone. Android asks to allow installs from your browser or file manager: allow it.
3. Play Protect may warn that the developer is unknown. That is expected for an app installed from
   outside the Play Store. Choose *Install anyway*.

Needs Android 7.0 or newer.

## Playing on Android

- **Touch:** the on-screen pad. Portrait puts the small buttons in their own row; landscape puts
  the D-pad and A/B either side of the screen like a handheld.
- **Back gesture or button:** the game's **B**. On the title screen it closes the app.
- **Controllers** (Bluetooth or USB): D-pad or stick to move, A confirm, B back, X info,
  Y danger zone, L1/R1 cycle units, Start menu, R2 fast-forward.
- **Saves** live on the phone, inside the app. Uninstalling the app deletes them, so use
  *Save → Show Save Code* before uninstalling (the code goes to the clipboard), and
  *Import Save Code* on the title screen to bring a game back.

## Update the game

Export the newest version of the game artifact, replace `web/index.html` with it, and push.
CI builds a new APK. Each build has a higher version code and the same signing key, so it
installs over the old one and keeps the saves.

## Build it yourself

- **CI:** [`.github/workflows/all-divine-tactics-apk.yml`](../.github/workflows/all-divine-tactics-apk.yml)
  builds on every push that touches `all-divine-tactics/`. To publish a GitHub Release, push a tag:
  `git tag all-divine-tactics-v1.0.0 && git push origin all-divine-tactics-v1.0.0`.
- **With the Android SDK** (Android Studio, JDK 17):
  `cd all-divine-tactics/android && ./gradlew assembleRelease`, output in `app/build/outputs/apk/release/`.
- **Without the SDK** (e.g. a sandbox that cannot reach `dl.google.com`):
  `all-divine-tactics/tools/build-apk-offline.sh` builds the same app from Maven Central tools only.

## Signing, and the road to the Play Store

Builds are signed with [`android/app/sideload.keystore`](android/app/sideload.keystore). It is
committed on purpose, so that every build can update the last one, but anyone can read it. That
is fine for sideloading and wrong for a store listing.

For Google Play:

1. Settle the package name first. It is `com.advoxsegoat.alldivinetactics` (`applicationId` in
   [`android/app/build.gradle`](android/app/build.gradle)), and it can never change after the first upload.
2. Make a private upload key and keep it somewhere safe, outside the repo:
   `keytool -genkeypair -keystore upload.keystore -alias upload -keyalg RSA -keysize 2048 -validity 10000`
3. Add four repository secrets (*Settings → Secrets and variables → Actions*):
   `ANDROID_KEYSTORE_BASE64` (output of `base64 -w0 upload.keystore`), `ANDROID_KEYSTORE_PASSWORD`,
   `ANDROID_KEY_ALIAS` (`upload`), `ANDROID_KEY_PASSWORD`.
4. CI then signs with that key and also builds the `.aab` bundle that Play asks for.

A phone that has the sideload build has to uninstall it before installing a build signed with
the new key (Android rejects updates signed with a different key). Export a save code first.

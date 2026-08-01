# iOS test build (free Apple ID, no Developer Program)

EasyTrack ships as a signed Android APK. This document covers the other thing
the repo can produce: an **unsigned iOS build** that runs on a personal iPhone,
for looking at the app on real hardware before deciding whether to pay for the
Apple Developer Program ($99/year).

Two facts shape the whole procedure:

- **iOS can only be compiled on macOS.** Development here happens on Windows, so
  the build runs on a GitHub-hosted macOS runner. That is free for this repo —
  the 10× macOS billing multiplier only applies to private repositories.
- **A free Apple ID can sign apps for devices you own** (a "Personal Team"). No
  Developer Program, no cost. In exchange the signature **expires after 7 days**,
  at most 3 sideloaded apps may be installed at once, and 10 app IDs may be
  created per 7 days.

This path is for personal testing only. TestFlight, outside testers and the App
Store all require the paid program and real distribution signing, none of which
exist in this repo.

## 1. Build the IPA

`.github/workflows/ios-testbuild.yml`, manual trigger only:

```sh
gh workflow run ios-testbuild.yml
gh run watch
```

It builds `flutter build ios --release --no-codesign`, wraps
`build/ios/iphoneos/Runner.app` in a `Payload/` folder, zips that to
`easytrack-unsigned.ipa` and uploads it as a run artifact. Download and unzip
the artifact to get the `.ipa`.

`flutter build ipa` is not used: its export step insists on a signing identity,
which is exactly what we don't have. An `.ipa` is only a zip of `Payload/*.app`,
so the workflow builds it directly.

## 2. Install on the iPhone from Windows

Requires [Sideloadly](https://sideloadly.io) plus Apple's device drivers on
Windows (Apple Devices from the Microsoft Store, or the classic iTunes
installer — Sideloadly checks for these and links them if missing).

1. Connect the iPhone by USB and trust the computer.
2. Open Sideloadly, drop in `easytrack-unsigned.ipa`, enter your Apple ID, and
   start. The Apple ID is used to fetch a free development certificate; if the
   account has 2FA you will be asked for an app-specific password.
3. Sideloadly rewrites the bundle id to something unique for the Personal Team.
   The id in the repo (`is.dnn.easytrack`, matching the Android `applicationId`)
   is what a future paid build would use.
4. On the phone: **Settings → General → VPN & Device Management** → trust the
   developer profile that now appears under your Apple ID.
5. On iOS 16 and later, also enable **Settings → Privacy & Security → Developer
   Mode**. The phone reboots. Without it a free-provisioned app refuses to launch.

After 7 days the app stops opening. Re-run Sideloadly with the same IPA to
refresh it; the app's data survives.

## 3. What to check on the device

The build exercises a few things that only exist on a real phone:

- App launches: splash animation cross-fades into the home shell.
- Search a food and log it — proves the bundled `assets/data/bls.sqlite` opens
  and the SQLite native asset loaded (see the note below).
- Open the barcode scanner — iOS shows the camera prompt carrying
  `NSCameraUsageDescription` from `ios/Runner/Info.plist`, then a live preview.
- **Einstellungen → Produktdaten** → download the `de` product pack — proves
  network access and writes into the app's documents directory.
- **Profil → Datensicherung** → export — the iOS share sheet appears with the zip.

## Known rough edges

**`libsqlite3.dylib`.** `package:sqlite3` compiles SQLite from source through a
native-assets build hook instead of shipping a CocoaPod, so the resulting dylib
is bundled into `Runner.app/Frameworks/` unsigned and must be re-signed along
with everything else. Sideloadly signs nested code by default. If the app dies
instantly at launch, check the workflow's "List bundled frameworks" step first —
it prints that directory so a missing dylib shows up in CI rather than as a
mystery crash on the phone.

**The update banner.** Einstellungen offers an update hint that checks GitHub
Releases and points at an APK. On an iOS build that is meaningless; it is
cosmetic and left alone.

**The `ios/` project is not part of a release.** `release.yml` builds only the
Android APK and AAB. Shipping to the App Store additionally needs the Developer
Program, an App ID registration, certificates and provisioning profiles in CI,
a privacy nutrition label and per-device screenshots.

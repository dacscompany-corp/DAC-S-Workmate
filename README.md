# DAC'S WorkMate

Worker app for Attendance, Material Requests and Tools. By Dacs Building Design Services.
Flutter/Dart, Android only. Backend: the shared DAC's Supabase project (`hqbgduyonlbbsvjuapre`).
Design and rules: `Dacs Web/docs/superpowers/specs/2026-09-29-unified-worker-app-design.md`.

## Build

- JDK 21: `flutter config --jdk-dir "C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot"`
- Tests: `flutter test`
- Debug APK (`com.dacs.workmate.debug`, installs beside the real app): `flutter build apk --debug`
- Release APK: `flutter build apk --release` — ONE universal APK. Never split it per ABI: that rewrites
  versionCode per ABI and the server then refuses those phones.

## Attendance (Stage 0C)

Time In and Time Out live in WorkMate: the four-step flow (project, photo, check, describe), Home and History,
with the same rules and words as DACS Attendance.

- Camera and location permission are asked for together at the photo step. A refused location refuses the
  Time In with an Open Settings button; Location switched off refuses it with a button to the phone's
  Location switch.
- Photos are taken in the app only (no gallery), front camera by default, filed mirrored as previewed, with
  the project, date and time burned in.
- A Time In made with no signal says "Not sent yet" and sends itself when signal returns, even after the app
  is closed.

## Release rules

- Bump `version:` in `pubspec.yaml` on EVERY release. The number after `+` is the versionCode:
  it must be 1000 or higher and higher than the last published WorkMate build (server rule 0082).
- The release APK must stay under 50 MB (the `app-releases` bucket limit). It carries only the ARM
  engines (armeabi-v7a, arm64-v8a): `build.gradle.kts` excludes `lib/x86_64` (emulator-only, ~18 MB).
  0.1.0 was 31 MB. Because of this, the app does not run on x86_64 emulators; test on a real phone.
- Publish from Dacs Web → App Updates. It recognises `com.dacs.workmate` and files it under the
  WorkMate stream. Publishing makes the update REQUIRED for every WorkMate phone.

## Upload key

`android/keystore.properties` (gitignored) points at
`C:\Users\John Aerol Tapales\keystores\dacs-workmate-upload.jks`:

```
storeFile=C:/Users/John Aerol Tapales/keystores/dacs-workmate-upload.jks
storePassword=...
keyAlias=workmate-upload
keyPassword=...
```

Losing this key means no update can ever be installed over WorkMate. Back it up with the Attendance key.
A release build refuses to run without it; debug builds and tests do not need it.

# Build the Android prototype

Toolchain: Flutter stable 3.47.7 (Dart 3.13.5), JDK 21, Android SDK platform 36 and build tools 36.0.0. Pin the Flutter version when reproducing results; preserve `pubspec.lock`.

From a normal shell in the repository:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`. Install with `adb install -r` after enabling USB debugging and accepting the phone's trust prompt, or transfer the APK and open it on the phone. A physical sign is not needed.

The native bridge supplies Android `SystemClock.elapsedRealtime()` with `BOOT_COUNT`, uses `AtomicFile` in application-private storage, and accesses selected documents through the system picker. The app requires no account or Internet connection. Debug builds may carry Flutter's tooling Internet permission; no application transport is implemented.

On this Windows workspace, the reusable Android environment is at `C:\Users\x1\Documents\Codex\android-toolchain\Activate.ps1`. The Flutter SDK installation and build verification details are recorded in the delivered verification report. Machine-specific SDK locations belong in ignored `android/local.properties`, not source control.

If a fresh checkout lacks the Gradle wrapper binary, run `flutter create --platforms android --org org.kosenuel .` using the pinned Flutter version, then inspect its changes before building. The committed native bridge and app identity must remain intact.

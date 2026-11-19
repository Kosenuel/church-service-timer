# local_notifier (Windows, patched)

A copy of [local_notifier 0.1.6](https://pub.dev/packages/local_notifier)
(MIT, see `LICENSE`), kept here for one fix: on Windows the published
package ignores `LocalNotification.silent`, so every notification played the
Windows notification sound. Church Service Timer's warnings must make no
sound on a PC, which is often plugged into the sound system.

The change is in `windows/local_notifier_plugin.cpp`: a silent notification
sets the toast's audio option to silent. Only the Dart code and the Windows
plugin are kept; the app does not build for Linux or macOS.

If a later release of the package honours `silent` on Windows, delete this
folder and point `pubspec.yaml` back at pub.dev.

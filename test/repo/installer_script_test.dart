import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// The Windows installer cannot be compiled on a Linux machine, so these
// checks read the Inno Setup script as text. They catch a missing or
// wrongly sized picture, unbalanced script code and a changed silent-install
// contract before a Windows build is needed. The first real proof is still a
// build on GitHub (see windows/installer/README.md).
void main() {
  final dir = Directory('windows/installer');
  final iss = File('${dir.path}/church-service-timer.iss').readAsStringSync();

  (int, int) pngSize(String relative) {
    final file = File('${dir.path}/${relative.replaceAll(r'\', '/')}');
    expect(file.existsSync(), isTrue, reason: '$relative is missing');
    final bytes = file.readAsBytesSync();
    expect(String.fromCharCodes(bytes.sublist(1, 4)), 'PNG',
        reason: '$relative is not a PNG');
    final data = ByteData.sublistView(bytes);
    return (data.getUint32(16), data.getUint32(20));
  }

  String setupValue(String key) {
    final m = RegExp('^$key=(.*)\$', multiLine: true).firstMatch(iss);
    expect(m, isNotNull, reason: '$key is not set');
    return m!.group(1)!.trim();
  }

  test('The wizard pictures exist and have the sizes Inno Setup expects', () {
    final big = setupValue('WizardImageFile').split(',');
    expect(big.length, 4);
    for (final f in big) {
      final (w, h) = pngSize(f);
      // The picture area is 164 x 314 in proportion.
      expect((h - w * 314 / 164).abs(), lessThan(1.5), reason: f);
    }
    final widths = big.map((f) => pngSize(f).$1).toList();
    expect(widths, [...widths]..sort(), reason: 'smallest first');
    for (final f in setupValue('WizardSmallImageFile').split(',')) {
      final (w, h) = pngSize(f);
      expect(w, h, reason: '$f must be square');
    }
  });

  test('Every picture the script and its code use exists', () {
    for (final m in RegExp(r'Source: "(art\\[^"]+)"').allMatches(iss)) {
      pngSize(m.group(1)!);
    }
    for (var i = 1; i <= 6; i++) {
      final (w, h) = pngSize('art\\scene-$i.png');
      expect((w, h), (1000, 333), reason: 'scene-$i');
      expect(iss, contains('art\\scene-$i.png'));
    }
    // The finished-page pictures the code picks from match the welcome ones.
    final big = setupValue('WizardImageFile').split(',');
    for (final f in big) {
      final ready = f.replaceFirst('welcome-', 'ready-');
      expect(pngSize(ready), pngSize(f));
      expect(iss, contains(ready));
    }
    for (final s in ['220', '331', '441', '551']) {
      expect(iss, contains("Size := '$s'"));
    }
    expect(File('${dir.path}/${setupValue('SetupIconFile').replaceAll(r'\', '/')}').existsSync(),
        isTrue);
  });

  test('The Code section is balanced and only builds with the new look', () {
    final start = iss.indexOf('[Code]');
    expect(start, greaterThan(0));
    // The section must sit inside #ifdef Cinematic ... #endif.
    expect(iss.lastIndexOf('#ifdef Cinematic', start), greaterThan(-1));
    expect(iss.substring(start), contains('#endif'));
    var code = iss.substring(start);
    code = code.replaceAll(RegExp(r'\{[^}]*\}', dotAll: true), ' ');
    code = code.replaceAll(RegExp(r"'[^']*'"), "''");
    final words = RegExp(r'\b(begin|case|try|end)\b', caseSensitive: false)
        .allMatches(code)
        .map((m) => m.group(1)!.toLowerCase())
        .toList();
    var depth = 0;
    for (final w in words) {
      depth += w == 'end' ? -1 : 1;
      expect(depth, greaterThanOrEqualTo(0));
    }
    expect(depth, 0);
    // Wizard-only work stays out of silent installs, and each event the
    // script relies on is spelled as Inno Setup expects.
    expect(code, contains('if WizardSilent then'));
    expect(code, contains('procedure InitializeWizard;'));
    expect(code,
        contains('procedure CurInstallProgressChanged(CurProgress, MaxProgress: Integer);'));
  });

  test('Install location, upgrade and silent-install behaviour are unchanged',
      () {
    expect(iss, contains('AppId={{6C1E0A4B-93D7-4F5E-8B2A-5D0F7C3E91A4}'));
    expect(setupValue('DefaultDirName'), r'{autopf}\{#AppName}');
    expect(setupValue('PrivilegesRequired'), 'lowest');
    expect(setupValue('CloseApplications'), 'yes');
    expect(iss, contains('Flags: nowait postinstall skipifsilent'));
    // The in-app updater starts the installer with no arguments, so every
    // page shows; nothing here may depend on a command-line switch.
    final updater = File('lib/windows/windows_updates.dart').readAsStringSync();
    expect(updater, contains('Process.start(path, const []'));
    // Without the new look the script falls back to the plain wizard.
    expect(iss, contains('#if VER >= 0x06060000'));
    expect(iss, contains('WizardStyle=modern\n#endif'));
  });
}

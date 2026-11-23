import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:church_service_timer/app/platform.dart';
import 'package:church_service_timer/app/update_checker.dart';
import 'package:church_service_timer/app/update_installer.dart';
import 'package:church_service_timer/display/tinos_rasterizer.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/hardware/w2/w2_transport.dart';
import 'package:church_service_timer/windows/atomic_store.dart';
import 'package:church_service_timer/windows/desktop_clock.dart';
import 'package:church_service_timer/windows/desktop_files.dart';
import 'package:church_service_timer/windows/desktop_images.dart';
import 'package:church_service_timer/windows/desktop_network.dart';
import 'package:church_service_timer/windows/desktop_warnings.dart';
import 'package:church_service_timer/windows/mini_window.dart';
import 'package:church_service_timer/windows/secret_vault.dart';
import 'package:church_service_timer/windows/stage_output.dart';
import 'package:church_service_timer/windows/tray_countdown.dart';
import 'package:flutter/services.dart';

/// The handful of things only the operating system can do. The real one
/// calls Windows (windows_system.dart); tests use a fake.
abstract class DesktopSystem {
  /// Opens a web, `mailto:` or `ms-settings:` link with its Windows
  /// handler; false if nothing could open it.
  bool open(String target);

  /// Stops the PC sleeping ([system]) and the screen turning off
  /// ([display]) until called again.
  void keepAwake({required bool system, required bool display});

  /// Battery level and whether on mains; empty without a battery.
  Json power();

  /// Draws attention to the window without sound: the taskbar button
  /// flashes until the window is brought forward.
  void flash();

  /// Shows a Windows notification and takes it down again after
  /// [clearSeconds] (0 leaves it until dismissed). It is silent unless
  /// [sound] is on. Clicking it calls [onClick].
  void notify(
    String title,
    String body, {
    int clearSeconds = 30,
    bool sound = false,
    void Function()? onClick,
  });

  /// Brings the window to the front.
  void raise();

  /// Shows the icon in the notification area with [tip] as its tooltip
  /// (adding it, or changing only its text), or removes the icon when
  /// [tip] is null. Clicking the icon brings the window forward. False
  /// when Windows refused.
  bool tray(String? tip);

  String description();
}

class _SignPrefs implements W2Preferences {
  final JsonPrefs store;
  _SignPrefs(this.store);
  @override
  Future<Json> read() async =>
      Map<String, dynamic>.from(await store.get('w2') as Map? ?? {});
  @override
  Future<void> write(Json changes) async {
    final next = await read();
    for (final entry in changes.entries) {
      if (entry.value == null) {
        next.remove(entry.key);
      } else {
        next[entry.key] = entry.value;
      }
    }
    await store.set('w2', next);
  }
}

/// Church Service Timer on a Windows PC.
///
/// Written in Dart so that everything except the calls in [DesktopSystem]
/// runs, and is tested, on any machine. Each method does what its Android
/// counterpart in MainActivity.kt does, or says honestly that Windows has
/// no equivalent.
class WindowsPort extends DevicePort with LocalNetworkPairing {
  final Directory dataDir;
  final DesktopClock _clock;
  final FileDialogs dialogs;
  final DesktopSystem system;
  final W2Transport sign;
  final TinosRasterizer _tinos;
  @override
  final StageOutputHost? stageOutput;
  @override
  final MiniWindow? miniWindow;
  @override
  final FullScreenWindow? fullScreenWindow;

  /// The download, temporary file and installer start for Check for
  /// updates, and how the app ends once the installer runs. Null in
  /// tests that do not need them.
  final UpdateFiles? updateFiles;
  final void Function() exitApp;
  late final AtomicTextFile _state = AtomicTextFile.json(
    File(_path('service-state.json')),
  );
  late final JsonPrefs _prefs = JsonPrefs(File(_path('settings.json')));
  final SecretVault _vault, _pairingVault;
  late final DesktopWarnings _warnings = DesktopWarnings(
    monoMs: _clock.monotonicMs,
    deliver: _warn,
  );
  int _clearSeconds = 30;

  /// Whether a warning's notification plays the Windows notification
  /// sound. Off unless the operator turns it on: a PC is often plugged
  /// into the sound system. Kept on this computer, not in backups.
  bool _sound = false;
  bool _soundLoaded = false;
  Future<void> _loadSound() async {
    if (_soundLoaded) return;
    _sound = await _prefs.get('warningSound') == true;
    _soundLoaded = true;
  }

  @override
  Future<void> setWarningSound(bool on) async {
    await _prefs.set('warningSound', on);
    _sound = on;
    _soundLoaded = true;
  }

  /// The countdown in the notification area, beside the Windows clock,
  /// while a service or quick timer runs. On unless the operator turns it
  /// off. Kept on this computer, not in backups.
  late final TrayCountdown _tray = TrayCountdown(system.tray);
  bool _trayLoaded = false;
  Future<void> _loadTray() async {
    if (_trayLoaded) return;
    final on = await _prefs.get('trayCountdown') != false;
    if (_trayLoaded) return;
    _trayLoaded = true;
    _tray.enabled = on;
  }

  @override
  Future<void> setTrayCountdown(bool on) async {
    await _prefs.set('trayCountdown', on);
    _trayLoaded = true;
    _tray.enabled = on;
  }

  @override
  Future<void> showTrayCountdown(String? text) async {
    await _loadTray();
    _tray.show(text);
  }

  @override
  Future<void> windowClosing() async => _tray.close();
  @override
  Future<Json> secondScreenSettings() async {
    final saved = await _prefs.get('secondScreen');
    return saved is Map ? Map<String, dynamic>.from(saved) : {};
  }

  @override
  Future<void> saveSecondScreenSettings(Json settings) =>
      _prefs.set('secondScreen', settings);

  /// A warning reaches the operator two ways: a Windows notification, for
  /// when another window is in front, and the flashing taskbar button,
  /// which still shows when Windows is holding notifications back (it
  /// does that by itself while a screen is being duplicated or presented).
  void _warn(String title, String body) {
    system.flash();
    system.notify(
      title,
      body,
      clearSeconds: _clearSeconds,
      sound: _sound,
      onClick: _openFromNotification,
    );
  }

  Future<void> Function(String action)? _notificationHandler;
  @override
  void setNotificationActionHandler(
    Future<void> Function(String action)? handler,
  ) => _notificationHandler = handler;

  /// Clicking a warning's notification brings the window forward, restored
  /// if it was minimised, and shows Live.
  void _openFromNotification() {
    system.raise();
    unawaited(_notificationHandler?.call('open'));
  }

  WindowsPort._(
    this.dataDir,
    this._clock,
    this.dialogs,
    this.system,
    this.sign,
    this._tinos,
    this._vault,
    this._pairingVault,
    this.stageOutput,
    this.miniWindow,
    this.fullScreenWindow,
    this.updateFiles,
    this.exitApp,
  );

  factory WindowsPort({
    required Directory dataDir,
    required int Function() monotonicMs,
    required SecretProtector protector,
    required FileDialogs dialogs,
    required DesktopSystem system,
    required Future<Uint8List> Function(String style) loadTinosFace,
    int Function()? wallMs,
    W2Transport? sign,
    StageOutputLauncher? stageLauncher,
    MiniWindow? miniWindow,
    FullScreenWindow? fullScreenWindow,
    UpdateFiles? updateFiles,
    void Function()? exitApp,
  }) {
    String path(String name) => '${dataDir.path}${Platform.pathSeparator}$name';
    final prefs = JsonPrefs(File(path('sign.json')));
    return WindowsPort._(
      dataDir,
      DesktopClock(
        monotonicMs: monotonicMs,
        wallMs: wallMs,
        boot: BootTracker(File(path('boot-marker.json'))),
      ),
      dialogs,
      system,
      sign ?? W2Transport(prefs: _SignPrefs(prefs)),
      TinosRasterizer(loadTinosFace),
      SecretVault(JsonPrefs(File(path('display-vault.json'))), protector),
      SecretVault(
        JsonPrefs(File(path('pairing-vault.json'))),
        protector,
        maxLength: 65536,
      ),
      stageLauncher == null ? null : StageOutputHost(stageLauncher),
      miniWindow,
      fullScreenWindow,
      updateFiles,
      exitApp ?? () => exit(0),
    );
  }

  String _path(String name) => '${dataDir.path}${Platform.pathSeparator}$name';

  @override
  bool get isDesktop => true;

  // ---- Clock and saved state ----------------------------------------------

  @override
  Future<Stamp> clock() async => _clock.read();
  @override
  Future<String?> load() => _state.read();
  @override
  Future<void> save(String state) => _state.write(state);

  // ---- Files --------------------------------------------------------------

  @override
  Future<Map<String, dynamic>?> pickFile() async {
    final path = await dialogs.open(
      label: 'Programs and backups (CSV, JSON)',
      extensions: const ['csv', 'json'],
    );
    return path == null ? null : readImportFile(path, backupLimitBytes);
  }

  @override
  Future<void> exportFile(String filename, String content) async {
    final json = filename.toLowerCase().endsWith('.json');
    final extension = json ? 'json' : 'csv';
    var path = await dialogs.save(
      suggestedName: safeFileName(filename),
      label: json ? 'JSON file' : 'CSV file',
      extensions: [extension],
    );
    if (path == null) return;
    if (!fileName(path).contains('.')) path = '$path.$extension';
    await writeWhole(path, Uint8List.fromList(utf8.encode(content)));
  }

  /// On a PC "share" means choosing where to save: one file gets a Save
  /// window, several go into a folder the person picks, never replacing a
  /// file that is already there.
  @override
  Future<bool> shareFiles(List<SharedFile> files, {String? subject}) async {
    if (files.isEmpty) return false;
    if (files.length == 1) {
      final file = files.single;
      final dot = file.name.lastIndexOf('.');
      final extension = dot < 0 ? '' : file.name.substring(dot + 1);
      var path = await dialogs.save(
        suggestedName: safeFileName(file.name),
        label: extension.isEmpty ? 'File' : '${extension.toUpperCase()} file',
        extensions: [if (extension.isNotEmpty) extension],
      );
      if (path == null) return false;
      if (extension.isNotEmpty && !fileName(path).contains('.'))
        path = '$path.$extension';
      await writeWhole(path, file.bytes);
      return true;
    }
    final folder = await dialogs.folder();
    if (folder == null) return false;
    for (final file in files) {
      await writeWhole(await freePath(folder, file.name), file.bytes);
    }
    return true;
  }

  final _incoming = <String>[];
  Future<void> Function()? _incomingHandler;

  /// A program file handed to the app: on the command line when Windows
  /// opens a `.json` or `.csv` with it, or passed on by a second copy of
  /// the app that was started the same way.
  @override
  void offerIncomingFile(String path) {
    _incoming.add(path);
    system.raise();
    unawaited(_incomingHandler?.call());
  }

  void Function(List<String> paths)? _dropHandler;

  @override
  void setFileDropHandler(void Function(List<String> paths)? handler) =>
      _dropHandler = handler;

  /// Files dropped on the window. A folder is marked with a closing
  /// separator, so it is never taken for a program file.
  void filesDropped(List<String> paths) => _dropHandler?.call([
    for (final path in paths)
      FileSystemEntity.isDirectorySync(path)
          ? '$path${Platform.pathSeparator}'
          : path,
  ]);

  @override
  void setIncomingFileHandler(Future<void> Function()? handler) =>
      _incomingHandler = handler;

  @override
  Future<Map<String, dynamic>?> takeIncomingFile() async {
    if (_incoming.isEmpty) return null;
    final path = _incoming.last;
    _incoming.clear();
    return readImportFile(path, backupLimitBytes);
  }

  Future<Uint8List?> _pickImage() async {
    final path = await dialogs.open(
      label: 'Pictures (JPEG, PNG, WebP)',
      extensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (path == null) return null;
    final file = File(path);
    require(
      await file.length() <= 5000000,
      'Choose an image no larger than 5 MB.',
    );
    return file.readAsBytes();
  }

  @override
  Future<String?> pickChurchBanner() async {
    final raw = await _pickImage();
    return raw == null ? null : churchBannerFrom(raw);
  }

  @override
  Future<String?> pickChurchPhoto() async {
    final raw = await _pickImage();
    return raw == null ? null : churchPhotoFrom(raw);
  }

  @override
  Future<Uint8List?> loadLyricPicture() async {
    final f = File(_path('lyric-picture.jpg'));
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> saveLyricPicture(Uint8List bytes) =>
      writeWhole(_path('lyric-picture.jpg'), bytes);

  @override
  Future<String?> lyricPicturePath() async => _path('lyric-picture.jpg');

  @override
  Future<Map<String, dynamic>?> pickTextFile() async {
    final path = await dialogs.open(
      label: 'Song words (TXT)',
      extensions: const ['txt'],
    );
    return path == null ? null : readTextFile(path);
  }

  // ---- Secrets ------------------------------------------------------------

  @override
  Future<void> saveDisplayPassword(String id, String password) =>
      _vault.save(id, password);
  @override
  Future<String?> savedDisplayPassword(String id) => _vault.read(id);
  @override
  Future<void> forgetDisplayPassword(String id) => _vault.forget(id);
  @override
  Future<String?> loadPairing() => _pairingVault.read('registry');
  @override
  Future<void> savePairing(String value) =>
      _pairingVault.save('registry', value);

  // ---- The LED sign -------------------------------------------------------

  @override
  Future<Json> displayPreferences() => sign.preferences();
  @override
  Future<void> setDisplayAutoReconnect(bool enabled) =>
      sign.autoReconnect(enabled);
  @override
  Future<List<Json>> discoverDisplays() => sign.discover();
  @override
  Future<Json> connectDisplay(String id, String password) =>
      sign.connect(id, password);
  @override
  Future<void> disconnectDisplay() => sign.disconnect();
  @override
  Future<void> useSimulator() => sign.simulator();
  @override
  Future<Json> checkDisplay() => sign.status();
  @override
  Future<Json> sendDisplay(Uint8List bytes, int generation, int? deadline) =>
      sign.send(bytes, deadline, generation);

  @override
  Future<void> forgetDisplay() async {
    final id = (await sign.preferences())['id'] as String;
    if (id.isNotEmpty) {
      await _vault.forget(id);
      await _forgetSignWifi(id);
    }
    await sign.forget();
  }

  @override
  Future<Json> administerDisplay(
    String kind,
    String value,
    int generation,
  ) async {
    final saved = await _state.read();
    require(saved != null, 'End the service before changing device settings.');
    final session = (jsonDecode(saved!) as Map)['session'];
    require(
      session is Map && session['phase'] != 'active',
      'End the service before changing device settings.',
    );
    final id = (await sign.preferences())['id'] as String;
    final outcome = await sign.administer(kind, value, generation);
    if (kind == 'devicePassword') await _vault.forget(id);
    if (kind == 'wifiPassword' || kind == 'ssid') await _forgetSignWifi(id);
    return outcome;
  }

  // ---- Wi-Fi --------------------------------------------------------------
  //
  // Windows keeps its own list of Wi-Fi networks and joins them itself, so
  // the app never switches network here: it remembers the sign's Wi-Fi
  // details (they travel in backups to and from Android) and sends the
  // operator to Windows' Wi-Fi settings.

  Future<Json> _profiles(String key) async =>
      Map<String, dynamic>.from(await _prefs.get(key) as Map? ?? {});

  static void _checkWifi(String ssid, String security) {
    require(
      ssid.trim().isNotEmpty &&
          utf8.encode(ssid).length <= 32 &&
          !ssid.codeUnits.any((c) => c < 0x20),
      'Enter a Wi-Fi name of 1–32 bytes.',
    );
    require(
      const {'open', 'wpa2', 'wpa3'}.contains(security),
      'Choose Open, WPA2 or WPA3.',
    );
  }

  static bool _wifiPassword(String? value) =>
      value != null &&
      value.length >= 8 &&
      value.length <= 63 &&
      value.codeUnits.every((c) => c >= 32 && c <= 126);

  @override
  Future<Json> signWifiProfile(String id) async {
    final j = (await _profiles('signWifi'))[id] as Map? ?? const {};
    return {
      'ssid': j['ssid'] as String? ?? '',
      'security': j['security'] as String? ?? 'wpa2',
      'bssid': j['bssid'] as String? ?? '',
      'passwordSaved': await _vault.contains('wifi:$id'),
      'supported': false,
      'wifiEnabled': true,
    };
  }

  @override
  Future<void> saveSignWifiProfile(Json profile) async {
    final id = profile['id'] as String? ?? '';
    final ssid = profile['ssid'] as String? ?? '';
    final security = profile['security'] as String? ?? 'wpa2';
    final bssid = profile['bssid'] as String? ?? '';
    final password = profile['password'] as String?;
    require(id.trim().isNotEmpty, 'Select a remembered display first.');
    _checkWifi(ssid, security);
    require(
      bssid.isEmpty ||
          RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$').hasMatch(bssid),
      'Invalid Wi-Fi access point address.',
    );
    final previous = await signWifiProfile(id);
    if (security != 'open') {
      final value =
          password ??
          ((previous['ssid'] == ssid || previous['ssid'] == '') &&
                  previous['security'] == security
              ? await _vault.read('wifi:$id')
              : null);
      require(
        _wifiPassword(value),
        'Enter the sign’s Wi-Fi password (8–63 characters).',
      );
      await _vault.save('wifi:$id', value!);
    } else {
      await _vault.forget('wifi:$id');
    }
    final all = await _profiles('signWifi');
    all[id] = {'ssid': ssid, 'security': security, 'bssid': bssid};
    await _prefs.set('signWifi', all);
  }

  Future<void> _forgetSignWifi(String id) async {
    final all = await _profiles('signWifi');
    if (all.remove(id) != null) await _prefs.set('signWifi', all);
    await _vault.forget('wifi:$id');
  }

  /// Passwords the person chose not to store: kept only while the app runs.
  final _unsavedPairWifi = <String, String>{};

  @override
  Future<Json> pairWifiProfile(String host) async {
    final j = (await _profiles('pairWifi'))[host] as Map? ?? const {};
    return {
      'ssid': j['ssid'] as String? ?? '',
      'security': j['security'] as String? ?? 'wpa2',
      'kind': j['kind'] as String? ?? 'church',
      'passwordSaved': await _vault.contains('pairwifi:$host'),
      'supported': false,
      'wifiEnabled': true,
    };
  }

  @override
  Future<void> savePairWifi(Json profile) async {
    final host = profile['host'] as String? ?? '';
    final ssid = profile['ssid'] as String? ?? '';
    final security = profile['security'] as String? ?? 'wpa2';
    final kind = profile['kind'] as String? ?? 'church';
    final password = profile['password'] as String?;
    require(host.trim().isNotEmpty, 'Join a host first.');
    _checkWifi(ssid, security);
    require(
      const {'church', 'hotspot', 'sign'}.contains(kind),
      'Choose how this computer joined.',
    );
    _unsavedPairWifi.remove(host);
    if (security == 'open') {
      await _vault.forget('pairwifi:$host');
    } else if (password != null && password.isNotEmpty) {
      require(
        _wifiPassword(password),
        'Enter the Wi-Fi password (8–63 characters).',
      );
      if (profile['store'] != false) {
        await _vault.save('pairwifi:$host', password);
      } else {
        await _vault.forget('pairwifi:$host');
        _unsavedPairWifi[host] = password;
      }
    }
    final all = await _profiles('pairWifi');
    all[host] = {'ssid': ssid, 'security': security, 'kind': kind};
    await _prefs.set('pairWifi', all);
  }

  @override
  Future<void> forgetPairWifi(String host) async {
    final all = await _profiles('pairWifi');
    if (all.remove(host) != null) await _prefs.set('pairWifi', all);
    await _vault.forget('pairwifi:$host');
    _unsavedPairWifi.remove(host);
  }

  @override
  Future<void> openWifiSettings() async {
    system.open('ms-settings:network-wifi');
  }

  @override
  Future<Json> displayNetworkInfo({bool requestName = false}) =>
      desktopNetworkInfo();

  @override
  Future<String> localNetworkAddress() async {
    final address = pickLanAddress(
      await lanAddresses(),
      avoid: sign.localAddress,
    );
    require(
      address != null,
      'Connect this computer to the same network as the other devices first.',
    );
    return address!;
  }

  // ---- Staying awake and warnings -----------------------------------------

  bool _keepScreen = false, _sharing = false, _serviceRunning = false;
  void _applyAwake() {
    // Windows must not sleep while a service runs or screens are shared,
    // but the display follows the app's own choice (it already says when
    // a service, a stage screen or sharing needs it), so an idle or
    // sharing-only PC can turn its monitor off and save power.
    final busy = _sharing || _serviceRunning;
    system.keepAwake(system: busy, display: _keepScreen);
  }

  @override
  Future<void> setKeepScreenAwake(bool enabled) async {
    _keepScreen = enabled;
    _applyAwake();
  }

  /// A desktop app is never suspended, so "background operation" is simply
  /// on; what this adds is asking Windows not to sleep meanwhile.
  @override
  Future<bool> setActiveService(bool enabled) async {
    _sharing = enabled;
    _applyAwake();
    return enabled;
  }

  @override
  Future<bool> activeServiceRunning() async => _sharing;

  /// Android shows this card as a notification. Windows has no place for
  /// it, but the card says whether a service is running, and a PC must not
  /// go to sleep in the middle of one.
  @override
  Future<void> updateServiceNotification(Json card) async {
    final running = card['active'] == true;
    if (running == _serviceRunning) return;
    _serviceRunning = running;
    _applyAwake();
  }

  @override
  Future<Json> notificationStatus() async {
    await _loadSound();
    await _loadTray();
    return {
      'enabled': true,
      'exact': true,
      'sound': _sound,
      'tray': _tray.enabled,
    };
  }

  @override
  Future<void> syncWarnings(Json plan) async {
    await _loadSound();
    final clear = plan['clearSeconds'];
    if (clear is int && const {0, 15, 30, 60}.contains(clear)) {
      _clearSeconds = clear;
    }
    _warnings.sync(plan);
  }

  @override
  Future<void> testNotification() async {
    await _loadSound();
    _warn(
      'Church Service Timer test warning',
      'Warnings appear like this, without sound, and the taskbar button flashes.',
    );
  }

  // ---- Fonts --------------------------------------------------------------

  @override
  Future<bool> hasTinosFont() => _tinos.available();
  @override
  Future<Json> rasterizeTinos(TextLayout layout) => _tinos.rasterize(
    layout.text,
    layout.height * 7,
    bold: layout.bold,
    italic: layout.italic,
  );

  // ---- Smaller things -----------------------------------------------------

  static const feedbackRecipient = 'immanuelproton@gmail.com';

  /// Hands a draft to the PC's email program; never sends anything itself.
  /// Windows cannot pass a long message in a link, so a long one is put
  /// on the clipboard instead, with a line in the draft saying to paste it.
  @override
  Future<bool> composeFeedback(String subject, String body) async {
    require(
      subject.trim().isNotEmpty &&
          subject.length <= 512 &&
          !subject.contains('\r') &&
          !subject.contains('\n'),
      'Invalid feedback title',
    );
    require(
      body.trim().isNotEmpty && body.length <= 12000,
      'Invalid feedback message',
    );
    String link(String text) =>
        'mailto:$feedbackRecipient?subject=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent(text)}';
    var uri = link(body);
    if (uri.length > 1900) {
      await Clipboard.setData(ClipboardData(text: body));
      uri = link(
        'The feedback text has been copied. Press Ctrl+V here to paste it.',
      );
    }
    return system.open(uri);
  }

  /// Only https pages, in whichever browser the person uses.
  @override
  Future<bool> openWebPage(String url) async =>
      url.startsWith('https://') && system.open(url);

  @override
  UpdateChecker get updateChecker => const UpdateChecker();

  /// The installer replaces the app's files, so once it has started the
  /// app closes as if its window were closed: the notification-area icon,
  /// warnings and the stage window go with it.
  @override
  late final UpdateInstaller? updateInstaller = updateFiles == null
      ? null
      : UpdateInstaller(
          updateFiles!,
          quit: () async {
            await windowClosing();
            dispose();
            exitApp();
          },
        );

  @override
  Future<Json> batteryStatus() async => system.power();
  @override
  Future<String> deviceDescription() async => system.description();

  void dispose() {
    _tray.close();
    _warnings.dispose();
    stageOutput?.dispose();
  }
}

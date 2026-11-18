import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter/foundation.dart';

/// One screen connected to this computer: its place on the desktop as
/// `[left, top, right, bottom]` in Windows' own pixels.
typedef StageMonitor = ({int index, List<int> rect, bool primary});

/// The second copy of the app that draws the stage window.
abstract class StageChild {
  /// Completes when that copy has closed, however it closed.
  Future<void> get exited;
  void kill();
}

/// What only the operating system can do for the stage window: list the
/// screens and start the second copy. Tests use a fake.
abstract class StageOutputLauncher {
  List<StageMonitor> monitors();
  Future<StageChild> launch(List<String> arguments);
}

/// Shows the stage output full screen on a projector or second monitor.
///
/// Flutter draws one window per running app, so the stage window is a
/// second copy of the app started in a "stage output" mode. This copy
/// stays the only one that runs the service: it sends the other the same
/// picture a paired stage screen gets, over a connection that never leaves
/// this computer (loopback only, opened with a one-time token). If either
/// copy closes, the connection ends and the stage window closes with it.
class StageOutputHost extends ChangeNotifier {
  final StageOutputLauncher launcher;
  StageOutputHost(this.launcher);

  static final _random = math.Random.secure();

  ServerSocket? _server;
  Socket? _socket;
  StageChild? _child;
  int _generation = 0;
  String? _lastSent;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  Json? _latest;

  /// The screen the stage window is on, or null when it is not open.
  int? monitor;
  String? error;
  bool get open => monitor != null;

  /// True once the stage window has connected and is being sent pictures.
  bool get connected => _socket != null;

  List<StageMonitor> monitors() {
    try {
      return launcher.monitors();
    } catch (_) {
      return const [];
    }
  }

  Future<void> show(StageMonitor screen) async {
    await close();
    final generation = ++_generation;
    error = null;
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      final token = List.generate(
        16,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      server.listen((socket) => _accept(socket, token, generation));
      final child = await launcher.launch([
        '--stage-output',
        '--port=${server.port}',
        '--token=$token',
        '--rect=${screen.rect.join(',')}',
        // Stays above other windows on its own screen, but never over
        // the operator's controls on the main one.
        if (!screen.primary) '--topmost',
      ]);
      if (generation != _generation) {
        child.kill();
        return;
      }
      _child = child;
      monitor = screen.index;
      unawaited(
        child.exited.then((_) {
          if (generation == _generation) unawaited(close());
        }),
      );
    } catch (_) {
      await close();
      error = 'The stage window could not be opened.';
    }
    notifyListeners();
  }

  void _accept(Socket socket, String token, int generation) {
    var authorised = false;
    final lines = utf8.decoder.bind(socket).transform(const LineSplitter());
    lines.listen(
      (line) {
        if (authorised) return;
        if (line != token || generation != _generation || _socket != null) {
          socket.destroy();
          return;
        }
        authorised = true;
        _socket = socket;
        _lastSent = null;
        if (_latest != null) send(_latest!);
        notifyListeners();
      },
      onError: (_) => socket.destroy(),
      onDone: () {
        socket.destroy();
        if (_socket == socket && generation == _generation) {
          unawaited(close());
        }
      },
      cancelOnError: true,
    );
  }

  /// Sends the stage picture. Unchanged pictures are sent once a second
  /// only, as a sign that this copy is still running.
  void send(Json snapshot) {
    _latest = snapshot;
    final socket = _socket;
    if (socket == null) return;
    final line = jsonEncode(snapshot);
    final now = DateTime.now();
    if (line == _lastSent && now.difference(_lastSentAt).inMilliseconds < 1000)
      return;
    _lastSent = line;
    _lastSentAt = now;
    try {
      socket.writeln(line);
    } catch (_) {
      unawaited(close());
    }
  }

  Future<void> close() async {
    _generation++;
    final wasOpen = open;
    final socket = _socket, server = _server, child = _child;
    _socket = null;
    _server = null;
    _child = null;
    monitor = null;
    _lastSent = null;
    socket?.destroy();
    try {
      await server?.close();
    } catch (_) {}
    child?.kill();
    if (wasOpen) notifyListeners();
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}

/// The stage window's side of the connection: the latest picture, and
/// whether it has gone quiet.
class StageFeed extends ChangeNotifier {
  Json? data;
  bool closed = false;
  DateTime _received = DateTime.now();
  Timer? _watch;
  Socket? _socket;

  /// No picture for this long means the main app has stalled; the stage
  /// then marks its timer as out of date instead of showing a wrong time.
  static const staleAfter = Duration(milliseconds: 3500);
  bool get stale => DateTime.now().difference(_received) >= staleAfter;

  Future<void> connect(int port, String token) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 10),
      );
      _socket = socket;
      socket.writeln(token);
      utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .listen(
            receive,
            onError: (_) => _end(),
            onDone: _end,
            cancelOnError: true,
          );
      var wasStale = false;
      _watch = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (stale != wasStale) {
          wasStale = stale;
          notifyListeners();
        }
      });
    } catch (_) {
      _end();
    }
  }

  void receive(String line) {
    try {
      data = Map<String, dynamic>.from(jsonDecode(line) as Map);
      _received = DateTime.now();
      notifyListeners();
    } catch (_) {
      // A damaged line is skipped; the next one replaces it.
    }
  }

  void _end() {
    if (closed) return;
    closed = true;
    _watch?.cancel();
    _socket?.destroy();
    notifyListeners();
  }

  @override
  void dispose() {
    _watch?.cancel();
    _socket?.destroy();
    super.dispose();
  }
}

/// Reads `--name=value` from the stage window's command line.
String? stageArgument(List<String> arguments, String name) {
  for (final argument in arguments) {
    if (argument.startsWith('--$name=')) {
      return argument.substring(name.length + 3);
    }
  }
  return null;
}

/// The screen rectangle from `--rect=left,top,right,bottom`, or null when
/// it is missing or makes no sense.
List<int>? stageRect(List<String> arguments) {
  final parts = stageArgument(arguments, 'rect')?.split(',');
  if (parts == null || parts.length != 4) return null;
  final values = parts.map(int.tryParse).toList();
  if (values.any((v) => v == null)) return null;
  final rect = values.cast<int>();
  return rect[2] - rect[0] >= 200 && rect[3] - rect[1] >= 200 ? rect : null;
}

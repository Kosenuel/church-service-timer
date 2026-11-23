import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/web_stage/web_page.dart';

/// Who may follow the order of service from a browser.
enum OrderAccess {
  off('Off'),
  code('Needs the guest code'),
  open('Open to anyone on this Wi-Fi');

  final String label;
  const OrderAccess(this.label);
}

/// The three views a browser can open.
enum WebRole {
  order('Order of service'),
  stage('Stage display'),
  overview('Service overview');

  final String label;
  const WebRole(this.label);
  bool get team => this != WebRole.order;
}

/// Saved on the host device. The guest code stays until changed,
/// so it can go on a slide week after week.
class WebStageSettings {
  final OrderAccess orderAccess;
  final String orderCode;
  final bool showSpeakers;

  /// What Stage displays show under the time: 'timer', 'current' or
  /// 'next', as [stageLayouts] names them.
  final String stageLayout;

  /// Shown as `<localName>.local`.
  final String localName;

  /// Chosen by a person; otherwise it follows the church name.
  final bool customName;
  const WebStageSettings({
    this.orderAccess = OrderAccess.code,
    required this.orderCode,
    this.showSpeakers = false,
    this.stageLayout = 'timer',
    required this.localName,
    this.customName = false,
  });

  WebStageSettings copyWith({
    OrderAccess? orderAccess,
    String? orderCode,
    bool? showSpeakers,
    String? stageLayout,
    String? localName,
  }) => WebStageSettings(
    orderAccess: orderAccess ?? this.orderAccess,
    orderCode: orderCode ?? this.orderCode,
    showSpeakers: showSpeakers ?? this.showSpeakers,
    stageLayout: stageLayout ?? this.stageLayout,
    localName: localName ?? this.localName,
    customName: localName != null || customName,
  );

  Json toJson() => {
    'orderAccess': orderAccess.name,
    'orderCode': orderCode,
    'showSpeakers': showSpeakers,
    'stageLayout': stageLayout,
    'localName': localName,
    'customName': customName,
  };

  factory WebStageSettings.fromJson(Json j, {required String churchName}) {
    final code = j['orderCode'];
    final name = j['localName'];
    final custom =
        j['customName'] == true && name is String && validLocalName(name);
    return WebStageSettings(
      orderAccess:
          OrderAccess.values
              .where((v) => v.name == j['orderAccess'])
              .firstOrNull ??
          OrderAccess.code,
      orderCode: code is String && validOrderCode(code) ? code : newOrderCode(),
      showSpeakers: j['showSpeakers'] == true,
      stageLayout: stageLayoutValue(j['stageLayout']),
      // Until someone chooses a name, it follows the church profile.
      localName: custom ? name : localNameFor(churchName),
      customName: custom,
    );
  }
}

final _random = Random.secure();

String newOrderCode() => List.generate(4, (_) => _random.nextInt(10)).join();
String newTeamCode() => List.generate(6, (_) => _random.nextInt(10)).join();

/// 4–8 letters or digits, compared without regard to case.
bool validOrderCode(String code) =>
    RegExp(r'^[A-Za-z0-9]{4,8}$').hasMatch(code);

/// A DNS label: 1–40 lowercase letters, digits and hyphens.
bool validLocalName(String name) =>
    RegExp(r'^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?$').hasMatch(name);

const _plainLetters = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'æ': 'ae',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'œ': 'oe',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ß': 'ss',
  'ẹ': 'e',
  'ọ': 'o',
  'ṣ': 's',
  'ń': 'n',
};

/// Longest automatic easy name; a person can still choose a longer one.
const localNameShortLimit = 20;

const _fillerWords = {
  'the',
  'of',
  'and',
  'a',
  'an',
  'in',
  'at',
  'for',
  'on',
  'to',
  'de',
  'la',
  'le',
  'du',
  'des',
  'et',
};
const _genericWords = {
  'church',
  'churches',
  'chapel',
  'cathedral',
  'parish',
  'ministry',
  'ministries',
  'international',
  'intl',
  'assembly',
  'fellowship',
  'centre',
  'center',
  'global',
  'worldwide',
  'mission',
  'inc',
  'ltd',
  'congregation',
  'tabernacle',
  'temple',
  'worship',
  'family',
};

/// Plain lowercase words from a name: accents simplified, apostrophes
/// dropped, `&` read as `and`.
List<String> _plainWords(String text) {
  final plain = StringBuffer();
  for (final ch in text.toLowerCase().runes.map(String.fromCharCode)) {
    plain.write(_plainLetters[ch] ?? ch);
  }
  return plain
      .toString()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r"['’`]"), '')
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
}

/// Tidies typed text into a `.local` name: spaces and punctuation become
/// single hyphens (`Grace Church` → `grace-church`), at most 40 letters.
String localNameFrom(String text) {
  final slug = _plainWords(text).join('-');
  final cut = slug.length > 40 ? slug.substring(0, 40) : slug;
  final clean = cut.replaceAll(RegExp(r'-+$'), '');
  return clean.isEmpty ? 'church-timer' : clean;
}

/// A short, memorable `.local` name from a church name, at most 20 letters:
/// `Grace Community Church` → `grace-community`, `St. Mary's Cathedral`
/// → `marys`, `The Redeemed Christian Church of God, Victory Parish` →
/// `rccg-victory`. Filler words go first, then generic words such as
/// church or ministries; if it is still long, the words before the last
/// become initials. `church-timer` when nothing usable remains.
String localNameFor(String churchName) {
  final all = _plainWords(churchName);
  final words = [
    for (final w in all)
      if (!_fillerWords.contains(w)) w,
  ];
  if (words.isEmpty)
    return all.isEmpty ? 'church-timer' : localNameFrom(all.join(' '));
  String join(List<String> w) => w.join('-');
  if (join(words).length <= localNameShortLimit) return join(words);
  final distinct = [
    for (final w in words)
      if (!_genericWords.contains(w)) w,
  ];
  if (distinct.isNotEmpty && join(distinct).length <= localNameShortLimit) {
    return join(distinct);
  }
  // Still long. With few distinctive words, keep the leading ones that fit
  // ("Église Évangélique de Paris" → eglise-evangelique).
  final pool = distinct.isEmpty ? words : distinct;
  if (pool.length < 4) {
    final kept = <String>[];
    for (final w in pool) {
      if (join([...kept, w]).length > localNameShortLimit) break;
      kept.add(w);
    }
    if (kept.isNotEmpty) return join(kept);
  }
  // Many words: initials of everything before the last distinctive word,
  // generic words included ("Redeemed Christian Church of God" is RCCG).
  final last = distinct.isEmpty ? words.last : distinct.last;
  final before = words.sublist(0, words.lastIndexOf(last));
  final initials = before.map((w) => w[0]).join();
  final short = [if (initials.isNotEmpty) initials, last].join('-');
  return short.length <= localNameShortLimit
      ? short
      : short.substring(0, localNameShortLimit).replaceAll(RegExp(r'-+$'), '');
}

class WebDevice {
  final String token, label, address;
  WebRole role;
  int lastSeen;
  WebDevice(this.token, this.role, this.label, this.address)
    : lastSeen = DateTime.now().millisecondsSinceEpoch;
  bool get team => role.team || _team;
  bool _team = false;
  bool get active => DateTime.now().millisecondsSinceEpoch - lastSeen < 30000;
}

/// Serves the web stage page while the host device shares to screens.
/// Browsers join with the guest code (or none, when open) or
/// the team code; nothing private (notes, cues) and no controls are served.
class WebStageServer {
  static const preferredPort = 8080;
  static const orderViewerLimit = 100;
  static const maxBody = 4096;

  WebStageSettings Function() settings;

  /// The paired-screen snapshot without private notes, plus timing fields.
  final Json Function() snapshot;
  void Function(WebDevice device)? onJoined;

  /// Whether a Stage display was chosen to receive the current message.
  bool Function(WebDevice device)? showsMessage;
  void Function()? onChanged;

  /// Stage requests: whether they are open now, what happens when a team
  /// Stage display sends one, and that display's own request state.
  bool Function()? requestsOpen;
  bool Function(WebDevice device, String kind)? onRequest;
  Json? Function(WebDevice device)? requestFor;
  bool _requestsFor(WebDevice d) =>
      d.team && d.role == WebRole.stage && (requestsOpen?.call() ?? false);

  WebStageServer({required this.settings, required this.snapshot});

  HttpServer? _server;
  String teamCode = newTeamCode();
  final devices = <String, WebDevice>{};
  final _failures = <String, ({int count, int until})>{};

  bool get running => _server != null;
  int? get port => _server?.port;
  String? address;

  /// Serves on [host]. With [keepSession] (a network change, not a new
  /// share) the team code and joined browsers carry over, so browsers that
  /// reach the page again by the easy name carry on without a new code.
  Future<void> start(String host, {bool keepSession = false}) async {
    final code = teamCode;
    final joined = Map.of(devices);
    await stop();
    try {
      _server = await HttpServer.bind(host, preferredPort);
    } on SocketException {
      _server = await HttpServer.bind(host, 0);
    }
    address = host;
    teamCode = keepSession ? code : newTeamCode();
    if (keepSession) devices.addAll(joined);
    _server!.listen((r) => unawaited(_handle(r)));
    onChanged?.call();
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    devices.clear();
    _failures.clear();
    await s?.close(force: true);
    onChanged?.call();
  }

  /// New codes: team browsers must enter the new team code. With
  /// [orderToo], order-of-service browsers must too.
  void newCodes({bool orderToo = false}) {
    teamCode = newTeamCode();
    devices.removeWhere((_, d) => d.team || orderToo);
    onChanged?.call();
  }

  /// Order-of-service browsers that joined with an old guest code.
  void forgetOrderViewers() {
    devices.removeWhere((_, d) => !d.team);
    onChanged?.call();
  }

  void remove(String token) {
    if (devices.remove(token) != null) onChanged?.call();
  }

  /// Stage displays that fetched the output within the last few seconds,
  /// as for paired stage screens: these count as a connected stage.
  List<WebDevice> get syncedStageDevices => [
    for (final d in devices.values)
      if (d.role == WebRole.stage &&
          DateTime.now().millisecondsSinceEpoch - d.lastSeen < 3500)
        d,
  ];

  List<WebDevice> get activeDevices => [
    for (final d in devices.values)
      if (d.active) d,
  ];

  String _token() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  /// Locks a browser out for a while after repeated wrong codes.
  bool _locked(String ip) {
    final f = _failures[ip];
    return f != null && DateTime.now().millisecondsSinceEpoch < f.until;
  }

  void _fail(String ip) {
    final prev = _failures[ip];
    final count = (prev?.count ?? 0) + 1;
    // 5 tries, then 30 s, doubling with each further five (max 15 min).
    final wait = count % 5 == 0
        ? min(30000 * pow(2, count ~/ 5 - 1).toInt(), 900000)
        : 0;
    _failures[ip] = (
      count: count,
      until: wait == 0 ? 0 : DateTime.now().millisecondsSinceEpoch + wait,
    );
  }

  /// Which roles a code unlocks: the team code all three, the guest code
  /// (or none, when open) only the order of service.
  bool? _codeTier(String? code) {
    final c = (code ?? '').trim();
    if (c.isNotEmpty && c == teamCode) return true;
    final s = settings();
    if (s.orderAccess == OrderAccess.off) return null;
    if (s.orderAccess == OrderAccess.open && c.isEmpty) return false;
    if (c.isNotEmpty && c.toLowerCase() == s.orderCode.toLowerCase()) {
      return false;
    }
    return null;
  }

  Future<void> _handle(HttpRequest r) async {
    final res = r.response;
    res.headers
      ..set('Cache-Control', 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('X-Frame-Options', 'DENY')
      ..set('Referrer-Policy', 'no-referrer');
    try {
      final ip = r.connectionInfo?.remoteAddress.address ?? '';
      final path = r.uri.path;
      if (r.method == 'GET' && (path == '/' || path == '/index.html')) {
        res.headers.contentType = ContentType.html;
        res.headers.set(
          'Content-Security-Policy',
          "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:",
        );
        res.write(webStagePage);
      } else if (r.method == 'GET' && path == '/api/info') {
        final s = settings();
        _json(res, {
          'church': (snapshot()['church'] as String?) ?? '',
          'orderAccess': s.orderAccess.name,
        });
      } else if (r.method == 'POST' && path == '/api/join') {
        final body = await _body(r);
        if (_locked(ip)) {
          _json(res, {
            'error': 'Too many tries. Wait a moment, then try again.',
          }, 429);
          return;
        }
        final team = _codeTier(body['code'] as String?);
        if (team == null) {
          _fail(ip);
          _json(res, {
            'error':
                'That code is not right. Ask the team for the current code.',
          }, 403);
          return;
        }
        _failures.remove(ip);
        if (!team &&
            devices.values.where((d) => !d.team && d.active).length >=
                orderViewerLimit) {
          _json(res, {
            'error': 'Too many people are following right now. Try again soon.',
          }, 503);
          return;
        }
        final role = team
            ? (WebRole.values
                      .where((v) => v.name == body['role'])
                      .firstOrNull ??
                  WebRole.stage)
            : WebRole.order;
        final device = WebDevice(
          _token(),
          role,
          _label(r.headers.value('user-agent') ?? ''),
          ip,
        ).._team = team;
        devices[device.token] = device;
        if (team) onJoined?.call(device);
        onChanged?.call();
        _json(res, {'token': device.token, 'role': role.name, 'team': team});
      } else if (r.method == 'POST' && path == '/api/role') {
        final body = await _body(r);
        final device = devices[body['token']];
        final role = WebRole.values
            .where((v) => v.name == body['role'])
            .firstOrNull;
        if (device == null || role == null) {
          _json(res, {'error': 'Join again.'}, 401);
          return;
        }
        if (role.team && !device.team) {
          if (_locked(ip)) {
            _json(res, {
              'error': 'Too many tries. Wait a moment, then try again.',
            }, 429);
            return;
          }
          if (_codeTier(body['code'] as String?) != true) {
            _fail(ip);
            _json(res, {
              'error': 'Enter the team code from the host device.',
            }, 403);
            return;
          }
          _failures.remove(ip);
          device._team = true;
          onJoined?.call(device);
        }
        device.role = role;
        onChanged?.call();
        _json(res, {'role': role.name, 'team': device.team});
      } else if (r.method == 'POST' && path == '/api/request') {
        final body = await _body(r);
        final device = devices[body['token']];
        if (device == null) {
          _json(res, {'error': 'Join again.'}, 401);
          return;
        }
        final kind = body['kind'];
        final ok =
            _requestsFor(device) &&
            kind is String &&
            (onRequest?.call(device, kind) ?? false);
        _json(
          res,
          ok ? {'sent': true} : {'error': 'Not sent.'},
          ok ? 200 : 409,
        );
      } else if (r.method == 'GET' && path == '/api/state') {
        final device = devices[r.uri.queryParameters['token']];
        if (device == null ||
            (!device.team && settings().orderAccess == OrderAccess.off)) {
          _json(res, {'error': 'Join again.'}, 401);
          return;
        }
        final wasActive = device.active;
        device.lastSeen = DateTime.now().millisecondsSinceEpoch;
        if (!wasActive) onChanged?.call();
        _json(res, {
          'role': device.role.name,
          'team': device.team,
          ...viewFor(device.role, snapshot(), settings())..removeWhere(
            (k, _) =>
                k == 'message' &&
                showsMessage != null &&
                !showsMessage!(device),
          ),
          if (_requestsFor(device)) ...{
            'requests': true,
            if (requestFor?.call(device) case final Json request)
              'request': request,
          },
        });
      } else {
        res.statusCode = HttpStatus.notFound;
      }
    } catch (_) {
      res.statusCode = HttpStatus.badRequest;
    } finally {
      await res.close();
    }
  }

  Future<Json> _body(HttpRequest r) async {
    final bytes = <int>[];
    await for (final chunk in r) {
      bytes.addAll(chunk);
      if (bytes.length > maxBody) throw const FormatException('Too large');
    }
    final j = jsonDecode(utf8.decode(bytes));
    return j is Map ? Map<String, dynamic>.from(j) : {};
  }

  void _json(HttpResponse res, Json body, [int status = 200]) {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
  }

  /// "Laptop · Chrome" from a user agent, without anything identifying.
  static String _label(String ua) {
    final device = ua.contains('iPad')
        ? 'iPad'
        : ua.contains('iPhone')
        ? 'iPhone'
        : ua.contains('Android')
        ? (ua.contains('Mobile') ? 'Android phone' : 'Android tablet')
        : ua.contains('SmartTV') ||
              ua.contains('SMART-TV') ||
              ua.contains('Tizen') ||
              ua.contains('Web0S')
        ? 'TV'
        : 'Computer';
    final browser = ua.contains('Edg/')
        ? 'Edge'
        : ua.contains('Firefox')
        ? 'Firefox'
        : ua.contains('Chrome')
        ? 'Chrome'
        : ua.contains('Safari')
        ? 'Safari'
        : 'Browser';
    return '$device · $browser';
  }
}

/// What each role may see. Order of service has no times at all; nothing
/// carries private notes or cues.
Json viewFor(WebRole role, Json s, WebStageSettings settings) {
  final rundown = (s['rundown'] as List? ?? const []).whereType<Map>().toList();
  final phase = s['phase'] as String? ?? 'idle';
  final common = {
    'church': s['church'] ?? '',
    'phase': phase,
    'service': phase == 'idle' ? '' : s['service'] ?? '',
    'index': s['index'] ?? 0,
  };
  switch (role) {
    case WebRole.order:
      return {
        ...common,
        'rundown': phase == 'idle'
            ? const []
            : [
                for (final e in rundown)
                  {
                    'name': e['name'],
                    if (settings.showSpeakers &&
                        (e['speaker'] as String? ?? '').isNotEmpty)
                      'speaker': e['speaker'],
                  },
              ],
      };
    case WebRole.stage:
      // On the last segment, in a Quick timer or with no program, 'Up next
      // only' shows the end screen set for the program, or the clock.
      s = stageForLayout(s, settings.stageLayout);
      // A banner cue: the page shows the countdown or clock as usual and
      // the cue in a band over it.
      final position = stageBannerPosition(s);
      final shown = position == null ? s : stageUnderBanner(s);
      final color = stageCueRgb(s);
      String effectOf(Json from) =>
          const {'scroll', 'flash'}.contains(from['effect'])
          ? from['effect']
          : 'static';
      // The newer effects the page draws itself; a countdown bar only with
      // a time to run over.
      Json effectsOf(Json from) {
        final effect = stageScreenEffect(from);
        final time = stageCueTime(from);
        if (effect == null || (effect == 'bar' && time == null)) return {};
        return {
          'screenEffect': effect,
          if (time != null) 'cueTime': {'total': time.total, 'left': time.left},
        };
      }

      return {
        ...common,
        'sharing': s['stageSharing'] == true,
        'blank': s['blank'] == true,
        // A flip clock, wherever the screen is filled with the time of
        // day, in the host's theme (white on black from an older host).
        if (shown['displayIsTimer'] != true)
          'clock': ?_clockView(stageClockFace(shown)),
        'theme': ?stageThemeOf(s),
        'displayText': shown['displayText'] ?? '',
        'bold': shown['bold'] == true,
        'italic': shown['italic'] == true,
        'effect': effectOf(shown),
        ...effectsOf(shown),
        // The cue's speed on screens; the LED sign's until one is set.
        'speed': stageScrollSpeed(s),
        // Only a checked "#rrggbb" reaches the page.
        if (color != null && position == null) 'color': stageColorHex(color),
        // "Wrap long text": up to 3 lines, as large as fits, not scrolling.
        if (position == null && stageWrapsText(s)) 'wrap': true,
        // Flash or Pulse text too wide for the LED sign, a few words at a
        // time as the sign shows it.
        if (position == null) 'words': ?stageWordGroups(s),
        if (position != null)
          'banner': {
            'text': s['displayText'] ?? '',
            'position': position,
            'color': stageColorHex(color ?? 0xffffff),
            'bold': s['bold'] == true,
            'italic': s['italic'] == true,
            'effect': effectOf(s),
            if (stageWrapsText(s)) 'wrap': true,
            'words': ?stageWordGroups(s),
            ...effectsOf(s),
          },
        'layout': settings.stageLayout,
        // The countdown's own look: how far through the segment it is and
        // the moment it is in (see [stageMoment]), the bands for the
        // segment now and what is next, and how strongly overtime shows.
        if (shown['displayIsTimer'] == true)
          'countdown': {
            'moment': stageMoment(s),
            'progress': stageProgress(s),
            'alert': overtimeAlertValue(s['overtimeAlert']),
            'now': {
              'name': '${s['segment'] ?? ''}',
              'by': '${s['speaker'] ?? ''}'.trim(),
            },
            if (stageUpNext(s) case final next?)
              'next': {'name': next.name, 'detail': next.detail},
          },
        'overtime': s['overtime'] == true,
        'paused': s['paused'] == true,
        // Whether the text is a countdown or clock, whose colon blinks.
        'ticking':
            s['clockBlink'] != false &&
            (shown['outputMode'] == 'Clock' ||
                (shown['displayIsTimer'] == true && s['paused'] != true)),
        if (s['quickMessage'] case final Map q)
          'message': {
            'headline': q['headline'] ?? '',
            'body': q['body'] ?? '',
            // The same colours and style the paired screens show; only
            // known values pass, so the page never applies raw input.
            'palette': const {'amber', 'sky', 'mint'}.contains(q['palette'])
                ? q['palette']
                : 'white',
            'align': const {'left', 'right'}.contains(q['align'])
                ? q['align']
                : 'center',
            'bold': q['bold'] == true,
            'italic': q['italic'] == true,
            'scale': ((q['scale'] as num?)?.toDouble() ?? 1.0).clamp(.5, 2.0),
          },
      };
    case WebRole.overview:
      return {
        ...common,
        'segment': s['segment'] ?? '',
        'next': s['nextSegment'] ?? '',
        'remaining': s['remaining'] ?? '',
        'overtime': s['overtime'] == true,
        'paused': s['paused'] == true,
        'variance': s['variance'] ?? '',
        'behind': s['behind'] == true,
        'finish': s['finish'] ?? '',
        'rundown': [
          for (final e in rundown)
            {
              'name': e['name'],
              'minutes': e['minutes'],
              'seconds': e['seconds'],
              'speaker': e['speaker'] ?? '',
            },
        ],
      };
  }
}

/// The flip clock as the web page draws it, or null for no clock.
Json? _clockView(StageClockFace? face) => face == null
    ? null
    : {
        'hours': face.hours,
        'minutes': face.minutes,
        'pm': ?face.pm,
        'weekday': face.weekday,
        'date': face.date,
      };

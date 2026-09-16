import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show MaterialApp, Scaffold;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'package:video_player/video_player.dart';
import 'app_experience.dart';
import 'console_shell.dart';
import 'flyer_composer_page.dart';
import 'generation_page.dart';
import 'native_editor.dart';
import 'native_results.dart';
import 'profile_manager.dart';
import 'team_page.dart';
import 'trial_credentials.dart';
import 'instagram_connection.dart';
import 'phone_import.dart';
import 'app_motion.dart';
import 'inbox_automations.dart';
import 'schedule_calendar.dart';
import 'runtime_config.dart';

const String hostPrefKey = 'console.host';
const String nativeVersion = '1.0.46 (55)';
const String defaultHost = 'https://gateway.example.invalid:8445';
// Colour, type and the console primitives come from console_shell.dart. The
// legacy bg / panel / line / ink / muted / accent aliases stay in app_theme
// for the editor and results files that still reference them.

@immutable
class GatewayHost {
  const GatewayHost({
    required this.label,
    required this.url,
    required this.note,
    required this.secure,
  });
  final String label, url, note;
  final bool secure;
}

const List<GatewayHost> knownHosts = <GatewayHost>[
  GatewayHost(
    label: 'Tailnet over HTTPS',
    url: defaultHost,
    note: 'Best reach and microphone support.',
    secure: true,
  ),
  GatewayHost(
    label: 'Tailnet, direct',
    url: 'http://198.51.100.35:8105',
    note: 'Typing and review work; microphone may be unavailable.',
    secure: false,
  ),
  GatewayHost(
    label: 'Home network',
    url: 'http://192.0.2.15:8105',
    note: 'Use while on the house LAN.',
    secure: false,
  ),
];

String? normalizeHost(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'http://$text';
  final Uri? uri = Uri.tryParse(text);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  final bool defaultPort =
      (uri.scheme == 'http' && uri.port == 80) ||
      (uri.scheme == 'https' && uri.port == 443);
  final String port = uri.hasPort && !defaultPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port${uri.path.replaceAll(RegExp(r'/+$'), '')}';
}

String trialGatewayHost(String raw) {
  final Uri uri = Uri.parse(normalizeHost(raw) ?? defaultHost);
  final String path = uri.path.replaceFirst(
    RegExp(r'/(?:console(?:\.html)?|index\.html|trial\.html)$'),
    '',
  );
  return uri.replace(path: path).toString();
}

Uri trialEntryUri(String raw) {
  final Uri host = Uri.parse(trialGatewayHost(raw));
  return host.replace(
    path: '${host.path}/trial.html',
    queryParameters: const <String, String>{'native': '13'},
  );
}

GatewayHost? knownHostFor(String url) {
  for (final GatewayHost host in knownHosts) {
    if (host.url == url) return host;
  }
  return null;
}

/// Typed read boundary. Publishing and scheduling remain behind the existing
/// web workspace until their native confirmation flows are implemented.
class TrialApi {
  TrialApi(this.base, {HttpClient? client}) : _client = client ?? _shared;

  static HttpClient? _cachedClient;
  static Object? _cachedFor;

  /// One client for the whole app.
  ///
  /// TrialApi is constructed at 23 call sites, including inside closures
  /// handed to long-lived polling panels, and the class has no close(). Every
  /// poll tick used to leak a client and its connection pool, and `.timeout()`
  /// on request.close() resolves the future without aborting the socket, so
  /// file descriptors accumulated on every timeout too. The symptom on the
  /// phone is that after a long session the app stops loading anything until
  /// it is force-quit. The editor already shared one client and closed it;
  /// the pattern existed, it just was not applied here.
  ///
  /// Keyed on the active HttpOverrides so that one client does not outlive the
  /// scope that created it. In production there are no overrides, so this is
  /// one client for the life of the process; under test it is one client per
  /// HttpOverrides.runZoned, which is what keeps a fake gateway from leaking
  /// into the next test.
  static HttpClient get _shared {
    final Object? scope = HttpOverrides.current;
    if (_cachedClient == null || !identical(_cachedFor, scope)) {
      _cachedClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      _cachedFor = scope;
    }
    return _cachedClient!;
  }

  final String base;
  final HttpClient _client;

  /// The client this instance will use. Exposed so a test can prove the
  /// sharing rather than infer it.
  HttpClient get debugClient => _client;
  Future<dynamic> postJson(String path, Map<String, dynamic> payload) async {
    final HttpClientRequest request = await _client.postUrl(
      Uri.parse('$base$path'),
    );
    await TrialCredentials.attach(request, base);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.add(utf8.encode(jsonEncode(payload)));
    final HttpClientResponse response = await request.close().timeout(
      const Duration(seconds: 15),
    );
    // A gateway that returns headers and then stalls used to hang Approve,
    // Schedule, Scrap and Post now indefinitely: no spinner timeout, no
    // cancel, no failure recorded. getJson always had this budget; postJson
    // did not.
    final String body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 15));
    dynamic decoded;
    try {
      // A successful mutation may intentionally have no receipt body. It is
      // still a confirmed HTTP success, not a client-side JSON failure.
      decoded = body.isEmpty ? const <String, dynamic>{} : jsonDecode(body);
    } on FormatException {
      if (response.statusCode >= 200 && response.statusCode < 300) rethrow;
      decoded = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        decoded is Map
            ? '${decoded['detail'] ?? decoded['error'] ?? 'Gateway rejected the request'}'
            : 'Gateway returned ${response.statusCode}',
      );
    }
    return decoded;
  }

  Future<Uri> startOAuth(String account, String purpose) async {
    final dynamic result = await postJson('/reels/oauth/start', {
      'account': account,
      'purpose': purpose,
      // Marks this flow as app-initiated so the OAuth callback bounces back
      // to contentdoctor:// instead of the web connection.html page.
      'client': 'native',
    });
    if (result is! Map ||
        result['url'] is! String ||
        (result['url'] as String).isEmpty) {
      throw const FormatException('The connection link was not returned');
    }
    final Uri? uri = Uri.tryParse(result['url'] as String);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      throw const FormatException('The connection link is invalid');
    }
    return uri;
  }

  Future<dynamic> approveReview(Map<String, dynamic> item) =>
      postJson('/reels/review-approve', {
        'entries': [_exact(item)],
        // False when the operator confirmed a reel whose preview would not
        // play. The gateway is free to ignore this key today; it exists so a
        // reel nobody could watch is not recorded as one that was watched.
        'watch_observed': !watchBypassed('${item['sha256']}'),
        'idempotency_key': 'native-review-${item['id']}-${item['sha256']}',
      });
  Future<dynamic> schedule(Map<String, dynamic> item, DateTime when) =>
      postJson('/reels/schedule', {
        'entries': [
          {..._exact(item), 'scheduled_at': when.toUtc().toIso8601String()},
        ],
        'idempotency_key':
            'native-schedule-${item['id']}-${when.toUtc().toIso8601String()}',
      });
  Future<dynamic> cancel(Map<String, dynamic> item) =>
      postJson('/reels/cancel', {
        ..._exact(item),
        'idempotency_key': 'native-cancel-${item['id']}-${item['sha256']}',
      });
  Future<dynamic> scrap(Map<String, dynamic> item) => postJson('/reels/scrap', {
    ..._exact(item),
    'idempotency_key': 'native-scrap-${item['id']}-${item['sha256']}',
  });
  Future<dynamic> restore(Map<String, dynamic> item) =>
      postJson('/reels/restore', {
        ..._exact(item),
        'idempotency_key': 'native-restore-${item['id']}-${item['sha256']}',
      });
  Future<dynamic> reschedule(
    Map<String, dynamic> item,
    DateTime when,
  ) => postJson('/reels/reschedule', {
    ..._exact(item),
    'scheduled_at': when.toUtc().toIso8601String(),
    'idempotency_key':
        'native-move-${item['id']}-${item['sha256']}-${when.toUtc().toIso8601String()}',
  });
  Future<dynamic> postNow(Map<String, dynamic> item) =>
      postJson('/reels/post-now', {
        ..._exact(item),
        'idempotency_key': 'native-post-${item['id']}-${item['sha256']}',
      });
  static Map<String, dynamic> _exact(Map<String, dynamic> item) => {
    'id': item['id'],
    'sha256': item['sha256'],
    'caption': item['caption'] ?? '',
    'account': item['account'],
    'confirm': true,
  };
  Future<dynamic> getJson(String path) async {
    final HttpClientRequest request = await _client.getUrl(
      Uri.parse('$base$path'),
    );
    await TrialCredentials.attachIfAvailable(request, base);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final HttpClientResponse response = await request.close().timeout(
      const Duration(seconds: 10),
    );
    final String body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 10));
    // Decode before throwing, so a gateway's own `detail` or `error` reaches
    // the operator instead of being replaced by a status code. postJson has
    // always done this.
    dynamic decoded;
    try {
      // 204 and an empty 200 are a successful read of nothing, not malformed
      // JSON. snapshotFromCatalog Future.waits four of these, so one empty
      // body from /reels/controls, /reels/schedules, /reels/oauth/status or
      // /reels/revision-status used to fail the whole snapshot and banner an
      // otherwise healthy load.
      decoded = body.trim().isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(body);
    } on FormatException {
      if (response.statusCode >= 200 && response.statusCode < 300) rethrow;
      decoded = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        decoded is Map
            ? '${decoded['detail'] ?? decoded['error'] ?? 'Gateway returned ${response.statusCode}'}'
            : 'Gateway returned ${response.statusCode}',
        uri: Uri.parse('$base$path'),
      );
    }
    if (decoded is! Map && decoded is! List) {
      throw const FormatException('Gateway returned an unexpected response');
    }
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : List<dynamic>.from(decoded);
  }

  Future<TrialSnapshot> snapshot() async {
    final dynamic catalog = await getJson('/reels/catalog');
    return snapshotFromCatalog(catalog);
  }

  Future<TrialSnapshot> snapshotFromCatalog(dynamic catalog) async {
    final List<dynamic> v = await Future.wait<dynamic>(<Future<dynamic>>[
      getJson('/reels/controls'),
      getJson('/reels/schedules'),
      getJson('/reels/oauth/status'),
      getJson('/reels/revision-status'),
    ]);
    return TrialSnapshot.fromResponses(catalog, v[0], v[1], v[2], v[3]);
  }
}

@immutable
class TrialSnapshot {
  const TrialSnapshot({
    required this.reels,
    required this.accounts,
    required this.schedules,
    required this.accountStatus,
    required this.catalogItems,
    required this.scheduleItems,
    required this.revisionStatus,
  });
  final int reels, accounts, schedules;
  final List<Map<String, dynamic>> accountStatus;
  final List<Map<String, dynamic>> catalogItems, scheduleItems;
  final Map<String, dynamic> revisionStatus;
  factory TrialSnapshot.fromResponses(
    dynamic catalog,
    dynamic controls,
    dynamic schedules, [
    dynamic oauth,
    dynamic revisionStatus,
  ]) {
    int count(dynamic value) => value is List
        ? value.length
        : value is Map
        ? value.length
        : value is num
        ? value.toInt()
        : 0;
    dynamic field(dynamic value, String key, [String? alternate]) {
      if (value is List) return value;
      if (value is Map) {
        return value[key] ?? (alternate == null ? null : value[alternate]);
      }
      return null;
    }

    final List<Map<String, dynamic>> catalogItems = catalog is List
        ? catalog
              .whereType<Map>()
              .map((Map m) => Map<String, dynamic>.from(m))
              .toList()
        : <Map<String, dynamic>>[];
    final dynamic scheduleData =
        field(schedules, 'entries', 'items') ??
        field(schedules, 'schedules') ??
        field(schedules, 'data');
    final List<Map<String, dynamic>> scheduleItems = scheduleData is List
        ? scheduleData
              .whereType<Map>()
              .map((Map m) => Map<String, dynamic>.from(m))
              .toList()
        : <Map<String, dynamic>>[];
    final dynamic accountData = oauth is Map ? oauth['accounts'] : null;
    final List<Map<String, dynamic>> statuses = accountData is List
        ? accountData
              .whereType<Map>()
              .map((Map m) => Map<String, dynamic>.from(m))
              .toList()
        : <Map<String, dynamic>>[];
    return TrialSnapshot(
      reels: count(
        field(catalog, 'items', 'reels') ?? field(catalog, 'data') ?? catalog,
      ),
      accounts: count(
        field(controls, 'accounts', 'controls') ?? field(controls, 'data'),
      ),
      schedules: count(
        field(schedules, 'entries', 'items') ??
            field(schedules, 'schedules') ??
            field(schedules, 'data'),
      ),
      accountStatus: statuses,
      catalogItems: catalogItems,
      scheduleItems: scheduleItems,
      revisionStatus: revisionStatus is Map
          ? Map<String, dynamic>.from(revisionStatus)
          : const <String, dynamic>{},
    );
  }
}

const List<String> gabeProvisionedAccounts = <String>[
  '@barcrawls.arizona',
  '@barcrawling',
];

/// Role scope is independent from the optional compact/full presentation.
TrialSnapshot scopeSnapshotForRole(TrialSnapshot source, String? role) {
  if (role != 'gabe') return source;
  final reels = source.catalogItems
      .where((item) => gabeProvisionedAccounts.contains(item['account']))
      .toList();
  final schedules = source.scheduleItems
      .where((item) => gabeProvisionedAccounts.contains(item['account']))
      .toList();
  final accounts = source.accountStatus
      .where((item) => gabeProvisionedAccounts.contains(item['account']))
      .toList();
  return TrialSnapshot(
    reels: reels.length,
    accounts: accounts.length,
    schedules: schedules.length,
    accountStatus: accounts,
    catalogItems: reels,
    scheduleItems: schedules,
    revisionStatus: source.revisionStatus,
  );
}

// ---------------------------------------------------------------------------
// TIME
//
// Every time in this product is Phoenix wall clock. Arizona does not observe
// daylight saving, so the offset is a constant and no timezone package is
// pulled in to state it.
// ---------------------------------------------------------------------------

const Duration phoenixOffset = Duration(hours: -7);

/// The wall clock, as a seam. Production reads the device clock. Tests
/// substitute a fixed instant so a rendered screen is byte-stable and a
/// calendar or freshness assertion does not depend on the day it is run.
DateTime Function() trialNow = DateTime.now;

DateTime phoenixNow() => trialNow().toUtc().add(phoenixOffset);

/// A wall-clock value for Cupertino's local-time picker. The picker renders
/// a DateTime in the phone's zone, while schedules are intentionally Phoenix
/// wall time; a UTC DateTime would shift the visible minimum for non-Phoenix
/// phones.
DateTime phoenixPickerWallNow() {
  final DateTime wall = phoenixNow();
  return DateTime(wall.year, wall.month, wall.day, wall.hour, wall.minute);
}

DateTime phoenixWall(DateTime instant) => instant.toUtc().add(phoenixOffset);

DateTime phoenixWallToUtc(DateTime wall) => DateTime.utc(
  wall.year,
  wall.month,
  wall.day,
  wall.hour,
  wall.minute,
).subtract(phoenixOffset);

String clock(DateTime instant) {
  return wallClock(phoenixWall(instant));
}

/// Display Phoenix wall time in the operator-facing 12-hour form. Network
/// values remain UTC; this affects presentation only.
String wallClock(DateTime wall) {
  final int hour = wall.hour % 12 == 0 ? 12 : wall.hour % 12;
  final String period = wall.hour < 12 ? 'AM' : 'PM';
  return '$hour:${wall.minute.toString().padLeft(2, '0')} $period';
}

const List<String> _weekdays = <String>[
  'MON',
  'TUE',
  'WED',
  'THU',
  'FRI',
  'SAT',
  'SUN',
];
const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `2h`, `3d`, `12 Sep`. Never a placeholder character.
String ageLabel(String? createdAt) {
  final DateTime? created = DateTime.tryParse(createdAt ?? '');
  if (created == null) return 'Unknown';
  final Duration since = trialNow().toUtc().difference(created.toUtc());
  if (since.inMinutes < 60) return '${since.inMinutes.clamp(0, 59)}m';
  if (since.inHours < 24) return '${since.inHours}h';
  if (since.inDays < 7) return '${since.inDays}d';
  final DateTime wall = phoenixWall(created);
  return '${wall.day} ${_months[wall.month - 1]}';
}

String dayStamp(DateTime instant) {
  final DateTime wall = phoenixWall(instant);
  final DateTime today = phoenixNow();
  final int delta = DateTime(
    wall.year,
    wall.month,
    wall.day,
  ).difference(DateTime(today.year, today.month, today.day)).inDays;
  if (delta == 0) return 'TODAY';
  if (delta == 1) return 'TOMORROW';
  return '${_weekdays[wall.weekday - 1]} ${wall.day} '
      '${_months[wall.month - 1].toUpperCase()}';
}

String durationLabel(num seconds) {
  final int whole = seconds.round();
  return '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// WATCH COVERAGE
//
// Approval is bound to the export hash, so coverage is too. Buckets are whole
// seconds of the asset that have actually been played, which means seeking
// past a section never counts it as watched.
// ---------------------------------------------------------------------------

final Map<String, Set<int>> _watchedSeconds = <String, Set<int>>{};
final Map<String, int> _assetSeconds = <String, int>{};

/// Assets the operator confirmed without ever seeing play, because playback
/// was broken. Coverage is satisfied for them so review can move, and the
/// approve payload carries `watch_observed: false` so a reel nobody could
/// watch is distinguishable from one that was watched.
final Set<String> _watchBypassed = <String>{};
const String _watchCoverageStoreKey = 'trial.watch-coverage.v1';
Timer? _watchCoverageWrite;

Future<void> restoreWatchCoverage() async {
  try {
    final dynamic decoded = jsonDecode(
      (await SharedPreferences.getInstance()).getString(
            _watchCoverageStoreKey,
          ) ??
          '{}',
    );
    if (decoded is! Map) return;
    final dynamic totals = decoded['asset_seconds'];
    final dynamic watched = decoded['watched_seconds'];
    final dynamic bypassed = decoded['watch_bypassed'];
    if (bypassed is List) {
      _watchBypassed.addAll(bypassed.whereType<String>());
    }
    if (totals is Map) {
      for (final MapEntry<dynamic, dynamic> entry in totals.entries) {
        if (entry.key is String && entry.value is num && entry.value > 0) {
          _assetSeconds[entry.key] = entry.value.toInt();
        }
      }
    }
    if (watched is Map) {
      for (final MapEntry<dynamic, dynamic> entry in watched.entries) {
        if (entry.key is! String || entry.value is! List) continue;
        _watchedSeconds[entry.key] = entry.value
            .whereType<num>()
            .map((num second) => second.toInt())
            .where((int second) => second >= 0)
            .toSet();
      }
    }
  } catch (_) {
    // A damaged local receipt must never block review.
  }
}

void _saveWatchCoverageSoon() {
  _watchCoverageWrite?.cancel();
  _watchCoverageWrite = Timer(const Duration(milliseconds: 700), () {
    unawaited(() async {
      try {
        final Map<String, Object> receipt = <String, Object>{
          'watch_bypassed': _watchBypassed.toList()..sort(),
          'asset_seconds': _assetSeconds,
          'watched_seconds': _watchedSeconds.map(
            (String sha, Set<int> seconds) =>
                MapEntry<String, Object>(sha, seconds.toList()..sort()),
          ),
        };
        await (await SharedPreferences.getInstance()).setString(
          _watchCoverageStoreKey,
          jsonEncode(receipt),
        );
      } catch (_) {
        // Playback and review still work when local persistence is unavailable.
      }
    }());
  });
}

void recordWatched(String sha, int second, int total) {
  if (sha.isEmpty || total <= 0) return;
  _assetSeconds[sha] = total;
  if ((_watchedSeconds[sha] ??= <int>{}).add(second)) {
    _saveWatchCoverageSoon();
  }
}

double coverageFor(String sha) {
  final int total = _assetSeconds[sha] ?? 0;
  if (total <= 0) return 0;
  return ((_watchedSeconds[sha]?.length ?? 0) / total).clamp(0, 1).toDouble();
}

void clearCoverage(String sha) {
  _watchedSeconds.remove(sha);
  _assetSeconds.remove(sha);
  _watchBypassed.remove(sha);
  _saveWatchCoverageSoon();
}

/// The operator could not watch this reel because its preview would not play,
/// and said so explicitly. Review is unblocked; the receipt records that the
/// watch was never observed.
void markWatchBypassed(String sha) {
  if (sha.isEmpty) return;
  _watchBypassed.add(sha);
  markWatched(sha, 1);
}

bool watchBypassed(String sha) => _watchBypassed.contains(sha);

/// Drops every in-memory watch receipt. The store is process-global, so a
/// test that does not start from nothing is testing the previous test.
void resetWatchCoverage() {
  _watchedSeconds.clear();
  _assetSeconds.clear();
  _watchBypassed.clear();
}

void markWatched(String sha, int total) {
  if (sha.isEmpty || total <= 0) return;
  _assetSeconds[sha] = total;
  _watchedSeconds[sha] = <int>{
    for (int second = 0; second < total; second++) second,
  };
  _saveWatchCoverageSoon();
}

const double coverageGate = 0.8;

bool coverageMet(Map<String, dynamic> item) =>
    coverageFor('${item['sha256']}') >= coverageGate;

// ---------------------------------------------------------------------------
// ROW FAILURES
//
// A failure about one reel is part of that reel's state, not a message that
// erases itself. Keyed by id and sha so a reload does not lose it and a new
// export does not inherit the old export's failure.
// ---------------------------------------------------------------------------

/// The three answers to "does this device have a session on this gateway?".
@immutable
class _Session {
  const _Session.authed(String this.role) : unreachable = false;
  const _Session.unauthed() : role = null, unreachable = false;
  const _Session.unreachable() : role = null, unreachable = true;
  final String? role;
  final bool unreachable;
}

class RowFailures {
  static const String preferenceName = 'trial.row.failures.v1';
  final Map<String, String> _causes = <String, String>{};

  static String keyFor(Map<String, dynamic> item) =>
      '${item['id']}/${item['sha256']}';

  String? causeFor(Map<String, dynamic> item) => _causes[keyFor(item)];

  bool get isEmpty => _causes.isEmpty;

  Future<void> load() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      final dynamic decoded = jsonDecode(p.getString(preferenceName) ?? '{}');
      if (decoded is Map) {
        _causes.clear();
        decoded.forEach((dynamic k, dynamic v) => _causes['$k'] = '$v');
      }
    } catch (_) {
      // A missing or unreadable store is an empty store, never a crash.
    }
  }

  Future<void> record(Map<String, dynamic> item, String cause) async {
    _causes[keyFor(item)] = cause;
    await _save();
  }

  Future<void> clear(Map<String, dynamic> item) async {
    if (_causes.remove(keyFor(item)) != null) await _save();
  }

  Future<void> _save() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setString(preferenceName, jsonEncode(_causes));
    } catch (_) {
      // Losing the cache is survivable; losing the running app is not.
    }
  }
}

/// Fallback causes when the server sends nothing readable.
String failureCause(Object error, String action) {
  final String raw = error is HttpException ? error.message : '$error';
  final String text = raw.replaceFirst('HttpException: ', '').trim();
  if (text.isNotEmpty && text.length < 240) return text;
  return switch (action) {
    'approve' => 'Approve failed. The account is paused.',
    'schedule' => 'Schedule failed. That time is already taken.',
    'post' => 'Post failed. Instagram rejected the upload.',
    _ => 'The server did not answer.',
  };
}

// ---------------------------------------------------------------------------
// STATE MARKS
// ---------------------------------------------------------------------------

@immutable
class ReelState {
  const ReelState(
    this.caps,
    this.bar,
    this.label, {
    this.width = 3,
    this.hollow = false,
    this.posting = false,
  });
  final String caps;
  final Color bar, label;
  final double width;
  final bool hollow, posting;
}

ReelState _scheduledState(DateTime? due) => ReelState(
  due == null ? 'SCHEDULED' : 'SCHEDULED ${clock(due)}',
  Con.hold,
  Con.holdBright,
  hollow: true,
);

ReelState reelStateFor(Map<String, dynamic> item, {String? failure}) {
  if (failure != null) {
    return const ReelState('FAILED', Con.fail, Con.failBright, width: 4);
  }
  // Parsed lazily: only the 'Scheduled' arm below reads it, and this runs for
  // every visible row on every build.
  DateTime? due() {
    final dynamic schedule = item['schedule_detail'] ?? item['approval'];
    return schedule is Map
        ? DateTime.tryParse('${schedule['scheduled_at']}')
        : null;
  }

  return switch (reelLifecycle(item)) {
    'Published' => const ReelState('PUBLISHED', Con.ink3, Con.ink3),
    'Publishing' => const ReelState(
      'POSTING',
      Con.signal,
      Con.signalBright,
      posting: true,
    ),
    'Needs attention' => const ReelState(
      'FAILED',
      Con.fail,
      Con.failBright,
      width: 4,
    ),
    'On hold' => const ReelState('HELD', Con.wait, Con.wait),
    'Scheduled' => _scheduledState(due()),
    'Approved' => const ReelState('APPROVED', Con.hold, Con.holdBright),
    'Revision queued' => const ReelState('CHANGES', Con.wait, Con.wait),
    'Scrapped' => const ReelState('SCRAPPED', Con.ink3, Con.ink3, hollow: true),
    _ => const ReelState('REVIEW', Con.signal, Con.signalBright),
  };
}

/// Needs you: ready for review, changes requested, or failed. On this product
/// the reviewer and the creator are the same person, so a returned reel is
/// still his work and still belongs in the queue.
bool needsYou(Map<String, dynamic> item, RowFailures failures) {
  if (failures.causeFor(item) != null) return true;
  final String state = reelLifecycle(item);
  return (state == 'For review' && reelCanReceiveNewIntent(item)) ||
      state == 'Revision queued' ||
      state == 'Needs attention';
}

/// Scrapping is an existing reversible server action, never a media delete.
bool canScrapReel(Map<String, dynamic> item) => const <String>[
  'ready_for_review',
  'changes_requested',
  'earlier_version',
  'superseded',
].contains('${item['status']}');

bool canRestoreReel(Map<String, dynamic> item) => item['status'] == 'scrapped';

/// Per-field emptiness. A missing field says what is missing or is omitted; it
/// never renders punctuation.
String? optional(dynamic value) {
  final String text = '$value';
  return value == null || text.isEmpty ? null : text;
}

/// A displayable string from any shape `caption` has been seen to take on
/// the wire. Most reels carry a plain string. Newer "captioned successor"
/// rows carry either a single `{text, style}` object or a list of timed
/// segments `[{start, end, text}, ...]` from the per-segment caption editor.
/// A card that assumed a plain string and hard-cast it (`as String?`) threw
/// on those rows: a `TypeError` mid-build that Flutter's release-mode error
/// widget renders as a blank grey box, which is what a "half-screen"
/// screenshot of this app has actually been.
String captionText(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is Map) return _text(value['text'], '');
  if (value is List) {
    return value
        .whereType<Map>()
        .map((Map segment) => _text(segment['text'], ''))
        .where((String segment) => segment.isNotEmpty)
        .join(' ');
  }
  return '';
}

/// Compiled once. This used to be built inside `firstWords`, which every
/// visible reel row calls on every build.
final RegExp _whitespace = RegExp(r'\s+');

String firstWords(String? caption, int words) {
  final List<String> parts = (caption ?? '')
      .trim()
      .split(_whitespace)
      .where((String w) => w.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '';
  return parts.take(words).join(' ');
}

num? reelSeconds(Map<String, dynamic> item) {
  for (final String key in <String>[
    'duration_seconds',
    'duration',
    'seconds',
    'length_seconds',
  ]) {
    final dynamic value = item[key];
    if (value is num && value > 0) return value;
  }
  return null;
}

String? reelMusic(Map<String, dynamic> item) {
  for (final String key in <String>[
    'music_label',
    'music',
    'song',
    'audio_label',
  ]) {
    final dynamic value = item[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is Map && value['label'] is String) {
      return '${value['label']}';
    }
  }
  return null;
}

String? reelPermalink(Map<String, dynamic> item) {
  final List<dynamic> sources = <dynamic>[
    item,
    item['approval'],
    item['approval'] is Map ? item['approval']['receipt'] : null,
  ];
  for (final dynamic source in sources) {
    if (source is! Map) continue;
    for (final String key in <String>[
      'permalink',
      'post_url',
      'instagram_url',
      'published_url',
    ]) {
      final dynamic value = source[key];
      if (value is String && value.startsWith('http')) return value;
    }
  }
  return null;
}

DateTime? reelPostedAt(Map<String, dynamic> item) {
  final dynamic approval = item['approval'];
  final dynamic receipt = approval is Map ? approval['receipt'] : null;
  for (final dynamic source in <dynamic>[item, approval, receipt]) {
    if (source is! Map) continue;
    for (final String key in <String>[
      'finished_at',
      'posted_at',
      'published_at',
    ]) {
      final DateTime? value = DateTime.tryParse('${source[key] ?? ''}');
      if (value != null) return value;
    }
  }
  return null;
}

/// A receipt is shown only when the catalogue contains provider-returned
/// evidence. A published state on its own never gets a fabricated timestamp
/// or link.
String? reelReceiptSummary(Map<String, dynamic> item) {
  if (reelLifecycle(item) != 'Published') return null;
  final DateTime? postedAt = reelPostedAt(item);
  if (postedAt != null) {
    return 'Posted ${dayStamp(postedAt)} at ${clock(postedAt)}';
  }
  if (reelPermalink(item) != null) return 'Instagram posting receipt recorded';
  return null;
}

int? reelRating(Map<String, dynamic> item) =>
    item['owner_rating'] is num ? (item['owner_rating'] as num).toInt() : null;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TrialReelsApp());
}

class TrialReelsApp extends StatelessWidget {
  const TrialReelsApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Content Doctor',
    debugShowCheckedModeBanner: false,
    theme: studioTheme(),
    home: const NativeHome(),
  );
}

class NativeHome extends StatefulWidget {
  const NativeHome({super.key});
  @override
  State<NativeHome> createState() => _NativeHomeState();
}

const List<String> tabLabels = <String>[
  'Review',
  'Schedule',
  'Studio',
  'Results',
  'Accounts',
  'Team',
];
const List<int> navTabs = <int>[0, 1, 2, 3, 4, 5];

const List<String> stageFilters = <String>[
  'All stages',
  'Review only',
  'Changes requested',
  'Approved',
  'Scheduled',
  'Published',
  'Needs attention',
  'Scrapped',
];
const List<String> ratingFilters = <String>[
  'Any',
  '4 and up',
  '5 only',
  'Unrated',
];
const List<String> orderFilters = <String>[
  'Newest first',
  'Oldest first',
  'Highest rated',
  'Soonest scheduled',
];

class _NativeHomeState extends State<NativeHome>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  int tab = 0;
  int segment = 0;
  String scope = 'all';
  String stageFilter = stageFilters.first;
  String ratingFilter = ratingFilters.first;
  String orderFilter = orderFilters.first;
  bool searching = false;
  String query = '';
  int scheduleSegment = 0;
  DateTime? _calendarDay;

  String host = defaultHost;
  String? _sessionRole;

  /// True when the last attempt to read the session did not get an answer at
  /// all. Distinct from having no credential.
  bool _sessionUnreachable = false;
  bool get _gabeScope => _sessionRole == 'gabe';
  TrialSnapshot? snapshot;
  Object? error;
  bool loading = true;
  DateTime? lastFetch;
  int _loadGeneration = 0;
  int _loadSeconds = 0;
  bool _loadGaveUp = false;
  int _sessionEpoch = 0;
  Timer? _loadTicker;
  Timer? _runtimeConfigPoller;
  bool _oauthInFlight = false;
  // OAuth return-path state. The app registers the `contentdoctor://` scheme
  // (Info.plist); when Instagram finishes in the browser, the server bounces
  // app-initiated flows back to contentdoctor://oauth/return and the link
  // below resumes the flow instead of stranding the user in the browser.
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _appLinksSub;
  Uri? _lastOAuthUri;
  String? _oauthAccount;
  Timer? _oauthPollTimer;
  int _oauthPollTicks = 0;
  RuntimeConfig _runtimeConfig = RuntimeConfig.defaults();

  /// One-shot guard for first-run onboarding. The check runs once per launch,
  /// after a catalog actually arrives, not in initState: a tour thrown over a
  /// spinner or a sign-in wall teaches nothing.
  bool _tutorialChecked = false;

  final RowFailures _failures = RowFailures();
  final Map<String, String> _revisionDrafts = <String, String>{};
  final Map<String, Map<String, dynamic>> _revisionRequests =
      <String, Map<String, dynamic>>{};
  final TextEditingController _search = TextEditingController();

  String? _stripMessage;
  final Map<String, int> _approvalMotion = <String, int>{};
  VoidCallback? _stripUndo;
  Timer? _stripTimer;
  // Built in initState, not lazily. A lazy `late final` controller is first
  // constructed by dispose() when nothing ever refreshed, and creating a
  // ticker on a deactivated element throws.
  late final AnimationController _refreshBar;

  @override
  void initState() {
    super.initState();
    _refreshBar = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    WidgetsBinding.instance.addObserver(this);
    // AppLinks needs the native platform channel. In Linux widget tests
    // OAuth return deep links (contentdoctor://oauth/return).
    // The native AppLinks plugin is mocked in widget tests (see
    // test/support/console_harness.dart); on a real device it works fully.
    _appLinksSub = _appLinks.uriLinkStream.listen(_onOAuthReturn);
    // Cold start through the return link (the app was not running when the
    // browser bounced back).
    _appLinks.getInitialLink().then((Uri? uri) {
      if (uri != null) _onOAuthReturn(uri);
    });
    _failures.load().then((_) {
      if (mounted && !_failures.isEmpty) setState(() {});
    });
    restoreWatchCoverage().then((_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadTicker?.cancel();
    _runtimeConfigPoller?.cancel();
    _stripTimer?.cancel();
    _oauthPollTimer?.cancel();
    _appLinksSub?.cancel();
    _refreshBar.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _oauthInFlight) {
      _startOAuthReturnPoll();
    }
  }

  /// Handles the `contentdoctor://oauth/return` bounce from the OAuth
  /// callback. The server only sends this for app-initiated flows; the web
  /// flow keeps its connection.html landing page.
  void _onOAuthReturn(Uri uri) {
    if (uri.scheme != 'contentdoctor' ||
        uri.host != 'oauth' ||
        uri.path != '/return') {
      return;
    }
    if (!mounted) return;
    _oauthPollTimer?.cancel();
    _oauthPollTimer = null;
    final String outcome = uri.queryParameters['oauth'] ?? '';
    setState(() {
      _oauthInFlight = false;
      _oauthAccount = null;
    });
    _load();
    if (outcome == 'connected' || outcome == 'insights_connected') {
      _strip('Instagram connected. Welcome back.');
    } else {
      final String msg = (uri.queryParameters['message'] ?? '').trim();
      _strip(msg.isNotEmpty ? msg : 'Instagram connection did not complete.');
    }
  }

  /// The user is back from the browser but the token exchange may still be in
  /// flight server-side. Poll the gateway briefly instead of checking once
  /// and giving up.
  void _startOAuthReturnPoll() {
    _oauthPollTimer?.cancel();
    _oauthPollTicks = 0;
    _strip('Waiting for Instagram…');
    _oauthPollTimer =
        Timer.periodic(const Duration(seconds: 3), (Timer t) async {
      _oauthPollTicks++;
      await _load();
      final bool done = _oauthAccountConnected();
      if (done || _oauthPollTicks >= 10) {
        t.cancel();
        _oauthPollTimer = null;
        if (!mounted) return;
        setState(() {
          _oauthInFlight = false;
          if (done) _oauthAccount = null;
        });
        _strip(
            done ? 'Instagram connected.' : 'Still not connected. Try again.');
      }
    });
  }

  /// True when the account this OAuth flow was started for now reports a
  /// verified capability.
  bool _oauthAccountConnected() {
    final String? account = _oauthAccount;
    final TrialSnapshot? s = snapshot;
    if (account == null || s == null) return false;
    return s.accountStatus.any(
      (Map<String, dynamic> i) =>
          _text(i['account'], '') == account &&
          (_capability(i, 'publishing') == 'verified' ||
              _capability(i, 'insights') == 'verified'),
    );
  }

  // -------------------------------------------------------------------------
  // LOADING
  // -------------------------------------------------------------------------

  /// Why the app has no session. "No credential" and "could not ask" are not
  /// the same answer, and collapsing them into one is what sends Zion hunting
  /// for credentials that were never the problem.
  Future<_Session> _readSessionRole(String currentHost) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final String? token = await TrialCredentials.read(currentHost);
      if (token == null || token.isEmpty) {
        return const _Session.unauthed();
      }
      final HttpClientRequest request = await client.getUrl(
        Uri.parse('$currentHost/trial-auth'),
      );
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final dynamic data = jsonDecode(
        await utf8.decoder
            .bind(response)
            .join()
            .timeout(const Duration(seconds: 15)),
      );
      if (response.statusCode == 200 && data is Map) {
        final dynamic role = data['role'];
        return role is String && role.isNotEmpty
            ? _Session.authed(role)
            : const _Session.unauthed();
      }
      // 401 and 403 are the gateway saying no. Anything else is the gateway
      // not answering the question.
      if (response.statusCode == 401 || response.statusCode == 403) {
        return const _Session.unauthed();
      }
      return const _Session.unreachable();
    } on Object {
      // A timeout, a socket error, a TLS failure or a 500 used to collapse
      // into the same null that means "no credential", and the shell then
      // rendered "Session locked / Unlock".
      return const _Session.unreachable();
    } finally {
      client.close(force: true);
    }
  }

  void _startLoadClock() {
    _loadSeconds = 0;
    _loadGaveUp = false;
    _loadTicker?.cancel();
    _loadTicker = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) return t.cancel();
      setState(() {
        _loadSeconds = t.tick;
        if (t.tick >= 15 && snapshot == null) _loadGaveUp = true;
      });
    });
  }

  Future<void> _load() async {
    final int generation = ++_loadGeneration;
    String selected = defaultHost;
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      selected = trialGatewayHost(p.getString(hostPrefKey) ?? defaultHost);
    } catch (_) {}
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      if (selected != host) _sessionEpoch++;
      host = selected;
      loading = true;
      error = null;
    });
    _startLoadClock();
    if (snapshot != null && !MediaQuery.disableAnimationsOf(context)) {
      _refreshBar.forward(from: 0);
    }
    try {
      final _Session session = await _readSessionRole(selected);
      if (!mounted || generation != _loadGeneration) return;
      final String? role = session.role;
      if (role == null) {
        if (mounted && generation == _loadGeneration) {
          _loadTicker?.cancel();
          setState(() {
            if (_sessionRole != null) _sessionEpoch++;
            _sessionRole = null;
            _sessionUnreachable = session.unreachable;
            snapshot = null;
            loading = false;
          });
        }
        return;
      }
      if (_sessionRole != role) _sessionEpoch++;
      _sessionRole = role;
      _sessionUnreachable = false;
      if (_gabeScope && !gabeProvisionedAccounts.contains(scope)) {
        scope = gabeProvisionedAccounts.first;
      }
      _refreshRuntimeConfig(selected, generation);
      final TrialApi api = TrialApi(selected);
      final dynamic catalog = await api.getJson('/reels/catalog');
      final TrialSnapshot firstPaint = TrialSnapshot.fromResponses(
        catalog,
        const <String, dynamic>{},
        const <String, dynamic>{},
        const <String, dynamic>{},
      );
      if (mounted && generation == _loadGeneration) {
        setState(() {
          snapshot = firstPaint;
          loading = false;
          lastFetch = trialNow();
        });
        unawaited(_maybeShowTutorial());
      }
      try {
        final TrialSnapshot result = await api.snapshotFromCatalog(catalog);
        if (mounted && generation == _loadGeneration) {
          setState(() {
            snapshot = result;
            lastFetch = trialNow();
          });
        }
      } on Object catch (e) {
        if (mounted && generation == _loadGeneration) {
          setState(() => error = e);
        }
      }
    } on Object catch (e) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          loading = false;
          error = e;
        });
      }
    } finally {
      if (generation == _loadGeneration) _loadTicker?.cancel();
    }
  }

  /// Shows the tour to a genuinely new user, once.
  ///
  /// `TutorialPreferences.shouldShowTutorial()` was written to gate exactly
  /// this and was never called by anything, so the tour a new user is
  /// promised in its own Welcome step was only reachable by hunting for
  /// Accounts → Replay tutorial. The hook is the first successful catalog
  /// load rather than app start, because that is the first moment there is a
  /// signed-in workspace for the tour to describe.
  ///
  /// It stays off the screen for anyone who already saw it: the persisted
  /// flag is the only thing that decides, and closing the tour by any route
  /// sets it.
  Future<void> _maybeShowTutorial() async {
    if (_tutorialChecked) return;
    _tutorialChecked = true;
    if (!await TutorialPreferences.shouldShowTutorial()) return;
    // A route pushed while the operator is already inside an editor or a
    // reel would steal the screen out from under them.
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    await _openTutorial();
  }

  /// Opens the tour and records that it has been seen. Skip, Start reviewing
  /// and a back gesture all count: a user who dismissed it is not shown it
  /// again unasked. Replay uses this too, so replaying is always safe.
  Future<void> _openTutorial() async {
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        fullscreenDialog: true,
        builder: (BuildContext pageContext) =>
            TutorialPage(onFinish: () => Navigator.of(pageContext).pop()),
      ),
    );
    await TutorialPreferences.completeTutorial();
  }

  Future<void> _refreshRuntimeConfig(String currentHost, int generation) async {
    final String account = scope == 'all' ? '@zionboggan' : scope;
    final RuntimeConfigRepository repository = RuntimeConfigRepository(
      () => TrialApi(currentHost).getJson(
        '/reels/app-config?account=${Uri.encodeQueryComponent(account)}',
      ),
    );
    final RuntimeConfig config = await repository.load();
    if (!mounted || generation != _loadGeneration) return;
    if (config.version != _runtimeConfig.version ||
        config.sections.toString() != _runtimeConfig.sections.toString() ||
        config.copy.toString() != _runtimeConfig.copy.toString() ||
        config.features.toString() != _runtimeConfig.features.toString()) {
      setState(() {
        _runtimeConfig = config;
        _normalizeRuntimeTab();
      });
    }
    _scheduleRuntimeConfigPoller(currentHost, generation);
  }

  void _scheduleRuntimeConfigPoller(String currentHost, int generation) {
    _runtimeConfigPoller?.cancel();
    _runtimeConfigPoller = Timer.periodic(
      _runtimeConfig.refreshFor(_sectionForTab(tab)),
      (_) {
        if (mounted && generation == _loadGeneration) {
          _refreshRuntimeConfig(currentHost, generation);
        }
      },
    );
  }

  // -------------------------------------------------------------------------
  // STATUS CHANNEL
  // -------------------------------------------------------------------------

  String _runtimeText(String key, String fallback) =>
      _runtimeConfig.text(key) ?? fallback;

  String _sectionForTab(int value) => switch (value) {
    1 => 'schedule',
    2 => 'studio',
    3 => 'results',
    4 => 'accounts',
    5 => 'team',
    6 || 7 => 'team',
    _ => 'review',
  };

  bool _featureEnabled(String feature) => _runtimeConfig.feature(feature);

  void _normalizeRuntimeTab() {
    if ((tab == 6 || tab == 7) && !_featureEnabled('dm_workspace')) {
      tab = 0;
    }
    final List<int> active = _activeRuntimeTabs();
    if (active.isNotEmpty && !active.contains(tab)) tab = active.first;
  }

  void _strip(String message, {VoidCallback? undo}) {
    _stripTimer?.cancel();
    setState(() {
      _stripMessage = message;
      _stripUndo = undo;
    });
    _stripTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      setState(() {
        _stripMessage = null;
        _stripUndo = null;
      });
    });
  }

  void _clearStrip() {
    _stripTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _stripMessage = null;
      _stripUndo = null;
    });
  }

  // -------------------------------------------------------------------------
  // WRITES. Every payload and guard below is unchanged from the shipped
  // client; only what the operator sees around them is new.
  // -------------------------------------------------------------------------

  Future<bool> _approve(Map<String, dynamic> item) async {
    try {
      await TrialApi(host).approveReview(item);
      await _failures.clear(item);
      _strip('Approved');
      final String id = '${item['id']}';
      if (mounted && tab == 0 && segment == 0 && !CdMotion.reduced(context)) {
        setState(() => _approvalMotion[id] = 1);
        await Future<void>.delayed(const Duration(milliseconds: 320));
        if (mounted) setState(() => _approvalMotion[id] = 2);
        await Future<void>.delayed(CdMotion.std);
      }
      await _load();
      if (mounted) setState(() => _approvalMotion.remove(id));
      return true;
    } on Object catch (e) {
      await _failures.record(item, failureCause(e, 'approve'));
      if (mounted) setState(() {});
      return false;
    }
  }

  Future<bool> _scheduleAt(
    Map<String, dynamic> item,
    DateTime wall, {
    bool move = false,
  }) async {
    final DateTime due = phoenixWallToUtc(wall);
    try {
      if (move) {
        await TrialApi(host).reschedule(item, due);
      } else {
        await TrialApi(host).schedule(item, due);
      }
      await _failures.clear(item);
      _strip(
        'Scheduled for ${_weekdays[wall.weekday - 1].substring(0, 1)}'
        '${_weekdays[wall.weekday - 1].substring(1).toLowerCase()} '
        '${wallClock(wall)}',
        undo: () {
          _clearStrip();
          _cancel(item);
        },
      );
      await _load();
      return true;
    } on Object catch (e) {
      await _failures.record(item, failureCause(e, 'schedule'));
      if (mounted) setState(() {});
      return false;
    }
  }

  Future<bool> _cancel(Map<String, dynamic> item) async {
    final DateTime? previous = DateTime.tryParse(
      '${(item['schedule_detail'] ?? item['approval'] ?? const <String, dynamic>{})['scheduled_at']}',
    );
    try {
      await TrialApi(host).cancel(item);
      await _failures.clear(item);
      _strip(
        'Schedule cancelled',
        undo: previous == null
            ? null
            : () {
                _clearStrip();
                _scheduleAt(item, phoenixWall(previous));
              },
      );
      await _load();
      return true;
    } on Object catch (e) {
      await _failures.record(item, failureCause(e, 'schedule'));
      if (mounted) setState(() {});
      return false;
    }
  }

  Future<bool> _scrap(Map<String, dynamic> item) async {
    try {
      await TrialApi(host).scrap(item);
      clearCoverage('${item['sha256']}');
      await _failures.clear(item);
      _strip('Reel scrapped. Media is preserved.');
      await _load();
      return true;
    } on Object catch (e) {
      await _failures.record(item, failureCause(e, 'scrap'));
      if (mounted) setState(() {});
      return false;
    }
  }

  Future<bool> _restore(Map<String, dynamic> item) async {
    try {
      await TrialApi(host).restore(item);
      await _failures.clear(item);
      _strip('Reel restored. It needs a fresh review before posting.');
      await _load();
      return true;
    } on Object catch (e) {
      await _failures.record(item, failureCause(e, 'restore'));
      if (mounted) setState(() {});
      return false;
    }
  }

  Future<ReelWrite> _confirmRestore(Map<String, dynamic> item) async {
    if (!await _confirmSheet(
      'Restore reel',
      'This returns the saved media to review. It will need a fresh review before it can be scheduled or posted.',
      'Restore reel',
    )) {
      return ReelWrite.cancelled;
    }
    return await _restore(item) ? ReelWrite.done : ReelWrite.failed;
  }

  Future<ReelWrite> _confirmPostNow(Map<String, dynamic> item) async {
    if (!await _confirmSheet(
      'Post now',
      'This posts immediately and cannot be recalled.',
      'Post now',
    )) {
      return ReelWrite.cancelled;
    }
    return await _postNow(item) ? ReelWrite.done : ReelWrite.failed;
  }

  Future<ReelWrite> _confirmScrap(Map<String, dynamic> item) async {
    if (!await _confirmSheet(
      'Scrap reel',
      'This removes the reel from review. Its media is preserved and can be restored later.',
      'Scrap reel',
    )) {
      return ReelWrite.cancelled;
    }
    return await _scrap(item) ? ReelWrite.done : ReelWrite.failed;
  }

  /// Irreversible. It advances only on a server-confirmed result, and the row
  /// reads POSTING until the provider says otherwise.
  Future<bool> _postNow(Map<String, dynamic> item) async {
    try {
      await TrialApi(host).postNow(item);
      await _failures.clear(item);
      // The one irreversible action in the product was also the only one with
      // no receipt at all.
      _strip('Posting. The row reads POSTING until the provider confirms.');
      await _load();
      return true;
    } on Object catch (e) {
      await _failures.record(item, failureCause(e, 'post'));
      if (mounted) setState(() {});
      return false;
    }
  }

  Future<void> _rate(Map<String, dynamic> item, int rating) async {
    try {
      await TrialApi(host).postJson('/reels/rate', <String, dynamic>{
        'id': item['id'],
        'sha256': item['sha256'],
        'rating': rating,
      });
      await _load();
    } on Object catch (e) {
      await _failures.record(item, failureCause(e, 'rate'));
      if (mounted) setState(() {});
    }
  }

  /// The caption write keeps the documented `previous_caption` guard. Saving
  /// invalidates the review, so the watch coverage for that hash goes with it.
  Future<void> _saveCaption(Map<String, dynamic> item, String caption) async {
    try {
      await TrialApi(host).postJson('/reels/caption', <String, dynamic>{
        'id': item['id'],
        'sha256': item['sha256'],
        'previous_caption': item['caption'] ?? '',
        'caption': caption,
      });
      clearCoverage('${item['sha256']}');
      await _failures.clear(item);
      _strip('Caption saved. Approval cleared.');
      await _load();
    } on Object catch (e) {
      await _failures.record(item, failureCause(e, 'caption'));
      if (mounted) setState(() {});
    }
  }

  Future<void> _requestChanges(Map<String, dynamic> item, String text) async {
    final String reelId = '${item['id']}';
    try {
      final Map<String, dynamic>? prior = _revisionRequests[reelId];
      final String requestId =
          prior?['text'] == text && prior?['sha256'] == item['sha256']
          ? '${prior!['id']}'
          : 'native-${DateTime.now().microsecondsSinceEpoch}';
      _revisionRequests[reelId] = <String, dynamic>{
        'id': requestId,
        'text': text,
        'sha256': item['sha256'],
      };
      final dynamic receipt = await TrialApi(host)
          .postJson('/trial-message', <String, dynamic>{
            'id': requestId,
            'reel_id': item['id'],
            'reel_sha256': item['sha256'],
            'text':
                'Trial Reel edit request for ${item['title'] ?? item['id']} '
                '[${item['id']}]: $text. Keep posting behind my review.',
          });
      if (receipt is! Map || receipt['intake_verified'] != true) {
        // Not verified is not sent. Do not advance, and do not invite a resend.
        await _failures.record(
          item,
          'Change request not confirmed by intake. '
          'Your request is saved. Do not resend.',
        );
        if (mounted) setState(() {});
        return;
      }
      _revisionDrafts.remove(reelId);
      _revisionRequests.remove(reelId);
      await _failures.clear(item);
      _strip('Sent to revisions');
      await _load();
    } on Object catch (e) {
      await _failures.record(
        item,
        '${failureCause(e, 'revision')} Your request is saved. Do not resend.',
      );
      if (mounted) setState(() {});
    }
  }

  Future<void> _connect(String account, String purpose) async {
    if (_oauthInFlight) return;
    final int sessionEpoch = _sessionEpoch;
    setState(() {
      _oauthInFlight = true;
      _oauthAccount = account;
      _lastOAuthUri = null;
    });
    try {
      final Uri uri = await TrialApi(host).startOAuth(account, purpose);
      if (!mounted || sessionEpoch != _sessionEpoch) return;
      // Kept so the user can copy a Safari link when iOS routes the authorize
      // URL into the Instagram app instead of the browser.
      setState(() => _lastOAuthUri = uri);
      final InstagramConnectionLaunch result = await launchInstagramConnection(
        uri,
      );
      if (!mounted || sessionEpoch != _sessionEpoch) return;
      if (!result.opened) {
        setState(() {
          _oauthInFlight = false;
          _oauthAccount = null;
        });
      }
      _strip(result.message);
    } on Object catch (e) {
      if (mounted && sessionEpoch == _sessionEpoch) {
        setState(() {
          _oauthInFlight = false;
          _oauthAccount = null;
        });
        _strip(failureCause(e, 'connection'));
      }
    }
  }

  // -------------------------------------------------------------------------
  // QUEUE
  // -------------------------------------------------------------------------

  TrialSnapshot? _scopedSource;
  String? _scopedRole;
  TrialSnapshot? _scopedResult;

  /// `scopeSnapshotForRole` is a no-op for the owner, but for a scoped role it
  /// rebuilds three lists and a snapshot. Doing that inside `build()` also gave
  /// the scoped role a brand-new `catalogItems` identity every frame, which is
  /// what `_enriched` below memoises on. `TrialSnapshot` is `@immutable` and is
  /// only ever replaced wholesale by `setState`, so identity is a sound key.
  TrialSnapshot _scopedSnapshot() {
    final TrialSnapshot source = snapshot!;
    if (!identical(_scopedSource, source) ||
        _scopedRole != _sessionRole ||
        _scopedResult == null) {
      _scopedSource = source;
      _scopedRole = _sessionRole;
      _scopedResult = scopeSnapshotForRole(source, _sessionRole);
    }
    return _scopedResult!;
  }

  List<String> _accounts(TrialSnapshot s) => <String>{
    ...s.accountStatus.map((Map<String, dynamic> i) => _text(i['account'], '')),
    ...s.catalogItems.map((Map<String, dynamic> i) => _text(i['account'], '')),
  }.where((String name) => name.isNotEmpty).toList()..sort();

  TrialSnapshot? _enrichedFor;
  List<Map<String, dynamic>>? _enrichedRows;

  /// Catalog rows with their matching schedule attached.
  ///
  /// Two separate costs used to sit here. First, the match was a linear scan of
  /// every schedule for every reel -- O(catalog x schedules) -- and the inner
  /// lazy `where` was walked twice per reel, because `isNotEmpty` stops at the
  /// first hit but `last` always runs to the end. Second, `build()` called this
  /// four to six times per frame (the readout, the revision count, the queue,
  /// the tab-bar badge), so every search keystroke paid for all of it several
  /// times over.
  ///
  /// Now: one pass to index the schedules, one pass over the catalog, and the
  /// result is memoised on the identity of the immutable snapshot it came from.
  /// A record key gives exactly the `==` semantics the three-field comparison
  /// had, and a later schedule still wins, which is what `matches.last` meant.
  List<Map<String, dynamic>> _enriched(TrialSnapshot s) {
    final List<Map<String, dynamic>>? cached = _enrichedRows;
    if (cached != null && identical(_enrichedFor, s)) return cached;
    final Map<(Object?, Object?, Object?), Map<String, dynamic>> bySignature =
        <(Object?, Object?, Object?), Map<String, dynamic>>{};
    for (final Map<String, dynamic> entry in s.scheduleItems) {
      bySignature[(entry['id'], entry['sha256'], entry['account'])] = entry;
    }
    final List<Map<String, dynamic>> rows = s.catalogItems.map((
      Map<String, dynamic> item,
    ) {
      final Map<String, dynamic>? match =
          bySignature[(item['id'], item['sha256'], item['account'])];
      return <String, dynamic>{...item, 'schedule_detail': ?match};
    }).toList();
    _enrichedFor = s;
    _enrichedRows = rows;
    return rows;
  }

  bool _inScope(Map<String, dynamic> item) =>
      scope == 'all' || _text(item['account'], '') == scope;

  bool get _filtersAtDefault =>
      stageFilter == stageFilters.first &&
      ratingFilter == ratingFilters.first &&
      orderFilter == orderFilters.first;

  int _compareCreated(Map<String, dynamic> a, Map<String, dynamic> b) =>
      (DateTime.tryParse(_text(a['created_at'], '')) ??
              DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(
            DateTime.tryParse(_text(b['created_at'], '')) ??
                DateTime.fromMillisecondsSinceEpoch(0),
          );

  List<Map<String, dynamic>> _queue(TrialSnapshot s) {
    final List<Map<String, dynamic>> rows = _enriched(
      s,
    ).where(_inScope).toList();
    Iterable<Map<String, dynamic>> list = segment == 0
        ? rows.where((Map<String, dynamic> i) => needsYou(i, _failures))
        : rows.where(
            (Map<String, dynamic> i) => !const <String>[
              'archived',
              'scrapped',
              'rejected',
            ].contains(i['status']),
          );

    if (query.trim().isNotEmpty) {
      final String needle = query.trim().toLowerCase();
      list = list.where(
        (Map<String, dynamic> i) =>
            '${i['title'] ?? ''}'.toLowerCase().contains(needle) ||
            captionText(i['caption']).toLowerCase().contains(needle),
      );
    }

    list = switch (stageFilter) {
      'Review only' => list.where(
        (Map<String, dynamic> i) => reelLifecycle(i) == 'For review',
      ),
      'Changes requested' => list.where(
        (Map<String, dynamic> i) => reelLifecycle(i) == 'Revision queued',
      ),
      'Approved' => list.where(
        (Map<String, dynamic> i) => reelLifecycle(i) == 'Approved',
      ),
      'Scheduled' => list.where(
        (Map<String, dynamic> i) =>
            const <String>['Scheduled', 'On hold'].contains(reelLifecycle(i)),
      ),
      'Published' => list.where(
        (Map<String, dynamic> i) => reelLifecycle(i) == 'Published',
      ),
      'Needs attention' => list.where(
        (Map<String, dynamic> i) =>
            reelLifecycle(i) == 'Needs attention' ||
            _failures.causeFor(i) != null,
      ),
      'Scrapped' => _enriched(s).where(
        (Map<String, dynamic> i) =>
            _inScope(i) &&
            const <String>[
              'archived',
              'scrapped',
              'rejected',
            ].contains(i['status']),
      ),
      _ => list,
    };

    list = switch (ratingFilter) {
      '4 and up' => list.where(
        (Map<String, dynamic> i) => (reelRating(i) ?? 0) >= 4,
      ),
      '5 only' => list.where((Map<String, dynamic> i) => reelRating(i) == 5),
      'Unrated' => list.where(
        (Map<String, dynamic> i) => reelRating(i) == null,
      ),
      _ => list,
    };

    final List<Map<String, dynamic>> out = list.toList();
    switch (orderFilter) {
      case 'Oldest first':
        out.sort(_compareCreated);
      case 'Highest rated':
        out.sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              (reelRating(b) ?? 0).compareTo(reelRating(a) ?? 0),
        );
      case 'Soonest scheduled':
        out.sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              _scheduleDate(
                a['schedule_detail'] is Map
                    ? Map<String, dynamic>.from(a['schedule_detail'] as Map)
                    : a,
              ).compareTo(
                _scheduleDate(
                  b['schedule_detail'] is Map
                      ? Map<String, dynamic>.from(b['schedule_detail'] as Map)
                      : b,
                ),
              ),
        );
      default:
        out.sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              _compareCreated(b, a),
        );
    }
    return out;
  }

  int _needsYouCount(TrialSnapshot s) => _enriched(s)
      .where(_inScope)
      .where((Map<String, dynamic> i) => needsYou(i, _failures))
      .length;

  int _allCount(TrialSnapshot s) => _enriched(s)
      .where(_inScope)
      .where(
        (Map<String, dynamic> i) => !const <String>[
          'archived',
          'scrapped',
          'rejected',
        ].contains(i['status']),
      )
      .length;

  // -------------------------------------------------------------------------
  // SHELL
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool locked = !loading && _sessionRole == null;
    final TrialSnapshot? s = snapshot == null ? null : _scopedSnapshot();
    final List<int> activeTabs = _activeRuntimeTabs();
    if (activeTabs.isEmpty) activeTabs.addAll(navTabs);
    final int visibleTab = activeTabs.contains(tab) ? tab : activeTabs.first;

    return Scaffold(
      backgroundColor: Con.ground,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: ColoredBox(
          // Paint the full workspace while short lists and tab transitions
          // settle. No outgoing page or iOS surface can expose the system's
          // light backing color underneath it. Keyed so a test can measure
          // the workspace a tab body is given against the one it fills.
          key: const ValueKey<String>('workspace'),
          color: Con.ground,
          // On an iPad the workspace is up to 1366 pt wide, and every bit of
          // that width now belongs to the tab. Build 52 wrapped this in a 704
          // pt ConColumn; that left a phone-width strip of cards in the middle
          // of the glass with 331 pt of dark ground down each side, which is
          // the thing Zion rejected. Each tab adapts itself instead — Review
          // and Accounts into a grid of cards, Schedule into calendar beside
          // queue, Team into roster beside conversation — and each of those
          // adaptations is inert below 704 pt, so the phone is untouched.
          child: locked
              ? _lockedBody()
              : s == null
              ? _firstLoadBody()
              : _TabDeck(
                  // A host, session or scope change is a different set of
                  // reels, not the same set filtered, so it is the one thing
                  // that still throws every tab's state away.
                  key: ValueKey<String>(
                    'workspace-$host-$_sessionEpoch-$scope',
                  ),
                  index: tab,
                  duration: CdMotion.duration(context, CdMotion.screen),
                  curve: CdMotion.out,
                  builder: (int index) => _tabBody(s, index),
                ),
        ),
      ),
      bottomNavigationBar: ConTabBar(
        index: activeTabs.indexOf(visibleTab),
        inert: locked,
        badgeOnFirst: s != null && _needsYouCount(s) > 0,
        onChanged: (int i) => setState(() {
          tab = activeTabs[i];
          searching = false;
          _scheduleRuntimeConfigPoller(host, _loadGeneration);
        }),
        labels: [
          for (final int index in activeTabs)
            _runtimeText(
              'tab.${tabLabels[index].toLowerCase()}',
              tabLabels[index],
            ),
        ],
        icons: [
          for (final int index in activeTabs)
            <Widget>[
              _TabMark(),
              Icon(CupertinoIcons.calendar),
              Icon(CupertinoIcons.slider_horizontal_3),
              Icon(CupertinoIcons.chart_bar),
              Icon(CupertinoIcons.person_2),
              Icon(CupertinoIcons.chat_bubble_2),
            ][index],
        ],
      ),
    );
  }

  List<int> _activeRuntimeTabs() => _runtimeConfig.sections
      .where((String section) {
        if (!_featureEnabled('tab_$section')) return false;
        return switch (section) {
          'results' => _featureEnabled('analytics'),
          'team' => _featureEnabled('crew_chat'),
          _ => true,
        };
      })
      .map(
        (String section) => tabLabels.indexOf(
          '${section[0].toUpperCase()}${section.substring(1)}',
        ),
      )
      .where((int index) => index >= 0)
      .toList();

  // ---------------------------------------------------------------------------
  // CHROME
  //
  // The command bar, the control row and the readout strip are the same four
  // bands, in the same order, with the same paddings and rules as they were
  // when they sat in a fixed Column above the workspace. The only thing that
  // changed is where they live: they are slivers inside the tab body's own
  // scroll view, so they scroll away under the operator's finger and come
  // back when he scrolls to the top.
  //
  // They were holding 227 pt of a 740 pt workspace at text scale 1.0 and
  // 314 pt at 1.5 — permanently, whether or not he was looking at them. At
  // 1.5 that left less than one and a half reel cards on the screen, which is
  // what a "stuck at half screen" screenshot of this app actually is.
  //
  // The conditions below are the conditions the Column used, unchanged, so at
  // scroll offset zero every band is exactly where it was. That is pinned by
  // test/goldens/review_rest_390x844.png.
  // ---------------------------------------------------------------------------

  List<Widget> _chromeSlivers({required bool locked, TrialSnapshot? s}) =>
      <Widget>[
        SliverToBoxAdapter(
          child: _commandBar(locked: locked, snapshot: s),
        ),
        const SliverToBoxAdapter(child: Rule()),
        if (!locked && (tab == 0 || tab == 1 || tab == 3)) ...<Widget>[
          SliverToBoxAdapter(child: _controlRow(s)),
          const SliverToBoxAdapter(child: Rule()),
        ],
        if (!locked && tab < 5) ...<Widget>[
          SliverToBoxAdapter(child: _readout(s)),
          const SliverToBoxAdapter(child: Rule(strong: true)),
        ],
      ];

  /// Team, Inbox and Automations own their scrolling and their own internal
  /// Expanded regions, so their chrome stays fixed above them exactly as it
  /// was. Only the command bar applies on those tabs.
  Widget _panelShell(TrialSnapshot s, Widget panel) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _commandBar(locked: false, snapshot: s),
      const Rule(),
      Expanded(child: panel),
    ],
  );

  Widget _commandBar({required bool locked, TrialSnapshot? snapshot}) => Stack(
    key: const ValueKey<String>('command-bar'),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const TrialMark(size: 26),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        const TextSpan(
                          children: [
                            TextSpan(text: 'Content '),
                            TextSpan(
                              text: 'Doctor',
                              style: TextStyle(color: Con.signalBright),
                            ),
                          ],
                        ),
                        style: Ty.title.copyWith(
                          fontSize: 20,
                          height: 1.15,
                          color: Con.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _runtimeText(
                          'brand.tagline',
                          'Healthy content. Higher reach.',
                        ),
                        style: Ty.meta.copyWith(color: Con.ink2, height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const DoctorAvatar(size: 52),
                if (!locked)
                  ConIconButton(
                    icon: CupertinoIcons.ellipsis,
                    semanticLabel: 'More',
                    onPressed: _overflowSheet,
                  ),
              ],
            ),
            if (!locked) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Account scope',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: snapshot == null
                            ? null
                            : () => _scopeSheet(snapshot),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Con.surface2,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Con.ruleStrong),
                          ),
                          child: Row(
                            children: [
                              const DoctorAvatar(size: 24),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  scope == 'all' ? 'All accounts' : scope,
                                  style: Ty.body.copyWith(color: Con.ink),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                CupertinoIcons.chevron_down,
                                size: 14,
                                color: Con.ink2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConIconButton(
                    icon: CupertinoIcons.search,
                    semanticLabel: 'Search content',
                    onPressed: () => setState(() {
                      tab = 0;
                      searching = true;
                    }),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      if (loading && this.snapshot != null)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 2,
          child: AnimatedBuilder(
            animation: _refreshBar,
            builder: (context, child) => CdMotion.reduced(context)
                ? const ColoredBox(color: Con.signal)
                : FractionallySizedBox(
                    alignment: Alignment(_refreshBar.value * 2 - 1, 0),
                    widthFactor: .3,
                    child: const ColoredBox(color: Con.signal),
                  ),
          ),
        ),
    ],
  );

  Widget _controlRow(TrialSnapshot? s) {
    if (searching) {
      return SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: CupertinoTextField(
                  controller: _search,
                  autofocus: true,
                  placeholder: 'Search titles and captions',
                  placeholderStyle: Ty.label.copyWith(color: Con.ink3),
                  style: Ty.label.copyWith(color: Con.ink),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Con.surface3,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Con.rule),
                  ),
                  onChanged: (String value) => setState(() => query = value),
                ),
              ),
              const SizedBox(width: 8),
              ConButton(
                label: 'Cancel',
                kind: ConButtonKind.ghost,
                onPressed: () => setState(() {
                  searching = false;
                  query = '';
                  _search.clear();
                }),
              ),
            ],
          ),
        ),
      );
    }
    final List<String> labels = switch (tab) {
      1 => <String>['Today', _runtimeText('schedule.heading', 'Upcoming')],
      3 => const <String>['Published', 'Activity'],
      _ => <String>[_runtimeText('review.heading', 'Needs you'), 'All'],
    };
    final List<int> counts = tab == 0 && s != null
        ? <int>[_needsYouCount(s), _allCount(s)]
        : tab == 1 && s != null
        ? <int>[_dueToday(s).length, _upcoming(s).length]
        : <int>[0, 0];
    final int index = tab == 1 ? scheduleSegment : segment;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: ConSegmented(
                labels: labels,
                counts: counts,
                index: index,
                onChanged: (int i) => setState(() {
                  if (tab == 1) {
                    scheduleSegment = i;
                    _calendarDay = null;
                  } else {
                    segment = i;
                  }
                }),
              ),
            ),
            if (tab == 0) ...<Widget>[
              const SizedBox(width: 4),
              ConIconButton(
                icon: CupertinoIcons.line_horizontal_3_decrease,
                semanticLabel: 'Filter and sort',
                bordered: true,
                marked: !_filtersAtDefault,
                onPressed: _filterSheet,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // READOUT
  //
  // Readouts do not accept input. The one exception is FAILED above zero: a
  // failure the operator cannot reach in one tap is a failure the product hid.
  // -------------------------------------------------------------------------

  List<Map<String, dynamic>> _scheduleRows(TrialSnapshot s) =>
      s.scheduleItems
          .where(
            (Map<String, dynamic> item) =>
                !const <String>[
                  'cancelled',
                  'invalidated',
                  'published',
                ].contains(item['state']) &&
                (scope == 'all' || item['account'] == scope),
          )
          .toList()
        ..sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              _scheduleDate(a).compareTo(_scheduleDate(b)),
        );

  List<Map<String, dynamic>> _dueToday(TrialSnapshot s) =>
      _scheduleRows(s).where((Map<String, dynamic> item) {
        final DateTime due = _scheduleDate(item);
        return due.year != 9999 && dayStamp(due) == 'TODAY';
      }).toList();

  List<Map<String, dynamic>> _upcoming(TrialSnapshot s) =>
      _scheduleRows(s).where((Map<String, dynamic> item) {
        final DateTime due = _scheduleDate(item);
        return due.year == 9999 || dayStamp(due) != 'TODAY';
      }).toList();

  int _revisionCount(TrialSnapshot s) => _enriched(s)
      .where(_inScope)
      .where((Map<String, dynamic> i) => reelLifecycle(i) == 'Revision queued')
      .length;

  Widget _readout(TrialSnapshot? s) {
    final List<Widget> parts = <Widget>[];
    void pair(String label, String value, {Color? tone, VoidCallback? onTap}) {
      if (parts.isNotEmpty) {
        parts.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Caps('·', color: Con.ink3),
          ),
        );
      }
      final Widget content = Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Caps(label, color: tone ?? Con.ink2),
          const SizedBox(width: 6),
          if (int.tryParse(value) case final int count)
            CdAnimatedCount(
              value: count,
              style: Ty.caps.copyWith(color: tone ?? Con.ink),
            )
          else
            Caps(value, color: tone ?? Con.ink),
        ],
      );
      parts.add(
        onTap == null
            ? content
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: content,
              ),
      );
    }

    if (s == null) {
      parts.add(
        Caps(
          _loadGaveUp
              ? 'COULD NOT LOAD'
              : _loadSeconds >= 4
              ? 'STILL LOADING ${_loadSeconds}S'
              : 'LOADING',
        ),
      );
    } else if (error != null && lastFetch != null) {
      parts.add(
        Caps(
          'OFFLINE. SHOWING DATA FROM ${clock(lastFetch!)}',
          color: Con.wait,
        ),
      );
    } else {
      switch (tab) {
        case 1:
          pair('QUEUED', '${_scheduleRows(s).length}');
          pair('DUE TODAY', '${_dueToday(s).length}');
          pair(
            'HELD',
            '${_scheduleRows(s).where((Map<String, dynamic> i) => i['held'] == true || i['state'] == 'paused').length}',
          );
          pair('NEEDS REVISION', '${_revisionCount(s)}');
        case 2:
          pair('ACCOUNTS', '${_accounts(s).length}');
        case 3:
          pair(
            'PUBLISHED',
            '${_enriched(s).where(_inScope).where((Map<String, dynamic> i) => reelLifecycle(i) == 'Published').length}',
          );
          pair('ACCOUNTS', '${_accounts(s).length}');
        case 4:
          pair('ACCOUNTS', '${s.accountStatus.length}');
          pair(
            'CONNECTED',
            '${s.accountStatus.where((Map<String, dynamic> i) => _capability(i, 'publishing') == 'verified').length}',
          );
        default:
          final List<Map<String, dynamic>> rows = _enriched(
            s,
          ).where(_inScope).toList();
          pair(
            'REVIEW',
            '${rows.where((Map<String, dynamic> i) => reelLifecycle(i) == 'For review').length}',
          );
          pair(
            'CHANGES',
            '${rows.where((Map<String, dynamic> i) => reelLifecycle(i) == 'Revision queued').length}',
          );
          pair('DUE TODAY', '${_dueToday(s).length}');
          final int revisions = _revisionCount(s);
          pair(
            'NEEDS REVISION',
            '$revisions',
            tone: revisions > 0 ? Con.wait : null,
            onTap: revisions == 0
                ? null
                : () => setState(() {
                    segment = 1;
                    stageFilter = 'Changes requested';
                  }),
          );
      }
      if (lastFetch != null) {
        parts.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Caps('·', color: Con.ink3),
          ),
        );
        parts.add(Caps(clock(lastFetch!), color: Con.ink2));
      }
      if (tab == 0 && !_filtersAtDefault) {
        parts.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Caps('·', color: Con.ink3),
          ),
        );
        parts.add(
          Caps(
            'FILTERED ${<String>[if (stageFilter != stageFilters.first) stageFilter, if (ratingFilter != ratingFilters.first) ratingFilter, if (orderFilter != orderFilters.first) orderFilter].join(', ')}',
            color: Con.signalBright,
          ),
        );
      }
      if (tab == 0 && query.trim().isNotEmpty) {
        parts.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Caps('·', color: Con.ink3),
          ),
        );
        parts.add(Caps('SEARCH ${query.trim()}', color: Con.signalBright));
      }
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 32),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      decoration: BoxDecoration(
        color: Con.surface1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Con.rule),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: parts.where((part) => part is! Padding).toList(),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // BODIES
  // -------------------------------------------------------------------------

  Widget _lockedBody() => CustomScrollView(
    slivers: <Widget>[
      ..._chromeSlivers(locked: true, s: null),
      SliverFillRemaining(hasScrollBody: false, child: _lockedNotice()),
    ],
  );

  /// Off the Tailnet, or through a flapping gateway, the app used to tell Zion
  /// he was signed out and ask him to unlock. He is not signed out; the
  /// gateway did not answer. The existing "No connection … Retry" banner says
  /// that, and the Unlock button stays available underneath because a
  /// credential problem is still possible.
  Widget _lockedNotice() => _sessionUnreachable
      ? Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const TrialMark(size: 40),
                  const SizedBox(height: 16),
                  ConBanner(
                    headline: 'No connection',
                    detail:
                        'The gateway did not answer. You are still signed in '
                        'on this device.',
                    tone: Con.wait,
                    actionLabel: 'Retry',
                    onAction: _load,
                  ),
                  const SizedBox(height: 16),
                  ConButton(
                    label: 'Unlock',
                    kind: ConButtonKind.ghost,
                    height: 48,
                    expand: true,
                    onPressed: _signInSheet,
                  ),
                ],
              ),
            ),
          ),
        )
      : _signedOutNotice();

  Widget _signedOutNotice() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const TrialMark(size: 40),
            const SizedBox(height: 16),
            Text(
              'Content Doctor',
              style: Ty.count.copyWith(color: Con.ink, letterSpacing: -0.44),
            ),
            const SizedBox(height: 24),
            Text('Session locked', style: Ty.title.copyWith(color: Con.ink)),
            const SizedBox(height: 8),
            Text(
              'Unlock to load your reels.',
              textAlign: TextAlign.center,
              style: Ty.body.copyWith(color: Con.ink2),
            ),
            const SizedBox(height: 16),
            ConButton(
              label: 'Unlock',
              kind: ConButtonKind.signalFill,
              height: 48,
              expand: true,
              onPressed: _signInSheet,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _firstLoadBody() => CustomScrollView(
    slivers: <Widget>[
      ..._chromeSlivers(locked: false, s: null),
      if (_loadGaveUp || (error != null && !loading))
        SliverToBoxAdapter(
          child: ConBanner(
            headline: 'Could not load reels',
            detail:
                'The server did not answer. Nothing is cached on this device.',
            actionLabel: 'Retry',
            onAction: _load,
          ),
        )
      else
        SliverList.builder(
          itemCount: 3,
          itemBuilder: (BuildContext context, int index) =>
              const Column(children: <Widget>[ConSkeletonRow(), Rule()]),
        ),
    ],
  );

  Widget _tabBody(TrialSnapshot s, int tab) => switch (tab) {
    1 => _scheduleBody(s),
    2 => _studioBody(s),
    3 => _resultsBody(s),
    4 => _accountsBody(s),
    5 => _panelShell(s, _teamBody()),
    6 => _panelShell(
      s,
      InboxPanel(
        key: ValueKey<String>('inbox-$host-$_sessionEpoch'),
        account: _messageAccount(s),
        getJson: (String path) => TrialApi(host).getJson(path),
        postJson: (String path, Map<String, dynamic> body) =>
            TrialApi(host).postJson(path, body),
        onAutomations: () => setState(() => tab = 7),
      ),
    ),
    7 => _panelShell(
      s,
      AutomationsPanel(
        key: ValueKey<String>('automations-$host-$_sessionEpoch'),
        account: _messageAccount(s),
        getJson: (String path) => TrialApi(host).getJson(path),
        postJson: (String path, Map<String, dynamic> body) =>
            TrialApi(host).postJson(path, body),
      ),
    ),
    _ => _reviewBody(s),
  };

  String _messageAccount(TrialSnapshot s) {
    if (scope != 'all') return scope;
    final List<String> accounts = _accounts(s);
    if (!_gabeScope && accounts.contains('@zionboggan')) return '@zionboggan';
    return accounts.isEmpty ? '' : accounts.first;
  }

  // Team talks to the durable queue, not to the reel catalogue, so it does
  // not take a snapshot. The panel is handed the shell's authenticated
  // transport rather than a credential, and the lane it opens is whatever the
  // account scope is set to. 'all' passes an empty lane and the backend picks
  // the default lane for the signed in role.
  Widget _teamBody() => TeamPanel(
    account: scope == 'all' ? '' : scope,
    getJson: (String path) => TrialApi(host).getJson(path),
    postJson: (String path, Map<String, dynamic> body) =>
        TrialApi(host).postJson(path, body),
  );

  List<Widget> _leadingSlivers() => <Widget>[
    if (error != null && lastFetch != null)
      SliverToBoxAdapter(
        child: ConBanner(
          headline: 'No connection',
          detail:
              'Showing data from ${clock(lastFetch!)}. Reconnect before making changes.',
          tone: Con.wait,
          actionLabel: 'Retry',
          onAction: _load,
        ),
      ),
    if (_stripMessage != null)
      SliverToBoxAdapter(
        child: ConStatusStrip(message: _stripMessage!, onUndo: _stripUndo),
      ),
  ];

  Widget _reviewBody(TrialSnapshot s) {
    final List<Map<String, dynamic>> rows = _queue(s);
    // How many cards sit side by side. One on every iPhone and every Split
    // View pane, which is the list that shipped; two or three on an iPad,
    // which is what the width is for.
    final int columns = SandLayout.columnsFor(MediaQuery.sizeOf(context).width);
    final bool grouped =
        scope == 'all' &&
        rows.isNotEmpty &&
        (segment == 0 || stageFilter == stageFilters.first);

    final List<Widget> slivers = <Widget>[..._leadingSlivers()];
    if (rows.isEmpty) {
      slivers.add(
        SliverFillRemaining(hasScrollBody: false, child: _reviewEmpty(s)),
      );
    } else if (grouped) {
      final Map<String, List<Map<String, dynamic>>> byAccount =
          <String, List<Map<String, dynamic>>>{};
      for (final Map<String, dynamic> item in rows) {
        byAccount
            .putIfAbsent(
              _text(item['account'], 'Unknown'),
              () => <Map<String, dynamic>>[],
            )
            .add(item);
      }
      bool firstGroup = true;
      byAccount.forEach((String account, List<Map<String, dynamic>> group) {
        slivers.add(
          SliverPersistentHeader(
            pinned: true,
            delegate: _GroupHead('$account ${group.length}'),
          ),
        );
        slivers.add(
          _rowSliver(group, rows, animateEntries: firstGroup, columns: columns),
        );
        firstGroup = false;
      });
    } else {
      slivers.add(_rowSliver(rows, rows, columns: columns));
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        // The refresh control stays first: it reads the viewport's overscroll
        // and only works at the leading edge. Pulling down therefore stretches
        // from above the command bar, as it did.
        CupertinoSliverRefreshControl(onRefresh: _load),
        ..._chromeSlivers(locked: false, s: s),
        ...slivers,
      ],
    );
  }

  /// The Review list. One card per row on a phone, [columns] cards per row on
  /// an iPad.
  ///
  /// At `columns == 1` this is the sliver and the cell builder that shipped,
  /// called the way they shipped — that is why a phone cannot tell the
  /// difference. Above the breakpoint the same cells are dealt into rows of
  /// [Expanded] cells: same keys, same entrance stagger, same approval
  /// collapse, same card, at a third of the glass instead of all of it.
  Widget _rowSliver(
    List<Map<String, dynamic>> group,
    List<Map<String, dynamic>> all, {
    bool animateEntries = false,
    int columns = 1,
  }) {
    if (columns <= 1) {
      return SliverList.builder(
        itemCount: group.length,
        itemBuilder: (BuildContext context, int index) =>
            _reelCell(context, group, all, index, animateEntries),
      );
    }
    final int rows = (group.length + columns - 1) ~/ columns;
    return SliverList.builder(
      itemCount: rows,
      itemBuilder: (BuildContext context, int row) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int column = 0; column < columns; column++)
            Expanded(
              child: row * columns + column < group.length
                  ? _reelCell(
                      context,
                      group,
                      all,
                      row * columns + column,
                      animateEntries,
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  /// One Review card, unchanged from the single-column list it was extracted
  /// from.
  Widget _reelCell(
    BuildContext context,
    List<Map<String, dynamic>> group,
    List<Map<String, dynamic>> all,
    int index,
    bool animateEntries,
  ) {
    final Map<String, dynamic> item = group[index];
    final Widget row = AnimatedSize(
      duration: CdMotion.duration(context, CdMotion.std),
      curve: CdMotion.out,
      alignment: Alignment.topCenter,
      child: segment == 0 && _approvalMotion['${item['id']}'] == 2
          ? const SizedBox(width: double.infinity)
          : _ReelRow(
              key: ValueKey<String>('reel-row-${item['id']}'),
              item: item,
              base: host,
              showHandle: scope == 'all',
              failure: _failures.causeFor(item),
              justApproved: _approvalMotion['${item['id']}'] == 1,
              onOpen: () => _openReel(all, all.indexOf(item)),
              onApprove: () async {
                await _approve(item);
              },
              onChanges: () => _changesSheet(item),
              onSchedule: () => _scheduleSheet(item),
              onReschedule: () => _scheduleSheet(item, move: true),
              onScrap: () => _confirmScrap(item),
              onRestore: () => _confirmRestore(item),
              // Zion asked for scrap, post and edit on the card. Scrap was
              // already there; these two were two taps behind the overflow.
              // Same handlers, same confirm sheet, just reachable.
              onEdit: () => _openEditor(item),
              onPostNow: () => _confirmPostNow(item),
              onRetry: () async {
                await _failures.clear(item);
                if (mounted) setState(() {});
                await _load();
              },
              onOverflow: () => _rowOverflowSheet(item),
            ),
    );
    // Keyed on the reel so a refresh reuses the element rather than
    // rebuilding every row, and so the row is addressable in a test.
    // A sliver creates new children as they enter the viewport. Animating
    // those children from opacity zero makes a fast iOS scroll look like a
    // dead, empty half-screen. Keep Claude's entrance motion for the first
    // visible cards; render later cards at full opacity as soon as reached.
    final Widget entry = animateEntries && index < 4
        ? CdEnter(
            key: ValueKey<String>('reel-entry-${item['id']}'),
            delay: CdMotion.stagger * index.clamp(0, 4),
            child: row,
          )
        : row;
    return KeyedSubtree(
      key: ValueKey<String>('reel-entry-${item['id']}'),
      child: entry,
    );
  }

  Widget _reviewEmpty(TrialSnapshot s) {
    if (query.trim().isNotEmpty) {
      return ConEmpty(
        title: 'No match for "${query.trim()}"',
        body: 'Search looks at titles and captions only.',
        actions: <Widget>[
          ConButton(
            label: 'Clear search',
            kind: ConButtonKind.signalOutline,
            onPressed: () => setState(() {
              query = '';
              _search.clear();
              searching = false;
            }),
          ),
        ],
      );
    }
    if (!_filtersAtDefault) {
      return ConEmpty(
        title: 'No reels match this filter',
        body:
            'Filtered to ${<String>[if (stageFilter != stageFilters.first) stageFilter.toLowerCase(), if (ratingFilter != ratingFilters.first) ratingFilter.toLowerCase()].join(', ')}.',
        actions: <Widget>[
          ConButton(
            label: 'Clear filter',
            kind: ConButtonKind.signalOutline,
            onPressed: () => setState(() {
              stageFilter = stageFilters.first;
              ratingFilter = ratingFilters.first;
              orderFilter = orderFilters.first;
            }),
          ),
        ],
      );
    }
    if (segment == 0) {
      return ConEmpty(
        title: _runtimeText('review.empty_title', 'Nothing waiting'),
        body: _runtimeText(
          'review.empty_body',
          'Every reel is approved, scheduled or posted. New reels appear here when rendering finishes.',
        ),
        actions: <Widget>[
          ConButton(
            label: 'Show all reels',
            kind: ConButtonKind.signalOutline,
            onPressed: () => setState(() => segment = 1),
          ),
          const SizedBox(height: 8),
          ConButton(
            label: 'Request a reel',
            kind: ConButtonKind.ghost,
            onPressed: () => _openGenerator(s),
          ),
        ],
      );
    }
    return ConEmpty(
      title: scope == 'all' ? 'No reels yet' : 'No reels for $scope',
      body: 'This account has nothing rendered yet.',
      actions: <Widget>[
        ConButton(
          label: 'Request a reel',
          kind: ConButtonKind.signalOutline,
          onPressed: () => _openGenerator(s),
        ),
      ],
    );
  }

  Widget _scheduleBody(TrialSnapshot s) {
    final List<Map<String, dynamic>> rows = _calendarDay != null
        ? _scheduleRows(s).where((entry) {
            final DateTime day = phoenixWall(_scheduleDate(entry));
            return day.year == _calendarDay!.year &&
                day.month == _calendarDay!.month &&
                day.day == _calendarDay!.day;
          }).toList()
        : scheduleSegment == 0
        ? _dueToday(s)
        : _upcoming(s);
    // A month grid and the queue it is a picker for. On a phone they stack, as
    // they shipped. On an iPad they sit side by side: build 52 had to shrink
    // the calendar to stop one month being 1074 pt tall in a 943 pt
    // workspace, and half the width solves that without giving the other half
    // away — what is scheduled is now beside the day you tapped instead of
    // below the fold.
    final bool wide = SandLayout.isWide(MediaQuery.sizeOf(context).width);
    final Widget calendar = CdScheduleCalendar(
      today: phoenixNow(),
      scheduledDays: _scheduleRows(s)
          .map((entry) => _scheduleDate(entry))
          .where((day) => day.year != 9999)
          .map(phoenixWall)
          .toList(),
      selectedDay: _calendarDay,
      onSelected: (day) => setState(() => _calendarDay = day),
    );
    final List<Widget> queue = <Widget>[];
    if (rows.isEmpty) {
      queue.add(
        ConEmpty(
          title: _calendarDay == null
              ? _runtimeText('schedule.empty_title', 'Nothing queued')
              : 'Nothing scheduled this day',
          body: _runtimeText(
            'schedule.empty_body',
            'Approved reels appear here once you give them a time. Nothing posts on its own.',
          ),
        ),
      );
    } else {
      String? day;
      final List<Widget> children = queue;
      for (final Map<String, dynamic> entry in rows) {
        final DateTime due = _scheduleDate(entry);
        final String stamp = due.year == 9999 ? 'NO TIME SET' : dayStamp(due);
        if (stamp != day) {
          day = stamp;
          final bool held = rows
              .where((Map<String, dynamic> i) => _scheduleDate(i).year != 9999)
              .where(
                (Map<String, dynamic> i) => dayStamp(_scheduleDate(i)) == stamp,
              )
              .any(
                (Map<String, dynamic> i) =>
                    i['held'] == true || i['state'] == 'paused',
              );
          children.add(
            Container(
              height: 24,
              color: Con.ground,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Caps(
                held ? '$stamp HELD' : stamp,
                color: held ? Con.wait : Con.ink2,
              ),
            ),
          );
          children.add(const Rule());
        }
        final Map<String, dynamic> reel = s.catalogItems.firstWhere(
          (Map<String, dynamic> candidate) => candidate['id'] == entry['id'],
          orElse: () => entry,
        );
        children.add(
          DoctorCard(
            child: _ScheduleRow(
              entry: entry,
              reel: <String, dynamic>{...reel, ...entry},
              base: host,
              onOpen: () => _openReel(<Map<String, dynamic>>[reel], 0),
              onReschedule: exactScheduleMatches(entry, reel)
                  ? () => _scheduleSheet(reel, move: true)
                  : null,
              onOverflow: () => _scheduleOverflowSheet(entry, reel),
            ),
          ),
        );
      }
    }
    final List<Widget> slivers = <Widget>[
      ..._leadingSlivers(),
      if (wide)
        SliverToBoxAdapter(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: calendar),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: queue,
                ),
              ),
            ],
          ),
        )
      else ...<Widget>[
        SliverToBoxAdapter(child: calendar),
        SliverList.list(children: queue),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: _load),
        ..._chromeSlivers(locked: false, s: s),
        ...slivers,
      ],
    );
  }

  Future<void> _importFromPhone(TrialSnapshot s) async {
    final int sessionEpoch = _sessionEpoch;
    final List<String> accounts = _accounts(s)
        .where(
          (String account) =>
              !_gabeScope ||
              const <String>{
                '@barcrawling',
                '@barcrawls.arizona',
              }.contains(account),
        )
        .toList();
    final PhoneImportReceipt? receipt = await showPhoneImport(
      context: context,
      base: host,
      accounts: accounts,
      initialAccount: scope == 'all' ? null : scope,
    );
    if (!mounted || sessionEpoch != _sessionEpoch || receipt == null) return;
    _strip(
      receipt.kind == PhoneImportKind.video
          ? 'Clip added. It is ready to review and edit.'
          : 'Audio added. Choose it in the editor.',
    );
    await _load();
  }

  Widget _studioBody(TrialSnapshot s) => CustomScrollView(
    slivers: <Widget>[
      ..._chromeSlivers(locked: false, s: s),
      // Studio is where a clip is uploaded and a reel is requested. A gateway
      // that stopped answering has to say so here too, not only on Review and
      // Schedule. _leadingSlivers carries the status strip as well, so the
      // strip below moved into it rather than being rendered twice.
      ..._leadingSlivers(),
      SliverList.list(children: _studioRows(s)),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ],
  );

  List<Widget> _studioRows(TrialSnapshot s) {
    // The four CREATE actions are cards, so on an iPad they deal into the
    // same grid Review uses instead of four 1366 pt-wide rows stacked down
    // the middle. One column on a phone: the shipped list, in order.
    final int columns = SandLayout.columnsFor(MediaQuery.sizeOf(context).width);
    final List<Widget> create = <Widget>[
      if (_featureEnabled('phone_upload'))
        DoctorAction(
          title: 'Add from phone',
          subtitle: 'Upload a clip or audio from your phone',
          icon: CupertinoIcons.add,
          onTap: () => _importFromPhone(s),
        ),
      if (_featureEnabled('generation'))
        DoctorAction(
          title: 'Request a reel',
          subtitle: 'Get a new reel from your content',
          icon: CupertinoIcons.film,
          onTap: () => _openGenerator(s),
        ),
      if (_featureEnabled('flyer_composer'))
        DoctorAction(
          title: 'Make a flyer',
          subtitle: 'Build a flyer or carousel from typed event details',
          icon: CupertinoIcons.doc_richtext,
          onTap: () => _openFlyerComposer(s),
        ),
      DoctorAction(
        title: 'Make variations',
        subtitle: 'Create new versions of existing content',
        icon: CupertinoIcons.wand_stars,
        onTap: _openEditor,
      ),
    ];
    return <Widget>[
      const _GroupLabel('CREATE'),
      ...conCardRows(create, columns),
      const _GroupLabel('APPROVED LIBRARY'),
      _studioLibrary(s),
      const _GroupLabel('CAPTION'),
      ProfileManagerCard(
        key: ValueKey<String>('profile-$host-$_sessionEpoch'),
        accounts: _accounts(
          s,
        ).where((String name) => scope == 'all' || name == scope).toList(),
        read: (String path) => TrialApi(host).getJson(path),
      ),
    ];
  }

  Widget _studioLibrary(TrialSnapshot s) {
    // Three tiles across on a phone, and — MEASURED — three rows of them.
    // The tile is the same tile at every size; an iPad simply fits more of
    // them across, so the library shows more of the library instead of
    // showing nine tiles in the middle of the glass.
    final double width = MediaQuery.sizeOf(context).width;
    final double scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final int columns = SandLayout.isWide(width)
        ? (width / (190 * scale)).round().clamp(3, 8)
        : scale * 14 > 18
        ? 2
        : 3;
    final List<Map<String, dynamic>> items = _enriched(
      s,
    ).where(_inScope).where(_reviewApproved).take(columns * 3).toList();
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          'Your approved clips will appear here.',
          style: Ty.body.copyWith(color: Con.ink2),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 9,
        mainAxisSpacing: 9,
        childAspectRatio: .65,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return CdEnter(
          key: ValueKey('studio-${item['id']}'),
          delay: CdMotion.stagger * index.clamp(0, 4),
          child: CdPressFeedback(
            child: Semantics(
              button: true,
              label: 'Edit ${item['title'] ?? 'clip'}',
              child: GestureDetector(
                onTap: () => _openEditor(item),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ColoredBox(
                    color: Con.surface2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _Poster(
                            base: host,
                            id: '${item['id']}',
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(
                            _text(item['title'], 'Approved clip'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Ty.meta.copyWith(color: Con.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _resultsBody(TrialSnapshot s) => CustomScrollView(
    slivers: <Widget>[
      ..._chromeSlivers(locked: false, s: s),
      // Numbers that stopped updating look exactly like numbers that stopped
      // moving. The banner is the difference.
      ..._leadingSlivers(),
      SliverToBoxAdapter(
        child: NativeResults(
          key: ValueKey<String>('results-$host-$_sessionEpoch'),
          base: host,
          selectedAccounts: <String>{scope},
          catalog: s.catalogItems,
          accountStatus: s.accountStatus,
          load: () => TrialApi(host).getJson('/reels/insights'),
          connect: (String name) => _connect(name, 'insights'),
          preview: (Map<String, dynamic> item) =>
              _openReel(<Map<String, dynamic>>[item], 0),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ],
  );

  /// Shown while an OAuth flow is in flight. If iOS opens the authorize URL
  /// inside the Instagram app instead of Safari, the server bounce cannot
  /// reach the browser -- the copied link lets the user finish in Safari.
  Widget _oauthReturnBanner() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: DoctorCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Finish connecting in Instagram, then return here.',
                    style: Ty.body,
                  ),
                ),
                if (_lastOAuthUri != null)
                  ConButton(
                    label: 'Copy Safari link',
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: _lastOAuthUri.toString()),
                      );
                      _strip(
                        'Link copied. Paste it in Safari if Instagram opened its own app.',
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountsBody(TrialSnapshot s) {
    final List<Map<String, dynamic>> accounts = s.accountStatus;
    final int live = accounts
        .where(
          (Map<String, dynamic> i) =>
              _capability(i, 'publishing') == 'verified',
        )
        .length;
    // Account cards are cards: two or three across on an iPad, one on a
    // phone. The prose and the sign-out control below them keep a width,
    // because a 1334 pt line of body text and a 1334 pt red outline button
    // were the two things that were actually wrong on this tab.
    final int columns = SandLayout.columnsFor(MediaQuery.sizeOf(context).width);
    return CustomScrollView(
      slivers: <Widget>[
        ..._chromeSlivers(locked: false, s: s),
        // "Connected" on this tab is a claim about the gateway's own answer.
        // If the gateway is not answering, the tab has to say that first.
        ..._leadingSlivers(),
        if (_oauthInFlight) _oauthReturnBanner(),
        SliverList.list(
          children: <Widget>[
            const _GroupLabel('CONNECTION'),
            if (accounts.isEmpty)
              const ConEmpty(
                title: 'No accounts listed',
                body: 'The gateway did not return account status.',
              ),
            ...conCardRows(<Widget>[
              for (final Map<String, dynamic> account in accounts)
                DoctorCard(
                  child: _AccountRow(
                    item: account,
                    purpose: 'publish',
                    onConnect: _connect,
                  ),
                ),
            ], columns),
            const _GroupLabel('ANALYTICS'),
            ...conCardRows(<Widget>[
              for (final Map<String, dynamic> account in accounts)
                DoctorCard(
                  child: _AccountRow(
                    item: account,
                    purpose: 'insights',
                    onConnect: _connect,
                  ),
                ),
            ], columns),
            const _GroupLabel('PUBLISHING'),
            ConProse(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  'Posting is live for $live of ${accounts.length} accounts.',
                  style: Ty.body.copyWith(color: Con.ink2),
                ),
              ),
            ),
            ConProse(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Nothing publishes automatically. Review and confirmation remain required.',
                  style: Ty.meta.copyWith(color: Con.ink2, height: 1.4),
                ),
              ),
            ),
            const Rule(),
            const _GroupLabel('HELP'),
            ConSheetRow(
              label: 'Replay tutorial',
              onTap: () => unawaited(_openTutorial()),
            ),
            const _GroupLabel('SESSION'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Text(
                'Signed in as ${_gabeScope ? 'Gabe' : 'Zion'}. Content Doctor $nativeVersion.',
                style: Ty.body.copyWith(color: Con.ink2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  // MEASURED shipped: 358 pt in a 390 pt phone column, and
                  // 1334 pt of red outline on a 12.9" before build 52 capped
                  // the whole app. A destructive control does not get better
                  // by being wider; 420 is above every phone width, so the
                  // phone button is the phone button.
                  constraints: const BoxConstraints(maxWidth: SandLayout.card),
                  child: ConButton(
                    label: 'Sign out',
                    kind: ConButtonKind.redOutline,
                    expand: true,
                    onPressed: _signOut,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // SHEETS
  // -------------------------------------------------------------------------

  String _capability(Map<String, dynamic> account, String key) {
    final dynamic caps = account['capabilities'];
    if (caps is Map && caps[key] is Map) {
      return _text((caps[key] as Map)['status'], 'unknown');
    }
    return 'unknown';
  }

  Color _connectionTone(Map<String, dynamic>? account) {
    if (account == null) return Con.fail;
    final String state = _capability(account, 'publishing');
    if (state == 'verified') {
      return account['enabled'] == false ? Con.wait : Con.hold;
    }
    return Con.fail;
  }

  Future<void> _scopeSheet(TrialSnapshot s) async {
    final List<String> names = _accounts(s);
    final List<Map<String, dynamic>> rows = _enriched(s);
    await showConSheet<void>(
      context,
      (BuildContext sheet) => ConSheet(
        title: 'Account',
        children: <Widget>[
          for (final String name in names)
            Builder(
              builder: (BuildContext _) {
                final Map<String, dynamic>? status = s.accountStatus
                    .cast<Map<String, dynamic>?>()
                    .firstWhere(
                      (Map<String, dynamic>? a) => a?['account'] == name,
                      orElse: () => null,
                    );
                final int waiting = rows
                    .where((Map<String, dynamic> i) => i['account'] == name)
                    .where((Map<String, dynamic> i) => needsYou(i, _failures))
                    .length;
                final bool connected =
                    status != null &&
                    _capability(status, 'publishing') == 'verified';
                return ConSheetRow(
                  label: name,
                  height: 56,
                  leadingBar: _connectionTone(status),
                  detail: connected
                      ? '$waiting need review'
                      : status == null
                      ? 'Not connected'
                      : 'Connection incomplete',
                  selected: scope == name,
                  trailing: connected
                      ? null
                      : ConButton(
                          label: 'Connect',
                          height: 32,
                          onPressed: () {
                            Navigator.of(sheet).pop();
                            _connect(name, 'publish');
                          },
                        ),
                  onTap: () {
                    Navigator.of(sheet).pop();
                    setState(() => scope = name);
                    _refreshRuntimeConfig(host, _loadGeneration);
                  },
                );
              },
            ),
          if (!_gabeScope)
            ConSheetRow(
              label: 'All accounts',
              height: 56,
              detail:
                  '${rows.where((Map<String, dynamic> i) => needsYou(i, _failures)).length} need review',
              selected: scope == 'all',
              onTap: () {
                Navigator.of(sheet).pop();
                setState(() => scope = 'all');
                _refreshRuntimeConfig(host, _loadGeneration);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _filterSheet() async {
    String stage = stageFilter, rating = ratingFilter, order = orderFilter;
    final bool? applied = await showConSheet<bool>(
      context,
      (BuildContext sheet) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheet) => ConSheet(
          title: 'Filter and sort',
          children: <Widget>[
            const _GroupLabel('SHOW'),
            for (final String option in stageFilters)
              ConSheetRow(
                label: option,
                selected: stage == option,
                onTap: () => setSheet(() => stage = option),
              ),
            const _GroupLabel('RATING'),
            for (final String option in ratingFilters)
              ConSheetRow(
                label: option,
                selected: rating == option,
                onTap: () => setSheet(() => rating = option),
              ),
            const _GroupLabel('ORDER'),
            for (final String option in orderFilters)
              ConSheetRow(
                label: option,
                selected: order == option,
                onTap: () => setSheet(() => order = option),
              ),
            SizedBox(
              height: 60,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    ConButton(
                      label: 'Clear',
                      kind: ConButtonKind.ghost,
                      onPressed: () => setSheet(() {
                        stage = stageFilters.first;
                        rating = ratingFilters.first;
                        order = orderFilters.first;
                      }),
                    ),
                    const Spacer(),
                    ConButton(
                      label: 'Apply',
                      kind: ConButtonKind.signalOutline,
                      onPressed: () => Navigator.of(sheet).pop(true),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (applied == true && mounted) {
      setState(() {
        stageFilter = stage;
        ratingFilter = rating;
        orderFilter = order;
      });
    }
  }

  Future<void> _overflowSheet() async {
    final TrialSnapshot? s = snapshot == null ? null : _scopedSnapshot();
    await showConSheet<void>(
      context,
      (BuildContext sheet) => ConSheet(
        title: 'Workspace',
        children: <Widget>[
          if (_featureEnabled('dm_workspace'))
            ConSheetRow(
              label: 'Inbox',
              onTap: () {
                Navigator.of(sheet).pop();
                setState(() {
                  tab = 6;
                  _scheduleRuntimeConfigPoller(host, _loadGeneration);
                });
              },
            ),
          ConSheetRow(
            label: 'Accounts',
            onTap: () {
              Navigator.of(sheet).pop();
              setState(() => tab = 4);
            },
          ),
          if (_featureEnabled('dm_workspace'))
            ConSheetRow(
              label: 'Automations',
              onTap: () {
                Navigator.of(sheet).pop();
                setState(() {
                  tab = 7;
                  _scheduleRuntimeConfigPoller(host, _loadGeneration);
                });
              },
            ),
          if (_featureEnabled('generation'))
            ConSheetRow(
              label: 'Request a reel',
              onTap: () {
                Navigator.of(sheet).pop();
                if (s != null) _openGenerator(s);
              },
            ),
          ConSheetRow(
            label: 'Search',
            onTap: () {
              Navigator.of(sheet).pop();
              setState(() {
                tab = 0;
                searching = true;
              });
            },
          ),
          ConSheetRow(
            label: 'Refresh',
            onTap: () {
              Navigator.of(sheet).pop();
              _load();
            },
          ),
          ConSheetRow(
            label: 'Sign out',
            labelColor: Con.failBright,
            onTap: () {
              Navigator.of(sheet).pop();
              _signOut();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _rowOverflowSheet(Map<String, dynamic> item) async {
    final bool live = reelCanReceiveNewIntent(item);
    final bool approved = _reviewApproved(item);
    final bool canRestore = canRestoreReel(item);
    final String? link = reelPermalink(item);
    await showConSheet<void>(
      context,
      (BuildContext sheet) => ConSheet(
        title: _text(item['title'], _text(item['id'])),
        children: <Widget>[
          ConSheetRow(
            label: 'Rate',
            onTap: () {
              Navigator.of(sheet).pop();
              _rateSheet(item);
            },
          ),
          ConSheetRow(
            label: 'Edit caption',
            onTap: () {
              Navigator.of(sheet).pop();
              _captionSheet(item);
            },
          ),
          ConSheetRow(
            label: 'Make variations',
            onTap: () {
              Navigator.of(sheet).pop();
              _openEditor(item);
            },
          ),
          ConSheetRow(
            label: 'Edit music',
            onTap: () {
              Navigator.of(sheet).pop();
              _openEditor(item);
            },
          ),
          ConSheetRow(
            label: 'Copy private clip link',
            onTap: () {
              Navigator.of(sheet).pop();
              _copyLink(item);
            },
          ),
          if (link != null)
            ConSheetRow(
              label: 'View on Instagram',
              onTap: () {
                Navigator.of(sheet).pop();
                launchUrl(
                  Uri.parse(link),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
          ConSheetRow(
            label: 'Notes',
            onTap: () {
              Navigator.of(sheet).pop();
              _notesSheet(item);
            },
          ),
          ConSheetRow(
            label: 'Details',
            onTap: () {
              Navigator.of(sheet).pop();
              _detailsSheet(item);
            },
          ),
          if (live && approved)
            ConSheetRow(
              label: 'Post now',
              labelColor: Con.failBright,
              onTap: () async {
                Navigator.of(sheet).pop();
                await _confirmPostNow(item);
              },
            ),
          if (item['schedule_detail'] is Map)
            ConSheetRow(
              label: 'Cancel schedule',
              labelColor: Con.failBright,
              onTap: () {
                Navigator.of(sheet).pop();
                _cancel(item);
              },
            ),
          if (canRestore)
            ConSheetRow(
              label: 'Restore reel',
              onTap: () async {
                Navigator.of(sheet).pop();
                await _confirmRestore(item);
              },
            ),
          if (canScrapReel(item))
            ConSheetRow(
              label: 'Scrap reel',
              labelColor: Con.failBright,
              onTap: () async {
                Navigator.of(sheet).pop();
                await _confirmScrap(item);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _scheduleOverflowSheet(
    Map<String, dynamic> entry,
    Map<String, dynamic> reel,
  ) async {
    final bool exact = exactScheduleMatches(entry, reel);
    await showConSheet<void>(
      context,
      (BuildContext sheet) => ConSheet(
        title: _text(reel['title'], _text(reel['id'])),
        children: <Widget>[
          if (exact && _reviewApproved(reel))
            ConSheetRow(
              label: 'Post now',
              labelColor: Con.failBright,
              onTap: () async {
                Navigator.of(sheet).pop();
                if (await _confirmSheet(
                  'Post now',
                  'This posts immediately and cannot be recalled.',
                  'Post now',
                )) {
                  await _postNow(reel);
                }
              },
            ),
          if (const <String>['scheduled', 'paused'].contains(entry['state']))
            ConSheetRow(
              label: 'Cancel schedule',
              labelColor: Con.failBright,
              onTap: () {
                Navigator.of(sheet).pop();
                // Calendar entries are projections and may omit the catalog
                // SHA/caption. The mutation must use the full reel identity.
                _cancel(reel);
              },
            ),
          ConSheetRow(
            label: 'Details',
            onTap: () {
              Navigator.of(sheet).pop();
              _detailsSheet(reel);
            },
          ),
        ],
      ),
    );
  }

  List<DateTime> _suggestions() {
    final DateTime now = phoenixPickerWallNow();
    DateTime slot(int addDays, int hour, int minute) =>
        DateTime(now.year, now.month, now.day + addDays, hour, minute);
    final DateTime evening = slot(0, 18, 40);
    return <DateTime>[
      evening.isAfter(now.add(const Duration(minutes: 5)))
          ? evening
          : slot(1, 18, 40),
      slot(1, 12, 15),
      slot(2, 18, 40),
    ];
  }

  Future<ReelWrite> _scheduleSheet(
    Map<String, dynamic> item, {
    bool move = false,
  }) async {
    final List<DateTime> options = _suggestions();
    DateTime chosen = options.first;
    final bool approved = _reviewApproved(item);
    final Map<String, dynamic>? account = snapshot?.accountStatus
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (Map<String, dynamic>? a) => a?['account'] == item['account'],
          orElse: () => null,
        );
    final bool paused = account != null && account['enabled'] == false;

    final DateTime? committed = await showConSheet<DateTime>(
      context,
      (BuildContext sheet) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheet) => ConSheet(
          title: 'Schedule',
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Times in America/Phoenix. Paused accounts hold their schedules.',
                style: Ty.meta.copyWith(color: Con.ink3),
              ),
            ),
            for (final DateTime option in options)
              ConSheetRow(
                label:
                    '${dayStamp(phoenixWallToUtc(option))} '
                    '${wallClock(option)}',
                height: 56,
                detail: option.hour >= 17 ? 'Evening slot' : 'Midday slot',
                trailing: Container(
                  width: 6,
                  height: 6,
                  color: chosen == option ? Con.signal : Con.rule,
                ),
                onTap: () => setSheet(() => chosen = option),
              ),
            ConSheetRow(
              label: 'Pick a time',
              trailing: const Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: Con.ink3,
              ),
              onTap: () async {
                final DateTime? picked = await _pickTime(chosen);
                if (picked != null) setSheet(() => chosen = picked);
              },
            ),
            if (paused)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                color: Con.surface1,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Container(width: 3, color: Con.wait),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'This account is paused. The reel holds at its scheduled time until you enable it.',
                            style: Ty.meta.copyWith(
                              color: Con.ink2,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: ConButton(
                label: move
                    ? 'Reschedule'
                    : approved
                    ? 'Schedule'
                    : 'Approve and schedule',
                kind: ConButtonKind.signalFill,
                height: 48,
                expand: true,
                onPressed: () => Navigator.of(sheet).pop(chosen),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Nothing posts until the scheduled time. You can cancel from the Schedule tab.',
                style: Ty.meta.copyWith(color: Con.ink2, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
    if (committed == null || !mounted) return ReelWrite.cancelled;
    if (!approved && !move && !await _approve(item)) return ReelWrite.failed;
    return await _scheduleAt(item, committed, move: move)
        ? ReelWrite.done
        : ReelWrite.failed;
  }

  Future<DateTime?> _pickTime(DateTime initial) =>
      showConSheet<DateTime>(context, (BuildContext sheet) {
        DateTime value = initial;
        return Container(
          color: Con.surface1,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Rule(strong: true),
                SizedBox(
                  height: 44,
                  child: Row(
                    children: <Widget>[
                      const SizedBox(width: 16),
                      const Expanded(child: Caps('Pick a time')),
                      ConButton(
                        label: 'Apply',
                        kind: ConButtonKind.signalOutline,
                        onPressed: () => Navigator.of(sheet).pop(value),
                      ),
                      const SizedBox(width: 16),
                    ],
                  ),
                ),
                const Rule(),
                SizedBox(
                  height: 240,
                  child: CupertinoTheme(
                    data: const CupertinoThemeData(
                      brightness: Brightness.dark,
                      primaryColor: Con.signal,
                    ),
                    child: CupertinoDatePicker(
                      initialDateTime: initial,
                      minimumDate: phoenixPickerWallNow(),
                      maximumDate: phoenixPickerWallNow().add(
                        const Duration(days: 30),
                      ),
                      use24hFormat: true,
                      onDateTimeChanged: (DateTime picked) => value = picked,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      });

  Future<void> _changesSheet(Map<String, dynamic> item) async {
    final String reelId = '${item['id']}';
    final TextEditingController note = TextEditingController(
      text: _revisionDrafts[reelId] ?? '',
    );
    final String? text = await showConSheet<String>(
      context,
      (BuildContext sheet) => ConSheet(
        title: 'Request changes',
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: CupertinoTextField(
              controller: note,
              autofocus: true,
              maxLines: 5,
              maxLength: 4000,
              placeholder: 'What should change?',
              placeholderStyle: Ty.body.copyWith(color: Con.ink3),
              style: Ty.body.copyWith(color: Con.ink),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Con.surface3,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Con.rule),
              ),
              onChanged: (String value) => _revisionDrafts[reelId] = value,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: <Widget>[
                ConButton(
                  label: 'Cancel',
                  kind: ConButtonKind.ghost,
                  onPressed: () => Navigator.of(sheet).pop(),
                ),
                const Spacer(),
                ConButton(
                  label: 'Send to revisions',
                  kind: ConButtonKind.signalOutline,
                  onPressed: () => Navigator.of(sheet).pop(note.text.trim()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    note.dispose();
    if (text == null || text.isEmpty || !mounted) return;
    await _requestChanges(item, text);
  }

  Future<void> _rateSheet(Map<String, dynamic> item) async {
    final int? rating = await showConSheet<int>(
      context,
      (BuildContext sheet) => ConSheet(
        title: 'Rate',
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'A rating keeps a style reference. It does not approve or post the reel.',
              style: Ty.meta.copyWith(color: Con.ink2, height: 1.4),
            ),
          ),
          for (int value = 5; value >= 1; value--)
            ConSheetRow(
              label: '$value of 5',
              selected: reelRating(item) == value,
              trailing: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: RatingMeter(rating: value),
              ),
              onTap: () => Navigator.of(sheet).pop(value),
            ),
        ],
      ),
    );
    if (rating == null || !mounted) return;
    HapticFeedback.selectionClick();
    await _rate(item, rating);
  }

  Future<void> _captionSheet(Map<String, dynamic> item) async {
    final TextEditingController field = TextEditingController(
      text: _text(item['caption'], ''),
    );
    final String? saved = await showConSheet<String>(
      context,
      (BuildContext sheet) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheet) {
          final int length = field.text.length;
          final bool overLimit = length > 2200;
          return ConSheet(
            title: 'Caption',
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16),
                child: CupertinoTextField(
                  controller: field,
                  maxLines: null,
                  minLines: 5,
                  style: Ty.body.copyWith(color: Con.ink),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Con.surface3,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: overLimit ? Con.fail : Con.rule,
                      width: overLimit ? 1.5 : 1,
                    ),
                  ),
                  onChanged: (_) => setSheet(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: <Widget>[
                    if (overLimit)
                      Expanded(
                        child: Text(
                          'Caption is over 2200 characters.',
                          style: Ty.meta.copyWith(color: Con.failBright),
                        ),
                      )
                    else
                      const Spacer(),
                    Text(
                      '$length',
                      style: Ty.meta.copyWith(
                        color: overLimit
                            ? Con.failBright
                            : length > 2100
                            ? Con.wait
                            : Con.ink3,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  "Saving a caption clears this reel's approval and any schedule.",
                  style: Ty.meta.copyWith(color: Con.ink2, height: 1.4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: <Widget>[
                    ConButton(
                      label: 'Cancel',
                      kind: ConButtonKind.ghost,
                      onPressed: () => Navigator.of(sheet).pop(),
                    ),
                    const Spacer(),
                    ConButton(
                      label: 'Save caption',
                      kind: ConButtonKind.signalOutline,
                      onPressed: overLimit
                          ? null
                          : () => Navigator.of(sheet).pop(field.text),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
    field.dispose();
    if (saved == null || !mounted) return;
    await _saveCaption(item, saved);
  }

  Future<void> _detailsSheet(Map<String, dynamic> item) async {
    final dynamic schedule = item['schedule_detail'] ?? item['approval'];
    final DateTime? due = schedule is Map
        ? DateTime.tryParse('${schedule['scheduled_at']}')
        : null;
    final num? seconds = reelSeconds(item);
    final int? rating = reelRating(item);
    final String? permalink = reelPermalink(item);
    final DateTime? postedAt = reelPostedAt(item);
    final String sha = _text(item['sha256'], '');
    final Map<String, String> fields = <String, String>{
      'Account': _text(item['account']),
      'Created': _text(item['created_at']),
      if (seconds != null) 'Duration': durationLabel(seconds),
      if (reelMusic(item) != null) 'Sound': reelMusic(item)!,
      if (rating != null) 'Rating': '$rating of 5',
      'Version': sha.isEmpty
          ? 'Unknown'
          : sha.substring(0, sha.length < 12 ? sha.length : 12),
      'Status': reelLifecycle(item),
      if (postedAt != null)
        'Posted': '${dayStamp(postedAt)} at ${clock(postedAt)}',
      'Scheduled for': due == null ? 'Not scheduled' : clock(due),
      'Coverage': '${(coverageFor(sha) * 100).round()}%',
    };
    await showConSheet<void>(
      context,
      (BuildContext sheet) => ConSheet(
        title: 'Details',
        children: <Widget>[
          for (final MapEntry<String, String> field in fields.entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: <Widget>[
                  SizedBox(
                    height: 40,
                    child: Row(
                      children: <Widget>[
                        SizedBox(width: 120, child: Caps(field.key)),
                        Expanded(
                          child: Text(
                            field.value,
                            textAlign: TextAlign.right,
                            style: Ty.body.copyWith(color: Con.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Rule(),
                ],
              ),
            ),
          if (permalink != null)
            ConSheetRow(
              label: 'View published reel',
              detail: 'Instagram receipt',
              onTap: () {
                launchUrl(
                  Uri.parse(permalink),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _notesSheet(Map<String, dynamic> item) async {
    final dynamic raw = item['edit_requests'] ?? item['revision_requests'];
    final List<dynamic> rows = raw is List
        ? raw
        : raw == null
        ? const <dynamic>[]
        : <dynamic>[raw];
    await showConSheet<void>(
      context,
      (BuildContext sheet) => ConSheet(
        title: 'Notes',
        children: <Widget>[
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No change requests recorded for this export.',
                style: Ty.body.copyWith(color: Con.ink2),
              ),
            ),
          for (final dynamic row in rows)
            ConSheetRow(
              label: row is Map
                  ? '${row['text'] ?? row['note'] ?? row['feedback'] ?? row['id'] ?? 'Change requested'}'
                  : '$row',
              detail: row is Map
                  ? '${row['state'] ?? row['status'] ?? 'Queued'}'
                  : null,
              height: 56,
            ),
        ],
      ),
    );
  }

  Future<bool> _confirmSheet(String title, String body, String action) async {
    final bool? ok = await showConSheet<bool>(
      context,
      (BuildContext sheet) => ConSheet(
        title: title,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(body, style: Ty.body.copyWith(color: Con.ink)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: <Widget>[
                ConButton(
                  label: 'Cancel',
                  kind: ConButtonKind.ghost,
                  onPressed: () => Navigator.of(sheet).pop(false),
                ),
                const Spacer(),
                ConButton(
                  label: action,
                  kind: ConButtonKind.redOutline,
                  onPressed: () => Navigator.of(sheet).pop(true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _signInSheet() async {
    final TextEditingController username = TextEditingController();
    final TextEditingController key = TextEditingController();
    final bool? go = await showConSheet<bool>(
      context,
      (BuildContext sheet) => ConSheet(
        title: 'Sign in',
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: CupertinoTextField(
              controller: username,
              autocorrect: false,
              enableSuggestions: false,
              placeholder: 'Username',
              placeholderStyle: Ty.body.copyWith(color: Con.ink3),
              style: Ty.body.copyWith(color: Con.ink),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Con.surface3,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Con.rule),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: CupertinoTextField(
              controller: key,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              placeholder: 'Password or owner access key',
              placeholderStyle: Ty.body.copyWith(color: Con.ink3),
              style: Ty.body.copyWith(color: Con.ink),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Con.surface3,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Con.rule),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Owner keys sign in with the key alone. Access is saved in Keychain.',
              style: Ty.meta.copyWith(color: Con.ink2, height: 1.4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: ConButton(
              label: 'Unlock',
              kind: ConButtonKind.signalFill,
              height: 48,
              expand: true,
              onPressed: () => Navigator.of(sheet).pop(true),
            ),
          ),
        ],
      ),
    );
    final String name = username.text.trim();
    final String secret = key.text;
    username.dispose();
    key.dispose();
    if (go != true || secret.isEmpty) return;
    try {
      if (name.isNotEmpty) {
        await TrialCredentials.login(host, name, secret);
      } else {
        await TrialCredentials.validateAndSave(host, secret);
      }
      if (mounted) setState(() => _sessionEpoch++);
      await _load();
    } catch (_) {
      if (!mounted) return;
      _strip('Could not unlock. Check the connection and your sign in.');
    }
  }

  Future<void> _signOut() async {
    // Invalidate all pending reads before the asynchronous Keychain delete.
    // Otherwise an older auth response can repaint a just-signed-out role.
    ++_loadGeneration;
    if (mounted) {
      setState(() {
        _sessionEpoch++;
        _sessionRole = null;
        snapshot = null;
        loading = true;
        error = null;
      });
    }
    try {
      await TrialCredentials.clear(host);
    } catch (_) {
      /* A clear that fails still ends the session on the next auth check. */
    }
    await _load();
  }

  Future<void> _copyLink(Map<String, dynamic> item) async {
    await Clipboard.setData(
      ClipboardData(
        text: '$host/reels/file/${Uri.encodeComponent(item['id'].toString())}',
      ),
    );
    _strip('Private link copied. Sign in to the workspace to open it.');
  }

  // -------------------------------------------------------------------------
  // ROUTES
  // -------------------------------------------------------------------------

  Future<void> _openReel(List<Map<String, dynamic>> items, int index) async {
    if (items.isEmpty) return;
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ReelView(
          base: host,
          items: items,
          index: index < 0 ? 0 : index,
          failureFor: _failures.causeFor,
          onApprove: (Map<String, dynamic> item) async =>
              await _approve(item) ? ReelWrite.done : ReelWrite.failed,
          onSchedule: (Map<String, dynamic> item) => _scheduleSheet(item),
          onReschedule: (Map<String, dynamic> item) =>
              _scheduleSheet(item, move: true),
          onChanges: _changesSheet,
          onRate: _rateSheet,
          onEdit: (Map<String, dynamic> item) async {
            _openEditor(item);
          },
          onMarkWatched: (Map<String, dynamic> item, int duration) async {
            markWatched('${item['sha256']}', duration);
          },
          onWatchBypass: (Map<String, dynamic> item) async {
            markWatchBypassed('${item['sha256']}');
            _strip(
              'Approved without watching. The reel would not play, and the '
              'receipt says so.',
            );
          },
          onCaption: _captionSheet,
          onDetails: _detailsSheet,
          onNotes: _notesSheet,
          onCopyLink: _copyLink,
          onPostNow: _confirmPostNow,
          onCancel: (Map<String, dynamic> item) async =>
              await _cancel(item) ? ReelWrite.done : ReelWrite.failed,
          onScrap: _confirmScrap,
          onRestore: _confirmRestore,
          onRetry: (Map<String, dynamic> item) async {
            await _failures.clear(item);
            await _load();
            return ReelWrite.done;
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _openEditor([Map<String, dynamic>? reel]) {
    final TrialSnapshot? s = snapshot == null ? null : _scopedSnapshot();
    // Gabe's render permit is deliberately narrower than a catalogue-derived
    // account list: only account-status entries are current, role-verified
    // lanes. A stale reel must never create a third editor destination.
    final List<String> accounts = s == null
        ? <String>[]
        : _gabeScope
        ? s.accountStatus
              .map((Map<String, dynamic> item) => _text(item['account'], ''))
              .where(gabeProvisionedAccounts.contains)
              .toSet()
              .toList()
        : _accounts(s);
    if (accounts.isEmpty) {
      accounts.addAll(
        _gabeScope
            ? gabeProvisionedAccounts
            : <String>['@zionboggan', ...gabeProvisionedAccounts],
      );
    } else if (!_gabeScope && accounts.remove('@zionboggan')) {
      accounts.insert(0, '@zionboggan');
    }
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => NativeReelEditor(
          base: host,
          initialReel: reel,
          collectOnly: _gabeScope,
          allowDirectRender: _gabeScope,
          allowedAccounts: accounts,
          onReviewReady: (_) => _load(),
          openReview: () {
            Navigator.of(context).pop();
            setState(() => tab = 0);
            _load();
          },
        ),
      ),
    );
  }

  /// The flyer composer is account-scoped exactly like the generator, and its
  /// renders are review-only: it has no publish, schedule or approve path.
  void _openFlyerComposer(TrialSnapshot s) => Navigator.of(context).push(
    CupertinoPageRoute<void>(
      builder: (_) => FlyerComposerPage(
        accounts: _accounts(s),
        read: (String path) => TrialApi(host).getJson(path),
        write: (String path, Map<String, dynamic> payload) =>
            TrialApi(host).postJson(path, payload),
      ),
    ),
  );

  void _openGenerator(TrialSnapshot s) => Navigator.of(context).push(
    CupertinoPageRoute<void>(
      builder: (_) => GenerationPage(
        accounts: _accounts(s),
        read: (String path) => TrialApi(host).getJson(path),
        write: (String path, Map<String, dynamic> payload) =>
            TrialApi(host).postJson(path, payload),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// PURE HELPERS. Behaviour below is unchanged; only `_text` lost its dash.
// ---------------------------------------------------------------------------

List<Map<String, dynamic>> positiveRatedReels(
  List<Map<String, dynamic>> catalog,
  Set<String> accounts,
) => catalog
    .where(
      (Map<String, dynamic> item) =>
          (accounts.contains('all') || accounts.contains(item['account'])) &&
          item['owner_rating'] is num &&
          item['owner_rating'] >= 4,
    )
    .toList();

bool reelCanReceiveNewIntent(Map<String, dynamic> item) {
  final dynamic approval = item['approval'];
  if (item['status'] == 'scrapped') return false;
  return approval == null ||
      approval is Map &&
          <String>['cancelled', 'invalidated'].contains(approval['state']);
}

String reelLifecycle(Map<String, dynamic> item) {
  final dynamic schedule = item['schedule_detail'] ?? item['approval'];
  final dynamic state = schedule is Map ? schedule['state'] : item['status'];
  if (item['status'] == 'scrapped') return 'Scrapped';
  if (state == 'published' || item['status'] == 'published') return 'Published';
  if (item['status'] == 'changes_requested') return 'Revision queued';
  if (schedule is Map && (schedule['held'] == true || state == 'paused')) {
    return 'On hold';
  }
  if (<String>['needs_attention', 'failed', 'error'].contains(state)) {
    return 'Needs attention';
  }
  if (state == 'scheduled') return 'Scheduled';
  if (<String>['posting', 'publishing', 'preparing'].contains(state)) {
    return 'Publishing';
  }
  if (_reviewApproved(item)) return 'Approved';
  return 'For review';
}

String scheduleExplanation(Map<dynamic, dynamic> item) {
  final dynamic detail = item['status_explanation'];
  final dynamic explanation = detail is Map
      ? detail['summary']
      : item['human_reason'] ?? item['hold_reason_human'];
  final dynamic action = detail is Map
      ? detail['recovery_action']
      : item['recovery_action'];
  if (explanation is String && explanation.isNotEmpty) {
    return '$explanation${action is String && action.isNotEmpty ? '\n$action' : ''}';
  }
  if (item['held'] == true || item['state'] == 'paused') {
    return 'Posting is paused. Open Accounts to check publishing switches and connection.';
  }
  if (<String>['failed', 'needs_attention'].contains(item['state'])) {
    return 'Posting needs attention. Check the account connection before retrying; the previous attempt must be reconciled.';
  }
  return _text(item['state']).replaceAll('_', ' ');
}

String reelNextAction(Map<String, dynamic> item) {
  final String state = reelLifecycle(item);
  final dynamic schedule = item['schedule_detail'] ?? item['approval'];
  if (state == 'Scheduled' && schedule is Map) {
    final DateTime? date = DateTime.tryParse('${schedule['scheduled_at']}');
    return date == null
        ? 'Scheduled. See Schedule for details'
        : 'Scheduled ${clock(date)}';
  }
  if ((state == 'On hold' || state == 'Needs attention') && schedule is Map) {
    return scheduleExplanation(schedule);
  }
  return switch (state) {
    'Approved' => 'Approved. Give it a time',
    'Revision queued' => 'Changes saved. Waiting for the edit batch',
    'Published' => 'Posted. See Results',
    'Publishing' => 'Waiting for provider confirmation',
    _ => 'Watch it, then approve or request changes',
  };
}

DateTime _scheduleDate(Map<String, dynamic> item) =>
    DateTime.tryParse(_text(item['scheduled_at'], '')) ?? DateTime(9999);

bool exactScheduleMatches(
  Map<String, dynamic> entry,
  Map<String, dynamic> reel,
) =>
    (<String>['scheduled', 'paused'].contains(entry['state']) ||
        entry['retry_eligible'] == true) &&
    reel['status'] == 'ready_for_review' &&
    <String>[
      'id',
      'sha256',
      'account',
      'caption',
    ].every((String key) => entry[key] != null && entry[key] == reel[key]);

String _text(dynamic value, [String empty = 'Unknown']) =>
    value == null || '$value'.isEmpty ? empty : '$value';

bool _reviewApproved(Map<String, dynamic> item) {
  final dynamic value = item['review'];
  if (value is! Map || value['state'] != 'review_approved') return false;
  return value['sha256'] == item['sha256'] &&
      value['account'] == item['account'] &&
      value['caption'] == (item['caption'] ?? '');
}

// ---------------------------------------------------------------------------
// SMALL SHELL PIECES
// ---------------------------------------------------------------------------

/// Keeps every tab the operator has visited mounted, so its `State` — and
/// therefore its scroll position, its open conversation and the data it has
/// already fetched — survives a trip to another tab and back.
///
/// Only the active tab is laid out, painted, hit-tested or ticking; dormant
/// tabs sit behind `Offstage`, which costs nothing per frame. During a switch
/// the outgoing tab is held at full opacity underneath the incoming one, which
/// fades in over it. That is the same 300 ms fade as before with one less
/// artefact: the old switcher faded both children at once, so identical
/// chrome briefly composited to 75% and the ground showed through.
class _TabDeck extends StatefulWidget {
  const _TabDeck({
    super.key,
    required this.index,
    required this.duration,
    required this.curve,
    required this.builder,
  });

  final int index;
  final Duration duration;
  final Curve curve;
  final Widget Function(int index) builder;

  @override
  State<_TabDeck> createState() => _TabDeckState();
}

class _TabDeckState extends State<_TabDeck>
    with SingleTickerProviderStateMixin {
  // Built in initState, not lazily. A `late final` controller that build only
  // reads on some paths is first read by dispose(), which constructs a Ticker
  // against an already-deactivated element. See _SplitPrimaryState.
  late final AnimationController _fade;
  late final CurvedAnimation _curved;

  /// Tab index to the widget last built for it. A dormant tab is handed back
  /// the identical widget instance, which Element.updateChild short-circuits,
  /// so nothing off screen rebuilds when the shell repaints.
  final Map<int, Widget> _bodies = <int, Widget>{};
  int? _outgoing;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: 1,
    )..addStatusListener(_onFade);
    _curved = CurvedAnimation(parent: _fade, curve: widget.curve);
  }

  void _onFade(AnimationStatus status) {
    if (status == AnimationStatus.completed && _outgoing != null && mounted) {
      setState(() => _outgoing = null);
    }
  }

  @override
  void didUpdateWidget(_TabDeck old) {
    super.didUpdateWidget(old);
    _fade.duration = widget.duration;
    if (widget.index == old.index) return;
    _outgoing = old.index;
    if (widget.duration == Duration.zero) {
      _outgoing = null;
      _fade.value = 1;
    } else {
      _fade.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The active tab is rebuilt from the shell's current snapshot. Everything
    // else keeps the widget it was last given.
    _bodies[widget.index] = widget.builder(widget.index);
    final List<int> dormant =
        _bodies.keys
            .where((int tab) => tab != widget.index && tab != _outgoing)
            .toList()
          ..sort();
    return Stack(
      // Without an explicit expand the children are offered minHeight 0 and
      // anything that shrink-wraps in the scroll axis draws as a short island
      // centred in the workspace. See test/shell_layout_test.dart.
      fit: StackFit.expand,
      children: <Widget>[
        for (final int tab in dormant) _slot(tab, visible: false),
        if (_outgoing case final int out) _slot(out, visible: true),
        _slot(widget.index, visible: true, fading: _outgoing != null),
      ],
    );
  }

  /// The wrapper chain is deliberately the same shape for every slot in every
  /// state. Adding or removing a level here — a FadeTransition that is only
  /// present while a tab is arriving, say — changes the widget type at that
  /// position, and Flutter then discards the element below it. That is the
  /// whole defect being fixed: the page, and its scroll position, would be
  /// rebuilt from nothing again.
  Widget _slot(int tab, {required bool visible, bool fading = false}) =>
      KeyedSubtree(
        key: ValueKey<int>(tab),
        child: Offstage(
          offstage: !visible,
          child: FadeTransition(
            opacity: fading ? _curved : kAlwaysCompleteAnimation,
            child: TickerMode(
              enabled: visible && tab == widget.index,
              child: _bodies[tab]!,
            ),
          ),
        ),
      );
}

class _TabMark extends StatelessWidget {
  const _TabMark();
  @override
  Widget build(BuildContext context) {
    final Color tint = IconTheme.of(context).color ?? Con.ink3;
    return Icon(CupertinoIcons.play_rectangle, size: 24, color: tint);
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Container(
        height: 32,
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Caps(text),
      ),
      const Rule(),
    ],
  );
}

class _GroupHead extends SliverPersistentHeaderDelegate {
  const _GroupHead(this.text);
  final String text;
  @override
  double get minExtent => 25;
  @override
  double get maxExtent => 25;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: 24,
            color: Con.ground,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Caps(text),
          ),
          const Rule(),
        ],
      );
  @override
  bool shouldRebuild(_GroupHead old) => old.text != text;
}

/// The poster well. A locked session and a genuinely missing export used to
/// render the same glyph, which is how a gateway 401 on every poster stayed
/// invisible. The mark says missing; the lock says locked.
class _Poster extends StatelessWidget {
  const _Poster({
    required this.base,
    required this.id,
    this.width = 60,
    this.height = 104,
  });
  final String base, id;
  final double width, height;

  @override
  Widget build(BuildContext context) {
    final Map<String, String> headers = TrialCredentials.mediaHeaders(base);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        width: width,
        height: height,
        child: Image.network(
          '$base/reels/file/${Uri.encodeComponent(id)}.poster',
          fit: BoxFit.cover,
          cacheWidth: width.isFinite ? (width * 3).round() : 360,
          headers: headers,
          frameBuilder:
              (
                BuildContext context,
                Widget child,
                int? frame,
                bool wasSynchronouslyLoaded,
              ) => frame == null && !wasSynchronouslyLoaded
              ? const ColoredBox(color: Con.surface2)
              : child,
          errorBuilder: (BuildContext context, Object error, StackTrace? s) =>
              ColoredBox(
                color: Con.well,
                child: Center(
                  child: headers.isEmpty
                      ? const Icon(
                          CupertinoIcons.lock,
                          size: 20,
                          color: Con.ink3,
                        )
                      : const TrialMark(
                          size: 24,
                          color: Con.ink3,
                          dotColor: Con.ink3,
                        ),
                ),
              ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// THE REEL ROW
//
// A row, not a card: no border, no radius, no background, no margin. The
// hairline between rows runs full bleed and the content is inset by the
// gutter, and that contrast is the whole console read.
// ---------------------------------------------------------------------------

class _ReelRow extends StatefulWidget {
  const _ReelRow({
    super.key,
    required this.item,
    required this.base,
    required this.showHandle,
    required this.onOpen,
    required this.onApprove,
    required this.onChanges,
    required this.onSchedule,
    required this.onReschedule,
    required this.onScrap,
    required this.onRestore,
    required this.onRetry,
    required this.onEdit,
    required this.onPostNow,
    required this.onOverflow,
    this.failure,
    this.justApproved = false,
  });

  final Map<String, dynamic> item;
  final String base;
  final bool showHandle;
  final String? failure;
  final bool justApproved;
  final VoidCallback onOpen,
      onApprove,
      onChanges,
      onSchedule,
      onReschedule,
      onScrap,
      onRestore,
      onEdit,
      onPostNow,
      onOverflow;
  final Future<void> Function() onRetry;

  @override
  State<_ReelRow> createState() => _ReelRowState();
}

class _ReelRowState extends State<_ReelRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> item = widget.item;
    final ReelState state = reelStateFor(item, failure: widget.failure);
    final String lifecycle = reelLifecycle(item);
    final num? seconds = reelSeconds(item);
    final int? rating = reelRating(item);
    final String? music = reelMusic(item);
    final String? receipt = reelReceiptSummary(item);
    final bool untitled = optional(item['title']) == null;
    // `_text`'s fallback is an ordinary argument, so it used to be evaluated --
    // caption flattening, a split and a join -- for every row even when the row
    // had a title and the result was thrown away.
    final String title = untitled
        ? _text(null, firstWords(captionText(item['caption']), 6))
        : _text(item['title'], '');

    final List<String> line3 = <String>[
      if (widget.showHandle) _text(item['account'], ''),
      ?(receipt ?? music),
    ]..removeWhere((String s) => s.isEmpty);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpen,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: CdMotion.duration(context, Con.quick),
            color: _pressed ? Con.surface3 : Con.surface2,
            child: Stack(
              children: <Widget>[
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 128),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (state.hollow)
                          Row(
                            children: <Widget>[
                              Container(width: 2, color: state.bar),
                              Container(width: 1, color: Con.ground),
                            ],
                          )
                        else
                          Container(width: state.width, color: state.bar),
                        SizedBox(width: 16 - state.width),
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _Poster(
                            base: widget.base,
                            id: '${item['id']}',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 16,
                                child: Row(
                                  children: <Widget>[
                                    // The state mark, the rule and the age
                                    // are one left group that gives way; the
                                    // duration stays pinned right. This was a
                                    // flat Row with a Spacer, and the state
                                    // mark was an unbounded child of it: Caps
                                    // asks for one line with
                                    // TextOverflow.ellipsis but never got a
                                    // width to honour it against, so a
                                    // scheduled reel overflowed the card by
                                    // 30 pt on a 390 pt phone. Expanded here
                                    // occupies exactly the space the Spacer
                                    // did, so nothing that already fitted
                                    // moves by a pixel.
                                    Expanded(
                                      child: Row(
                                        children: <Widget>[
                                          Flexible(
                                            child: Caps(
                                              state.caps,
                                              color: state.label,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            width: 1,
                                            height: 8,
                                            color: Con.rule,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            ageLabel(
                                              item['created_at'] as String?,
                                            ),
                                            style: Ty.meta.copyWith(
                                              color: Con.ink3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (seconds != null)
                                      Text(
                                        durationLabel(seconds),
                                        style: Ty.meta.copyWith(
                                          color: Con.ink2,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                title,
                                style: Ty.title.copyWith(
                                  color: untitled ? Con.ink2 : Con.ink,
                                  fontSize: 16,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                        lifecycle == 'Publishing'
                                            ? 'Posting since ${clock(DateTime.tryParse(_text(item['updated_at'], '')) ?? DateTime.now())}'
                                            : line3.join('  ·  '),
                                        style: Ty.meta.copyWith(
                                          color: lifecycle == 'Publishing'
                                              ? Con.signalBright
                                              : Con.ink2,
                                        ),
                                      ),
                                    ),
                                    if (rating != null)
                                      RatingMeter(rating: rating),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              CdRejectShake(
                                rejection: widget.failure,
                                child: _actions(item, lifecycle),
                              ),
                              if (widget.failure != null) ...<Widget>[
                                const SizedBox(height: 8),
                                Text(
                                  widget.failure!,
                                  style: Ty.meta.copyWith(
                                    color: Con.failBright,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                    ),
                  ),
                ),
                if (state.posting)
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 2,
                    child: ColoredBox(color: Con.signal),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions(Map<String, dynamic> item, String lifecycle) {
    if (widget.justApproved) {
      return const ConStatusStrip(message: 'Approved');
    }
    final Widget overflow = ConIconButton(
      icon: CupertinoIcons.ellipsis,
      semanticLabel: 'More actions',
      size: 18,
      onPressed: widget.onOverflow,
    );
    final bool live = reelCanReceiveNewIntent(item);
    // Zion asked for scrap, post and edit on the clip card. Scrap was already
    // here; these two were two taps behind the overflow sheet. Edit is an
    // icon button rather than a fifth label because the For review row is
    // already full at 390 pt — "Changes" truncates today — and the styling
    // has to stay the styling. Same ConIconButton as the overflow beside it.
    // Edit rides in the trailing cluster beside the overflow, as an icon
    // button of the same kind and size, on the lifecycles that have room for
    // it. MEASURED at 390 pt the action row has about 278 pt: For review
    // (Approve, Changes, Scrap) and Approved (Schedule, Post now) already
    // consume all of it — a fifth control squeezes Schedule to 19 pt wide and
    // overflows the card. Those two need Zion to say which label he would
    // trade, and it is one line either way.
    final bool showEdit =
        live &&
        const <String>{
          'Scheduled',
          'On hold',
          'Revision queued',
        }.contains(lifecycle);
    final Widget edit = ConIconButton(
      icon: CupertinoIcons.pencil,
      semanticLabel: 'Edit',
      size: 18,
      onPressed: widget.onEdit,
    );
    final String? link = reelPermalink(item);
    final bool canScrap = canScrapReel(item);

    List<Widget> buttons;
    if (widget.failure != null || lifecycle == 'Needs attention') {
      buttons = <Widget>[
        ConButton(
          label: 'Retry',
          kind: ConButtonKind.signalOutline,
          onPressed: () => widget.onRetry(),
        ),
      ];
    } else {
      buttons = switch (lifecycle) {
        'Scrapped' => <Widget>[
          Expanded(
            child: ConButton(
              label: 'Restore',
              kind: ConButtonKind.signalOutline,
              expand: true,
              onPressed: widget.onRestore,
            ),
          ),
        ],
        'Revision queued' => <Widget>[
          Expanded(
            child: ConButton(
              label: 'Open',
              expand: true,
              onPressed: widget.onOpen,
            ),
          ),
          if (canScrap) ...<Widget>[
            const SizedBox(width: 8),
            ConButton(
              label: 'Scrap',
              kind: ConButtonKind.redOutline,
              onPressed: widget.onScrap,
            ),
          ],
        ],
        'Approved' => <Widget>[
          Expanded(
            child: ConButton(
              label: 'Schedule',
              kind: ConButtonKind.signalOutline,
              expand: true,
              onPressed: widget.onSchedule,
            ),
          ),
          const SizedBox(width: 8),
          ConButton(
            label: 'Post now',
            kind: ConButtonKind.redOutline,
            onPressed: widget.onPostNow,
          ),
          // No Edit here either. MEASURED: Schedule, Post now and the
          // overflow already fill the 278 pt this row has at 390 pt — adding
          // an 18 pt icon squeezes Schedule to 19 pt wide. Post beat Edit for
          // an approved reel; Zion can have it the other way round in a line.
        ],
        'Scheduled' || 'On hold' => <Widget>[
          ConButton(label: 'Reschedule', onPressed: widget.onReschedule),
        ],
        'Publishing' => const <Widget>[],
        'Published' => <Widget>[
          if (link != null)
            ConButton(
              label: 'View on Instagram',
              kind: ConButtonKind.ghost,
              leading: CupertinoIcons.arrow_up_right_square,
              onPressed: () => launchUrl(
                Uri.parse(link),
                mode: LaunchMode.externalApplication,
              ),
            ),
        ],
        _ =>
          live
              ? <Widget>[
                  Expanded(
                    child: ConButton(
                      label: coverageMet(item) ? 'Approve' : 'Watch',
                      kind: ConButtonKind.signalFill,
                      leading: coverageMet(item)
                          ? CupertinoIcons.check_mark_circled_solid
                          : CupertinoIcons.play_fill,
                      expand: true,
                      onPressed: coverageMet(item)
                          ? widget.onApprove
                          : widget.onOpen,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ConButton(
                      label: 'Changes',
                      expand: true,
                      onPressed: widget.onChanges,
                    ),
                  ),
                  if (canScrap) ...<Widget>[
                    const SizedBox(width: 8),
                    ConButton(
                      label: 'Scrap',
                      kind: ConButtonKind.redOutline,
                      onPressed: widget.onScrap,
                    ),
                  ],
                  // No Edit here, and it is not an oversight. MEASURED at
                  // 390 pt the For review row has 270 pt for its controls and
                  // Approve / Changes / Scrap / overflow already consume all
                  // of it — "Changes" truncates to "Cha…" on the shipped
                  // build. A fifth control, even an 18 pt icon, overflows the
                  // row. Edit is on the card for every other live lifecycle.
                  // Zion has to say which of Changes or Scrap he would trade
                  // for it here; it is one line either way.
                ]
              : <Widget>[ConButton(label: 'Open', onPressed: widget.onOpen)],
      };
    }

    if (MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 18) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final button in buttons)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: button is Expanded ? button.child : button,
            ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[if (showEdit) edit, overflow],
            ),
          ),
        ],
      );
    }
    return SizedBox(
      height: 44,
      child: Row(
        children: <Widget>[
          ...buttons,
          if (buttons.every((button) => button is! Expanded)) const Spacer(),
          if (showEdit) edit,
          overflow,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SCHEDULE ROW
// ---------------------------------------------------------------------------

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.entry,
    required this.reel,
    required this.base,
    required this.onOpen,
    required this.onOverflow,
    this.onReschedule,
  });
  final Map<String, dynamic> entry, reel;
  final String base;
  final VoidCallback onOpen, onOverflow;
  final VoidCallback? onReschedule;

  String _unsetLabel() => switch (_text(entry['state'], '')) {
    'needs_attention' => 'Needs review',
    'paused' => 'Held',
    'failed' => 'Needs attention',
    _ => 'Unscheduled',
  };

  @override
  Widget build(BuildContext context) {
    final DateTime due = _scheduleDate(entry);
    final bool held = entry['held'] == true || entry['state'] == 'paused';
    final DateTime wall = phoenixWall(due);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: Column(
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(width: 3, color: held ? Con.wait : Con.hold),
                  const SizedBox(width: 13),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SizedBox(
                      width: 78,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            due.year == 9999 ? 'Unset' : wallClock(wall),
                            style: Ty.label.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Con.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Caps(
                            due.year == 9999
                                ? _unsetLabel()
                                : '${_weekdays[wall.weekday - 1]} ${wall.day}',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _Poster(
                      base: base,
                      id: '${reel['id']}',
                      width: 44,
                      height: 64,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const SizedBox(height: 12),
                        Text(
                          _text(reel['title'], 'Untitled reel'),
                          style: Ty.title.copyWith(color: Con.ink),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_text(reel['account'])}  ·  ${scheduleExplanation(entry).split('\n').first}',
                          style: Ty.meta.copyWith(
                            color: held ? Con.wait : Con.ink2,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 44,
                          child: Row(
                            children: <Widget>[
                              if (onReschedule != null)
                                ConButton(
                                  label: 'Reschedule',
                                  onPressed: onReschedule,
                                ),
                              const Spacer(),
                              ConIconButton(
                                icon: CupertinoIcons.ellipsis,
                                semanticLabel: 'Schedule actions',
                                size: 18,
                                onPressed: onOverflow,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
          ),
          const Rule(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ACCOUNT ROW
//
// Exactly one button, and its label is the actual next step.
// ---------------------------------------------------------------------------

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.item,
    required this.purpose,
    required this.onConnect,
  });
  final Map<String, dynamic> item;
  final String purpose;
  final Future<void> Function(String, String) onConnect;

  @override
  Widget build(BuildContext context) {
    final String account = _text(item['account']);
    final dynamic caps = item['capabilities'];
    final String key = purpose == 'insights' ? 'insights' : 'publishing';
    final String state = caps is Map && caps[key] is Map
        ? _text((caps[key] as Map)['status'], 'unknown')
        : 'unknown';
    final bool identified = item['identity_verified'] == true;
    final bool ready =
        state == 'verified' ||
        (purpose == 'publishing' &&
            identified &&
            item['publisher_dry_run'] == true);
    final String next = ready
        ? ''
        : state == 'needs_connect' || state == 'unknown'
        ? 'Connect'
        : identified
        ? 'Finish connection'
        : 'Reconnect';

    return Column(
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Row(
            children: <Widget>[
              Container(
                width: 3,
                height: 76,
                color: ready ? Con.hold : Con.fail,
              ),
              const SizedBox(width: 13),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      Color(0xFF994AD1),
                      Color(0xFFED4264),
                      Color(0xFFF6A34D),
                    ],
                  ),
                ),
                child: const Icon(
                  CupertinoIcons.camera,
                  color: Con.ink,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      account,
                      style: Ty.label.copyWith(
                        color: Con.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ready
                          ? (purpose == 'insights'
                                ? 'Analytics ready'
                                : 'Publishing ready')
                          : state == 'unknown'
                          ? 'Connection not checked'
                          : state.replaceAll('_', ' '),
                      style: Ty.meta.copyWith(color: Con.ink2),
                    ),
                    if (next.isNotEmpty &&
                        MediaQuery.textScalerOf(context).scale(14) > 18)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: ConButton(
                          label: next,
                          onPressed: () => onConnect(account, purpose),
                        ),
                      ),
                  ],
                ),
              ),
              if (next.isNotEmpty &&
                  MediaQuery.textScalerOf(context).scale(14) <= 18)
                ConButton(
                  label: next,
                  onPressed: () => onConnect(account, purpose),
                ),
              const SizedBox(width: 16),
            ],
          ),
        ),
        const Rule(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// THE REEL VIEW
//
// The only place a video player exists. Watch, decide, swipe to the next one,
// without returning to the list.
// ---------------------------------------------------------------------------

typedef ReelAction = Future<void> Function(Map<String, dynamic> item);

/// What a write actually did. `cancelled` is the operator backing out of a
/// confirm sheet, which is not a failure and must not be reported as one;
/// `failed` is the server or the network, which must never be silent.
enum ReelWrite { done, cancelled, failed }

/// A reel action that changes the reel and says what happened. The player uses
/// the answer to decide whether to advance, and to say so on the screen the
/// operator is actually looking at when it did not.
typedef ReelOutcome = Future<ReelWrite> Function(Map<String, dynamic> item);

/// The player's control deck, in whichever box it is being laid out in.
///
/// Under the reel on a phone it is the capped, centred column that shipped.
/// Beside the reel on an iPad it is a fixed-width rail, so it scrolls: the
/// deck is taller than the glass at Larger Text with a failure banner and an
/// approve gate showing, and a rail cannot grow the way a page can.
class _DeckBox extends StatelessWidget {
  const _DeckBox({required this.rail, required this.child});
  final bool rail;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      rail ? SingleChildScrollView(child: child) : ConColumn(child: child);
}

class ReelView extends StatefulWidget {
  const ReelView({
    super.key,
    required this.base,
    required this.items,
    required this.index,
    required this.failureFor,
    required this.onApprove,
    required this.onSchedule,
    required this.onReschedule,
    required this.onChanges,
    required this.onRate,
    required this.onEdit,
    required this.onMarkWatched,
    required this.onWatchBypass,
    required this.onCaption,
    required this.onDetails,
    required this.onNotes,
    required this.onCopyLink,
    required this.onPostNow,
    required this.onCancel,
    required this.onScrap,
    required this.onRestore,
    required this.onRetry,
  });

  final String base;
  final List<Map<String, dynamic>> items;
  final int index;
  final String? Function(Map<String, dynamic>) failureFor;
  final ReelAction onChanges,
      onRate,
      onEdit,
      onCaption,
      onDetails,
      onNotes,
      onCopyLink,
      onWatchBypass;

  /// The writes. Each answers whether the reel actually changed.
  final ReelOutcome onApprove,
      onSchedule,
      onReschedule,
      onPostNow,
      onCancel,
      onScrap,
      onRestore,
      onRetry;
  final Future<void> Function(Map<String, dynamic> item, int duration)
  onMarkWatched;

  @override
  State<ReelView> createState() => _ReelViewState();
}

/// Shown once for the life of the process, not once per reel.
bool _cleanFrameHintShown = false;

class _ReelViewState extends State<ReelView> with WidgetsBindingObserver {
  late int index = widget.index;
  VideoPlayerController? controller;
  Future<void>? ready;
  bool chrome = true;
  bool clean = false;
  bool showHint = false;
  String? playbackIssue;
  bool _lastPlaybackReady = false;
  bool _lastPlaybackError = false;
  int _coverageBuckets = -1;
  Timer? _chromeTimer;
  Timer? _hintTimer;
  Offset? _flash;
  Timer? _flashTimer;
  bool _flashForward = true;

  /// What the last action on this reel actually did. The status strip the rest
  /// of the app uses is rendered by the home page, which is underneath this
  /// route and invisible: a scrap that failed here used to be completely
  /// silent. This is shown in the dock, over the reel the operator is looking
  /// at.
  String? _actionOutcome;
  bool _actionFailed = false;
  bool _actionRunning = false;

  /// True once the preview has spent long enough not initialising that it is
  /// indistinguishable from broken. Without it a reel that answers headers and
  /// then stalls sits on "Reel is loading…" forever with no way forward.
  bool _playbackStalled = false;
  Timer? _stallTimer;
  static const Duration _stallAfter = Duration(seconds: 10);

  Map<String, dynamic> get item => widget.items[index];
  String get sha => '${item['sha256']}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
    if (!_cleanFrameHintShown) {
      _cleanFrameHintShown = true;
      showHint = true;
      _hintTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => showHint = false);
      });
    }
  }

  void _open() {
    playbackIssue = null;
    _lastPlaybackReady = false;
    _lastPlaybackError = false;
    _playbackStalled = false;
    _stallTimer?.cancel();
    _stallTimer = Timer(_stallAfter, () {
      if (!mounted) return;
      if (controller?.value.isInitialized == true) return;
      setState(() => _playbackStalled = true);
    });
    final VideoPlayerController next = VideoPlayerController.networkUrl(
      Uri.parse(
        // The gateway selects a compact derived preview when available and
        // falls back to the exact original export when it is not. Review
        // starts sooner without weakening the exact review identity.
        '${widget.base}/reels/file/${Uri.encodeComponent(item['id'].toString())}.preview',
      ),
      httpHeaders: TrialCredentials.mediaHeaders(widget.base),
    );
    controller = next;
    next.addListener(_tick);
    ready = _initializeController(next);
  }

  Future<void> _initializeController(VideoPlayerController next) async {
    try {
      await next.initialize().timeout(const Duration(seconds: 20));
      // Sound is part of what is being judged.
      await next.setVolume(1);
    } catch (_) {
      if (mounted && identical(controller, next)) {
        setState(() {
          playbackIssue =
              'Reel unavailable. Retry playback before confirming your watch.';
        });
      }
      rethrow;
    }
  }

  void _tick() {
    final VideoPlayerController? c = controller;
    if (c == null) return;
    final bool playbackReady =
        c.value.isInitialized && c.value.duration > Duration.zero;
    final bool playbackChanged =
        playbackReady != _lastPlaybackReady ||
        c.value.hasError != _lastPlaybackError;
    _lastPlaybackReady = playbackReady;
    _lastPlaybackError = c.value.hasError;
    if (!c.value.isInitialized) {
      if (mounted && playbackChanged) setState(() {});
      return;
    }
    // Rounded up, not truncated. inSeconds on a 400 ms asset is 0, and an
    // asset with a total of 0 can never reach the coverage gate at all.
    final int total = _wholeSeconds(c.value.duration);
    if (c.value.isPlaying && total > 0) {
      recordWatched(sha, c.value.position.inSeconds, total);
    }
    final int buckets = _watchedSeconds[sha]?.length ?? 0;
    if (buckets != _coverageBuckets) {
      _coverageBuckets = buckets;
      if (mounted) setState(() {});
    } else if (mounted && playbackChanged) {
      setState(() {});
    }
  }

  static int _wholeSeconds(Duration d) => (d.inMilliseconds / 1000).ceil();

  /// Runs one write against the current reel and reports what happened.
  ///
  /// Every one of these used to be called without `await`, without `setState`
  /// and without advancing or popping: the handler did its work on the home
  /// page, underneath this route, and the player sat there showing the reel
  /// unchanged. Scrap a reel and it was still there. Post now and nothing
  /// visibly happened. Cancel a schedule and the button still said
  /// Reschedule, so it got tapped again.
  Future<ReelWrite> _run(
    ReelOutcome action, {
    required String failureCopy,
    bool advanceOnSuccess = true,
  }) async {
    if (_actionRunning) return ReelWrite.cancelled;
    final Map<String, dynamic> target = item;
    setState(() {
      _actionRunning = true;
      _actionOutcome = null;
      _actionFailed = false;
    });
    ReelWrite result = ReelWrite.failed;
    try {
      result = await action(target);
    } finally {
      if (mounted) setState(() => _actionRunning = false);
    }
    if (!mounted) return result;
    switch (result) {
      case ReelWrite.done:
        if (advanceOnSuccess) _advance();
      case ReelWrite.cancelled:
        // Backing out of a confirm sheet is not a failure and is not reported
        // as one. Nothing changed, so nothing is said and nothing advances.
        break;
      case ReelWrite.failed:
        setState(() {
          // Prefer the cause the failure store recorded for this reel over
          // anything invented here.
          _actionOutcome = widget.failureFor(target) ?? failureCopy;
          _actionFailed = true;
        });
    }
    return result;
  }

  Future<void> _swap(int next) async {
    if (next < 0 || next >= widget.items.length) return;
    final VideoPlayerController? old = controller;
    old?.removeListener(_tick);
    await old?.pause();
    setState(() {
      index = next;
      chrome = true;
      clean = false;
      _coverageBuckets = -1;
      controller = null;
      ready = null;
    });
    await old?.dispose();
    if (!mounted) return;
    setState(_open);
  }

  void _advance() {
    if (index + 1 < widget.items.length) {
      _swap(index + 1);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) controller?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chromeTimer?.cancel();
    _hintTimer?.cancel();
    _flashTimer?.cancel();
    _stallTimer?.cancel();
    controller?.removeListener(_tick);
    controller?.dispose();
    super.dispose();
  }

  void _armChromeHide() {
    _chromeTimer?.cancel();
    _chromeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && (controller?.value.isPlaying ?? false)) {
        setState(() => chrome = false);
      }
    });
  }

  Future<void> _togglePlay() async {
    final VideoPlayerController? c = controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      await c.pause();
      _chromeTimer?.cancel();
      if (mounted) setState(() => chrome = true);
      return;
    }
    if (c.value.position >= c.value.duration) {
      await c.seekTo(Duration.zero);
    }
    await c.play();
    _armChromeHide();
  }

  Future<void> _seekBy(Duration delta) async {
    final VideoPlayerController? c = controller;
    if (c == null || !c.value.isInitialized) return;
    final Duration target = c.value.position + delta;
    await c.seekTo(
      target < Duration.zero
          ? Duration.zero
          : target > c.value.duration
          ? c.value.duration
          : target,
    );
  }

  void _doubleTapSeek(Offset local, double width) {
    final bool forward = local.dx > width / 2;
    _seekBy(Duration(seconds: forward ? 5 : -5));
    _flashTimer?.cancel();
    setState(() {
      _flash = local;
      _flashForward = forward;
    });
    _flashTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  String _time(Duration value) =>
      '${value.inMinutes}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? c = controller;
    final VideoPlayerValue? value = c?.value;
    final bool overlays = chrome && !clean;
    final double coverage = coverageFor(sha);

    return Scaffold(
      backgroundColor: Con.ground,
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints page) {
          // An iPad with room for both puts the deck of controls beside the
          // reel instead of under it: the caption, the receipt, the watch
          // meter and every action stay on screen at the same time as the
          // frame they are about, and the reel gets the rest of the glass
          // rather than a 1366 pt-wide button under a 1366 pt-wide video.
          // Below 900 pt — every iPhone, every Split View pane, and an iPad
          // held in portrait on the small sizes — the deck stays under the
          // reel exactly as it shipped.
          final bool rail = SandLayout.isRoomy(page.maxWidth);
          final double deckWidth =
              ((page.maxWidth * .34).clamp(340.0, 448.0) / 4).roundToDouble() *
              4;
          final Widget stage = SafeArea(
            bottom: rail,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) =>
                  RawGestureDetector(
                    behavior: HitTestBehavior.opaque,
                    gestures: <Type, GestureRecognizerFactory>{
                      TapGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            TapGestureRecognizer
                          >(
                            TapGestureRecognizer.new,
                            (TapGestureRecognizer r) => r.onTap = () {
                              if (!chrome) {
                                setState(() => chrome = true);
                                _armChromeHide();
                              } else {
                                _togglePlay();
                              }
                            },
                          ),
                      DoubleTapGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            DoubleTapGestureRecognizer
                          >(DoubleTapGestureRecognizer.new, (
                            DoubleTapGestureRecognizer r,
                          ) {
                            r.onDoubleTapDown = (TapDownDetails d) =>
                                _doubleTapSeek(d.localPosition, box.maxWidth);
                            r.onDoubleTap = () {};
                          }),
                      LongPressGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            LongPressGestureRecognizer
                          >(
                            () => LongPressGestureRecognizer(
                              duration: const Duration(milliseconds: 250),
                            ),
                            (LongPressGestureRecognizer r) {
                              r.onLongPressStart = (_) =>
                                  setState(() => clean = true);
                              r.onLongPressEnd = (_) =>
                                  setState(() => clean = false);
                              r.onLongPressCancel = () =>
                                  setState(() => clean = false);
                            },
                          ),
                      HorizontalDragGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            HorizontalDragGestureRecognizer
                          >(
                            HorizontalDragGestureRecognizer.new,
                            (HorizontalDragGestureRecognizer r) =>
                                r.onEnd = (DragEndDetails d) {
                                  final double v =
                                      d.velocity.pixelsPerSecond.dx;
                                  if (v < -300) _swap(index + 1);
                                  if (v > 300) _swap(index - 1);
                                },
                          ),
                    },
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: ColoredBox(
                            color: Con.well,
                            child: Center(
                              child: value != null && value.isInitialized
                                  ? AspectRatio(
                                      aspectRatio: value.aspectRatio,
                                      child: VideoPlayer(c!),
                                    )
                                  : ready == null
                                  ? const SizedBox.shrink()
                                  : FutureBuilder<void>(
                                      future: ready,
                                      builder:
                                          (
                                            BuildContext context,
                                            AsyncSnapshot<void> snap,
                                          ) => snap.hasError
                                          ? _PlaybackFailure(
                                              onRetry: () => setState(_open),
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                            ),
                          ),
                        ),
                        if (_flash != null)
                          Positioned(
                            left: _flash!.dx - 20,
                            top: _flash!.dy - 20,
                            child: Container(
                              width: 40,
                              height: 40,
                              color: Con.surface1.withValues(alpha: 0.92),
                              child: Center(
                                child: Seek5Glyph(
                                  forward: _flashForward,
                                  color: Con.ink,
                                ),
                              ),
                            ),
                          ),
                        if (showHint)
                          Center(
                            child: Container(
                              color: Con.surface1,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Text(
                                'Hold to see the frame clean.',
                                style: Ty.meta.copyWith(color: Con.ink),
                              ),
                            ),
                          ),
                        if (overlays) _topBar(),
                        if (overlays && value != null && value.isInitialized)
                          _transport(value),
                        if (overlays && value != null && value.isInitialized)
                          _scrub(value, box.maxWidth),
                      ],
                    ),
                  ),
            ),
          );
          return rail
              ? Row(
                  // The rail runs the full height beside the reel, so its
                  // seam is a full-height hairline rather than a floating
                  // box.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: stage),
                    SizedBox(
                      width: deckWidth,
                      child: _dock(coverage, rail: true),
                    ),
                  ],
                )
              : Column(
                  children: <Widget>[
                    Expanded(child: stage),
                    _dock(coverage),
                  ],
                );
        },
      ),
    );
  }

  Widget _topBar() => Positioned(
    left: 0,
    right: 0,
    top: 0,
    height: 44,
    child: ColoredBox(
      color: Con.ground.withValues(alpha: 0.88),
      child: Row(
        children: <Widget>[
          ConIconButton(
            icon: CupertinoIcons.chevron_down,
            semanticLabel: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const Spacer(),
          Text(
            '${index + 1} / ${widget.items.length}',
            style: Ty.meta.copyWith(color: Con.ink2),
          ),
          const Spacer(),
          ConIconButton(
            icon: CupertinoIcons.ellipsis,
            semanticLabel: 'More actions',
            onPressed: _overflow,
          ),
        ],
      ),
    ),
  );

  Widget _transport(VideoPlayerValue value) => Positioned(
    left: 0,
    right: 0,
    bottom: 24,
    height: 44,
    child: Row(
      children: <Widget>[
        const Spacer(),
        ConIconButton(
          glyph: const Seek5Glyph(forward: false, color: Con.ink),
          semanticLabel: 'Back 5 seconds',
          color: Con.ink,
          onPressed: () => _seekBy(const Duration(seconds: -5)),
        ),
        const SizedBox(width: 24),
        ConIconButton(
          icon: value.isPlaying
              ? CupertinoIcons.pause_fill
              : CupertinoIcons.play_fill,
          semanticLabel: value.isPlaying ? 'Pause' : 'Play',
          color: Con.ink,
          size: 28,
          onPressed: _togglePlay,
        ),
        const SizedBox(width: 24),
        ConIconButton(
          glyph: const Seek5Glyph(forward: true, color: Con.ink),
          semanticLabel: 'Forward 5 seconds',
          color: Con.ink,
          onPressed: () => _seekBy(const Duration(seconds: 5)),
        ),
        const Spacer(),
        Text(
          '${_time(value.position)} / ${_time(value.duration)}',
          style: Ty.meta.copyWith(color: Con.ink2),
        ),
        const SizedBox(width: 16),
      ],
    ),
  );

  Widget _scrub(VideoPlayerValue value, double width) {
    final double total = value.duration.inMilliseconds.toDouble();
    final double played = total <= 0
        ? 0
        : (value.position.inMilliseconds / total).clamp(0, 1);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 24,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (DragUpdateDetails d) {
          if (total <= 0) return;
          final double fraction = (d.localPosition.dx / width).clamp(0, 1);
          controller?.seekTo(
            Duration(milliseconds: (fraction * total).round()),
          );
        },
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: 2,
            child: Stack(
              children: <Widget>[
                const Positioned.fill(child: ColoredBox(color: Con.rule)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: played,
                  child: const ColoredBox(color: Con.signal),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dock(double coverage, {bool rail = false}) {
    final String? failure = widget.failureFor(item);
    final String lifecycle = reelLifecycle(item);
    final bool live = reelCanReceiveNewIntent(item);
    final String caption = _text(item['caption'], '');
    final String? receipt = reelReceiptSummary(item);
    final bool videoReady =
        controller?.value.isInitialized == true &&
        (controller?.value.duration ?? Duration.zero) > Duration.zero;
    final bool videoUnavailable =
        playbackIssue != null || controller?.value.hasError == true;
    final bool videoLoading = !videoReady && !videoUnavailable;
    // Broken, or indistinguishable from broken: no route forward without it.
    final bool playbackBroken =
        videoUnavailable || (videoLoading && _playbackStalled);

    return Container(
      // Keyed so a test can measure the deck against the reel beside it.
      key: const ValueKey<String>('player-deck'),
      decoration: BoxDecoration(
        color: Con.ground,
        // The same hairline, on whichever edge the deck is attached to.
        border: Border(
          top: rail ? BorderSide.none : const BorderSide(color: Con.ruleStrong),
          left: rail
              ? const BorderSide(color: Con.ruleStrong)
              : BorderSide.none,
        ),
      ),
      child: SafeArea(
        top: rail,
        // The video stays full bleed, because a reel is the content. Under
        // it on a phone, beside it on an iPad — and a rail is a fixed height,
        // so the deck scrolls there rather than overflowing at Larger Text.
        child: _DeckBox(
          rail: rail,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  height: 40,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onCaption(item),
                    child: caption.isEmpty
                        ? Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  'No caption set',
                                  style: Ty.body.copyWith(color: Con.ink3),
                                ),
                              ),
                              ConButton(
                                label: 'Add caption',
                                kind: ConButtonKind.ghost,
                                onPressed: () => widget.onCaption(item),
                              ),
                            ],
                          )
                        : Text(
                            caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Ty.body.copyWith(color: Con.ink2),
                          ),
                  ),
                ),
                if (receipt != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(receipt, style: Ty.meta.copyWith(color: Con.ink2)),
                ],
                // The receipt for an action taken from inside the player. The
                // app's status strip is rendered by the home page, which is
                // underneath this route: a scrap or a post that failed here was
                // completely silent, and an approve that failed still advanced
                // to the next reel. Silent failure is the thing to kill.
                if (_actionOutcome case final String outcome) ...<Widget>[
                  const SizedBox(height: 8),
                  ConBanner(
                    headline: _actionFailed
                        ? 'That did not go through'
                        : 'Done',
                    detail: outcome,
                    tone: _actionFailed ? Con.fail : Con.signal,
                    actionLabel: 'Dismiss',
                    onAction: () => setState(() {
                      _actionOutcome = null;
                      _actionFailed = false;
                    }),
                  ),
                ],
                const SizedBox(height: 12),
                // The way out of review when the preview will not play.
                //
                // This control used to be disabled in exactly the states it
                // exists for: `videoReady && !videoUnavailable`. A reel whose
                // preview 404s, 401s or stalls could therefore never be
                // approved, scheduled or posted — only scrapped — because
                // coverage is only ever written while the asset is actually
                // playing. Its own zero-duration guard was dead code: it could
                // not run without the enabled condition it contradicted.
                //
                // Broken playback now enables the button with copy that says
                // what it is, and the approve payload carries
                // watch_observed: false so the audit trail stays honest.
                if (coverage < coverageGate &&
                    live &&
                    lifecycle == 'For review' &&
                    failure == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ConButton(
                      label: videoReady && !videoUnavailable
                          ? 'I watched this reel'
                          : playbackBroken
                          ? 'Playback is broken — approve without watching'
                          : 'Reel is loading…',
                      kind: ConButtonKind.ghost,
                      height: 40,
                      expand: true,
                      onPressed: videoReady && !videoUnavailable
                          ? () async {
                              await widget.onMarkWatched(
                                item,
                                _wholeSeconds(
                                  controller?.value.duration ?? Duration.zero,
                                ),
                              );
                              if (mounted) setState(() {});
                            }
                          : playbackBroken
                          ? () async {
                              await widget.onWatchBypass(item);
                              if (mounted) setState(() {});
                            }
                          : null,
                    ),
                  ),
                _primary(coverage, lifecycle, live, failure),
                const SizedBox(height: 8),
                if (live && lifecycle != 'Published') ...<Widget>[
                  ConButton(
                    label: 'Edit reel',
                    kind: ConButtonKind.signalOutline,
                    height: 40,
                    expand: true,
                    onPressed: () => widget.onEdit(item),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: <Widget>[
                    Expanded(
                      child: ConButton(
                        label: 'Request changes',
                        expand: true,
                        height: 40,
                        onPressed: () => widget.onChanges(item),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ConButton(
                        label: 'Rate',
                        expand: true,
                        height: 40,
                        onPressed: () => widget.onRate(item),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _primary(
    double coverage,
    String lifecycle,
    bool live,
    String? failure,
  ) {
    if (failure != null || lifecycle == 'Needs attention') {
      return ConButton(
        label: 'Retry',
        kind: ConButtonKind.redOutline,
        height: 48,
        expand: true,
        onPressed: () => _run(
          widget.onRetry,
          failureCopy: 'Retry failed. The reel still needs attention.',
          advanceOnSuccess: false,
        ),
      );
    }
    switch (lifecycle) {
      case 'Published':
        final String? link = reelPermalink(item);
        return link == null
            ? SizedBox(
                height: 48,
                child: Center(
                  child: Text(
                    'Published. See Results for performance.',
                    style: Ty.body.copyWith(color: Con.ink2),
                  ),
                ),
              )
            : ConButton(
                label: 'View published reel',
                kind: ConButtonKind.signalOutline,
                height: 48,
                expand: true,
                leading: CupertinoIcons.arrow_up_right_square,
                onPressed: () => launchUrl(
                  Uri.parse(link),
                  mode: LaunchMode.externalApplication,
                ),
              );
      case 'Publishing':
        return Container(
          height: 48,
          decoration: BoxDecoration(
            color: Con.surface2,
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Text(
            'Posting since ${clock(DateTime.tryParse(_text(item['updated_at'], '')) ?? DateTime.now())}',
            style: Ty.label.copyWith(color: Con.ink3),
          ),
        );
      case 'Scheduled':
      case 'On hold':
        return ConButton(
          label: 'Reschedule',
          height: 48,
          expand: true,
          onPressed: () => _run(
            widget.onReschedule,
            failureCopy: 'Reschedule failed. The old time still stands.',
            advanceOnSuccess: false,
          ),
        );
      case 'Scrapped':
        return ConButton(
          label: 'Restore reel',
          kind: ConButtonKind.signalOutline,
          height: 48,
          expand: true,
          onPressed: () => _run(
            widget.onRestore,
            failureCopy: 'Restore failed. The reel is still scrapped.',
          ),
        );
      case 'Revision queued':
        return ConButton(
          label: 'Open change request',
          height: 48,
          expand: true,
          onPressed: () => widget.onNotes(item),
        );
      case 'Approved':
        return _SplitPrimary(
          label: 'Schedule',
          armed: true,
          coverage: 1,
          showDoor: false,
          onCommit: () => _run(
            widget.onSchedule,
            failureCopy: 'Schedule failed. The reel has not been given a time.',
          ),
          onDoor: null,
        );
      default:
        if (!live) {
          return ConButton(
            label: 'Open change request',
            height: 48,
            expand: true,
            onPressed: () => widget.onNotes(item),
          );
        }
        return _SplitPrimary(
          label: 'Approve',
          armed: coverage >= coverageGate,
          coverage: coverage,
          showDoor: true,
          // Approve used to advance to the next reel whether or not the
          // approve landed, so a failure looked exactly like a success.
          onCommit: () => _run(
            widget.onApprove,
            failureCopy: 'Approve failed. The reel is still in review.',
          ),
          onDoor: coverage >= coverageGate
              ? () => _run(
                  widget.onSchedule,
                  failureCopy:
                      'Schedule failed. The reel has not been given a time.',
                )
              : null,
        );
    }
  }

  Future<void> _overflow() async {
    final bool canScrap = canScrapReel(item);
    final bool canRestore = canRestoreReel(item);
    await showConSheet<void>(
      context,
      (BuildContext sheet) => ConSheet(
        title: _text(item['title'], _text(item['id'])),
        children: <Widget>[
          ConSheetRow(
            label: 'Edit reel',
            onTap: () {
              Navigator.of(sheet).pop();
              widget.onEdit(item);
            },
          ),
          ConSheetRow(
            label: 'Edit music',
            onTap: () {
              Navigator.of(sheet).pop();
              widget.onEdit(item);
            },
          ),
          ConSheetRow(
            label: 'Edit caption',
            onTap: () {
              Navigator.of(sheet).pop();
              widget.onCaption(item);
            },
          ),
          ConSheetRow(
            label: 'Copy private clip link',
            onTap: () {
              Navigator.of(sheet).pop();
              widget.onCopyLink(item);
            },
          ),
          ConSheetRow(
            label: 'Notes',
            onTap: () {
              Navigator.of(sheet).pop();
              widget.onNotes(item);
            },
          ),
          ConSheetRow(
            label: 'Details',
            onTap: () {
              Navigator.of(sheet).pop();
              widget.onDetails(item);
            },
          ),
          if (_reviewApproved(item) && reelCanReceiveNewIntent(item))
            ConSheetRow(
              label: 'Post now',
              labelColor: Con.failBright,
              onTap: () {
                Navigator.of(sheet).pop();
                _run(
                  widget.onPostNow,
                  failureCopy: 'Post failed. The reel has not been posted.',
                );
              },
            ),
          if (item['schedule_detail'] is Map)
            ConSheetRow(
              label: 'Cancel schedule',
              labelColor: Con.failBright,
              onTap: () {
                Navigator.of(sheet).pop();
                _run(
                  widget.onCancel,
                  failureCopy:
                      'Cancel failed. The reel is still scheduled to post.',
                  advanceOnSuccess: false,
                );
              },
            ),
          if (canRestore)
            ConSheetRow(
              label: 'Restore reel',
              onTap: () {
                Navigator.of(sheet).pop();
                _run(
                  widget.onRestore,
                  failureCopy: 'Restore failed. The reel is still scrapped.',
                );
              },
            ),
          if (canScrap)
            ConSheetRow(
              label: 'Scrap reel',
              labelColor: Con.failBright,
              onTap: () {
                Navigator.of(sheet).pop();
                _run(
                  widget.onScrap,
                  failureCopy: 'Scrap failed. The reel is still in review.',
                );
              },
            ),
        ],
      ),
    );
  }
}

/// The primary: one object, two segments, one fill. Below the coverage gate it
/// is a flat locked plate carrying its own progress; at the gate it arms, and
/// commits only on a 600ms hold. That keeps `confirm` an operator act rather
/// than an inference, which is a stronger audit trail than a checkbox.
class _SplitPrimary extends StatefulWidget {
  const _SplitPrimary({
    required this.label,
    required this.armed,
    required this.coverage,
    required this.showDoor,
    required this.onCommit,
    required this.onDoor,
  });
  final String label;
  final bool armed, showDoor;
  final double coverage;
  final Future<ReelWrite> Function() onCommit;
  final Future<ReelWrite> Function()? onDoor;

  @override
  State<_SplitPrimary> createState() => _SplitPrimaryState();
}

class _SplitPrimaryState extends State<_SplitPrimary>
    with SingleTickerProviderStateMixin {
  // Built in initState, not lazily. `build` only reads this controller inside
  // `if (armed)` and inside tap closures that never fire for a disarmed
  // button, so on a reel the operator has not watched it was never
  // constructed during the widget's life and `dispose()` was its first read —
  // which constructs a Ticker against an already-deactivated element. A
  // release build compiles the assertion out and orphans a Ticker and its
  // TickerMode listener on every reel close; debug and profile builds throw.
  late final AnimationController hold;
  bool _armedLast = false;

  @override
  void initState() {
    super.initState();
    hold = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addStatusListener(_onStatus);
  }

  bool _committing = false;

  Future<void> _onStatus(AnimationStatus status) async {
    if (status != AnimationStatus.completed || _committing) return;
    HapticFeedback.selectionClick();
    // The commit is awaited, and the hold only resets once it has answered.
    // Resetting first let a second 600 ms hold start while the first approve
    // was still in flight; only the server's idempotency key stopped that
    // being a double effect.
    _committing = true;
    try {
      await widget.onCommit();
    } finally {
      _committing = false;
      if (mounted) hold.value = 0;
    }
  }

  @override
  void didUpdateWidget(_SplitPrimary old) {
    super.didUpdateWidget(old);
    if (widget.armed && !_armedLast) {
      _armedLast = true;
      HapticFeedback.selectionClick();
    }
    if (!widget.armed) _armedLast = false;
  }

  @override
  void dispose() {
    hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool armed = widget.armed;
    return SizedBox(
      height: 48,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              button: true,
              enabled: armed,
              label: armed
                  ? '${widget.label}. Press and hold to confirm'
                  : 'Watch ${(widget.coverage * 100).round()} percent of 80 before approving',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: armed ? (_) => hold.forward() : null,
                onTapUp: armed ? (_) => hold.reverse() : null,
                onTapCancel: armed ? () => hold.reverse() : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 48,
                  decoration: BoxDecoration(
                    color: armed ? Con.signal : Con.surface2,
                    borderRadius: widget.showDoor
                        ? const BorderRadius.horizontal(
                            left: Radius.circular(4),
                          )
                        : BorderRadius.circular(4),
                  ),
                  child: ClipRRect(
                    borderRadius: widget.showDoor
                        ? const BorderRadius.horizontal(
                            left: Radius.circular(4),
                          )
                        : BorderRadius.circular(4),
                    child: Stack(
                      children: <Widget>[
                        if (armed)
                          AnimatedBuilder(
                            animation: hold,
                            builder: (BuildContext context, Widget? child) =>
                                FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: hold.value,
                                  child: const ColoredBox(
                                    color: Con.signalBright,
                                  ),
                                ),
                          ),
                        Center(
                          child: Text(
                            widget.label,
                            style: Ty.label.copyWith(
                              color: armed ? Con.onSignal : Con.ink3,
                            ),
                          ),
                        ),
                        // How much of the reel has been watched, against
                        // the gate that unlocks Approve. It was measured
                        // against MediaQuery.sizeOf(context).width — the
                        // whole screen — and drawn inside a button that is
                        // narrower than the screen by the deck's 32 pt of
                        // padding and, when the schedule door is showing, a
                        // further 56 pt. The bar therefore filled the button
                        // at 77% watched on a 390 pt phone and the ClipRRect
                        // hid the rest, so it read "done" while Approve was
                        // still disabled and Zion had no way to tell how much
                        // was left. A fraction of the button is a fraction of
                        // the button.
                        if (!armed)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: 2,
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: widget.coverage,
                              child: const ColoredBox(
                                key: ValueKey<String>('watch-coverage'),
                                color: Con.signal,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.showDoor) ...<Widget>[
            Container(width: 1, height: 48, color: Con.ground),
            Semantics(
              button: true,
              enabled: widget.onDoor != null,
              label: 'Approve and schedule',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDoor,
                child: Container(
                  width: 55,
                  height: 48,
                  decoration: BoxDecoration(
                    color: armed ? Con.signal : Con.surface2,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(4),
                    ),
                  ),
                  child: Icon(
                    CupertinoIcons.calendar,
                    size: 20,
                    color: armed ? Con.onSignal : Con.ink3,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlaybackFailure extends StatelessWidget {
  const _PlaybackFailure({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const TrialMark(size: 32, color: Con.ink3, dotColor: Con.ink3),
        const SizedBox(height: 16),
        Text(
          'Could not load this reel',
          style: Ty.title.copyWith(color: Con.ink),
        ),
        const SizedBox(height: 8),
        Text(
          'Check the connection and try again.',
          textAlign: TextAlign.center,
          style: Ty.body.copyWith(color: Con.ink2),
        ),
        const SizedBox(height: 16),
        ConButton(
          label: 'Retry',
          kind: ConButtonKind.signalOutline,
          onPressed: onRetry,
        ),
      ],
    ),
  );
}

/// Kept as a small public error surface for existing host diagnostics.
class GatewayErrorView extends StatelessWidget {
  const GatewayErrorView({
    super.key,
    required this.host,
    required this.reason,
    required this.onRetry,
    required this.onSwitchHost,
  });
  final String host, reason;
  final VoidCallback onRetry, onSwitchHost;
  @override
  Widget build(BuildContext c) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            "Can't open Content Doctor",
            style: Ty.title.copyWith(color: Con.ink),
          ),
          const SizedBox(height: 12),
          Text(host, style: Ty.meta.copyWith(color: Con.ink2)),
          if (reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                reason,
                textAlign: TextAlign.center,
                style: Ty.body.copyWith(color: Con.ink2),
              ),
            ),
          const SizedBox(height: 16),
          ConButton(
            label: 'Try again',
            kind: ConButtonKind.signalOutline,
            onPressed: onRetry,
          ),
          const SizedBox(height: 8),
          ConButton(
            label: 'Switch host',
            kind: ConButtonKind.ghost,
            onPressed: onSwitchHost,
          ),
        ],
      ),
    ),
  );
}

class HostSheet extends StatelessWidget {
  const HostSheet({super.key, required this.current});
  final String current;
  @override
  Widget build(BuildContext c) => ConSheet(
    title: 'Choose connection',
    children: <Widget>[
      for (final GatewayHost host in knownHosts)
        ConSheetRow(
          label: host.label,
          detail: host.note,
          height: 56,
          selected: host.url == current,
          onTap: () =>
              Navigator.of(c).pop(host.url == current ? null : host.url),
        ),
    ],
  );
}

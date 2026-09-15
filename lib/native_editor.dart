// The GridView image callback must accept all three framework parameters;
// the ignored values are intentionally unnamed in this compact editor.
// ignore_for_file: unnecessary_underscores

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'app_experience.dart';
import 'app_theme.dart';
import 'console_shell.dart';
import 'render_jobs.dart';
import 'trial_credentials.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
/// The default caption look for a fresh export, per account. Gabe's is a
/// standing, repeatedly confirmed spec (recovered 2026-09-15 from three
/// independent dated sources: the 2026-09-11 caption profile, the A-word-v6
/// review, MASTER-PROMPT.md): 160px centered Roboto Condensed Regular,
/// butter yellow #FFEBA8, no outline. The style name sent to the server is
/// still the generic 'center_yellow' -- 'reel_gate.py' remaps it to the
/// Gabe-locked font/size automatically for any Gabe account, so this only
/// needs to pick the right generic name and the matching preview color, not
/// the font itself. Not applied to '@gabejlove': it has no assigned content
/// and no confirmed preference of its own -- the account exists in the
/// picker but is collect-only.
class CaptionDefaults {
  const CaptionDefaults({
    required this.style,
    required this.color,
    required this.sizePx,
  });
  final String style;
  final String color;
  final double sizePx;
}

const Set<String> gabeCaptionAccounts = <String>{
  '@barcrawling',
  '@barcrawls.arizona',
};

CaptionDefaults captionDefaultsForAccount(String account) =>
    gabeCaptionAccounts.contains(account)
    ? const CaptionDefaults(
        style: 'center_yellow',
        color: '#FFEBA8',
        sizePx: 160,
      )
    : const CaptionDefaults(
        style: 'center_white',
        color: '#FFFFFF',
        sizePx: 68,
      );

class TrialReelEditDraft {
  const TrialReelEditDraft({
    required this.sourceReelId,
    required this.inPoint,
    required this.outPoint,
    required this.caption,
    required this.captionStyle,
    required this.captionColor,
    required this.captionX,
    required this.captionY,
    this.captionSize = 68,
    this.musicAssetId,
    required this.musicCueSeconds,
  });
  final String sourceReelId, caption, captionStyle, captionColor;
  final double inPoint,
      outPoint,
      musicCueSeconds,
      captionX,
      captionY,
      captionSize;
  final String? musicAssetId;
  Map<String, Object?> toJson() => <String, Object?>{
    'source_reel_id': sourceReelId,
    'trim_in_seconds': inPoint,
    'trim_out_seconds': outPoint,
    'caption': caption,
    'caption_style': captionStyle,
    'caption_color': captionColor,
    'caption_x_percent': captionX,
    'caption_y_percent': captionY,
    'caption_size_px': captionSize,
    'music_asset_id': musicAssetId,
    'music_cue_seconds': musicCueSeconds,
  };
}

List<Map<String, dynamic>> parseMusicAssets(dynamic data) {
  final dynamic raw = data is List
      ? data
      : (data is Map ? data['assets'] : null);
  if (raw is! List) return <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((x) => Map<String, dynamic>.from(x))
      .where((x) => x['id'] != null && x['approved'] != false)
      .toList();
}

class NativeReelEditor extends StatefulWidget {
  const NativeReelEditor({
    super.key,
    required this.base,
    this.onReviewReady,
    this.openReview,
    this.requestOverride,
    this.allowedAccounts,
    this.initialReel,
    this.collectOnly = false,
    this.allowDirectRender = false,
  });
  final String base;
  final bool collectOnly;

  /// Enables only the existing review-only render path for a scoped role.
  /// It deliberately does not grant source-library or generation access.
  final bool allowDirectRender;
  final Map<String, dynamic>? initialReel;
  final ValueChanged<String>? onReviewReady;
  final VoidCallback? openReview;
  final Future<dynamic> Function(String, String, Map<String, Object?>?)?
  requestOverride;
  final List<String>? allowedAccounts;
  @override
  State<NativeReelEditor> createState() => _NativeReelEditorState();
}

class _NativeReelEditorState extends State<NativeReelEditor> {
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  List<Map<String, dynamic>> reels = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> libraryAssets = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> musicAssets = <Map<String, dynamic>>[];
  Map<String, Map<String, dynamic>> sourceTaste =
      <String, Map<String, dynamic>>{};
  Map<String, dynamic>? sourceFinalists;
  String? sourceId, musicAssetId, jobId, status, error, reviewId;
  double inPoint = 0, outPoint = 30, cue = 0, captionX = 50, captionY = 50;
  double captionSize = 68;
  String editorAccount = '@zionboggan';
  final caption = TextEditingController();
  final revisionBrief = TextEditingController();
  String cadence = 'Preserve existing pacing';
  String style = 'center_white', captionColor = '#FFFFFF';
  // Overwritten in initState() and on account switch by
  // _applyCaptionDefaultsForAccount(), which knows Gabe's locked spec.
  bool loading = true, sending = false;
  int visibleLibraryCount = 24;
  int? libraryNext;
  bool loadingMore = false;
  int _catalogGeneration = 0;
  final Set<String> savingTaste = <String>{};
  int _previewAttempt = 0;
  bool showLibrary = true;
  String? libraryError;
  final Set<String> bulkSourceIds = <String>{};
  final Map<String, String> renderKeys = <String, String>{};
  final RenderJobs renderJobs = RenderJobs();
  final Map<String, List<Map<String, dynamic>>> sequenceDrafts = {};
  List<Map<String, dynamic>> get sequenceShots =>
      sequenceDrafts.putIfAbsent(editorAccount, () => []);
  final sequenceTitle = TextEditingController(text: 'Studio sequence');
  double get sequenceDuration => sequenceShots.fold<double>(
    0,
    (sum, shot) =>
        sum +
        _sequenceNumber(shot['trim_out_seconds']) -
        _sequenceNumber(shot['trim_in_seconds']),
  );
  double _sequenceNumber(dynamic value) =>
      value is num && value.isFinite ? value.toDouble() : double.nan;
  bool get validSequence {
    if (sequenceShots.isEmpty ||
        sequenceShots.length > 12 ||
        !sequenceDuration.isFinite ||
        sequenceDuration > 90) {
      return false;
    }
    return sequenceShots.every((shot) {
      final double start = _sequenceNumber(shot['trim_in_seconds']);
      final double end = _sequenceNumber(shot['trim_out_seconds']);
      final Map? item = shot['item'] is Map ? shot['item'] as Map : null;
      final double? duration = item == null
          ? null
          : double.tryParse('${item['duration_seconds'] ?? ''}');
      return start.isFinite &&
          end.isFinite &&
          start >= 0 &&
          end - start >= .5 &&
          (duration == null || (duration.isFinite && duration >= end));
    });
  }

  bool pollingJobs = false;
  String get jobStorageKey => 'trial.studio-jobs:${widget.base}';
  bool get canCreateReviewExports =>
      !widget.collectOnly || widget.allowDirectRender;
  bool get canBrowseSourceLibrary => !widget.collectOnly;
  Set<String> get allowedEditorAccounts =>
      (widget.allowedAccounts ??
              const <String>[
                '@zionboggan',
                '@barcrawls.arizona',
                '@barcrawling',
                '@gabejlove',
              ])
          .toSet();
  Iterable<Map<String, dynamic>> get visibleRenderJobs => renderJobs.items
      .where((job) => allowedEditorAccounts.contains(job['account']));
  Iterable<Map<String, dynamic>> get pendingRenderJobs =>
      widget.collectOnly && !widget.allowDirectRender
      ? const <Map<String, dynamic>>[]
      : visibleRenderJobs.where(
          (job) => ['queued', 'rendering'].contains(job['status']),
        );

  void _applyCaptionDefaultsForAccount(String account) {
    final CaptionDefaults defaults = captionDefaultsForAccount(account);
    style = defaults.style;
    captionColor = defaults.color;
    captionSize = defaults.sizePx;
    captionX = 50;
    captionY = 50;
  }

  @override
  void initState() {
    super.initState();
    final List<String>? permitted = widget.allowedAccounts;
    if (permitted != null && permitted.isNotEmpty) {
      editorAccount = permitted.first;
    }
    final initial = widget.initialReel;
    if (initial != null &&
        (permitted == null || permitted.contains(initial['account']))) {
      editorAccount = initial['account'].toString();
      sourceId = initial['id'].toString();
      showLibrary = false;
    }
    _applyCaptionDefaultsForAccount(editorAccount);
    restoreJobs();
  }

  Future<void> restoreJobs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonDecode(prefs.getString(jobStorageKey) ?? '{}');
      if (raw is Map) {
        renderJobs.restore(raw['jobs']);
        if (raw['sequences'] is Map) {
          for (final entry in (raw['sequences'] as Map).entries) {
            if (entry.key is String && entry.value is List) {
              sequenceDrafts[entry.key] = (entry.value as List)
                  .whereType<Map>()
                  .map((row) => Map<String, dynamic>.from(row))
                  .toList();
            }
          }
        }
        if (raw['keys'] is Map) {
          for (final entry in (raw['keys'] as Map).entries) {
            if (entry.key is String && entry.value is String) {
              renderKeys[entry.key] = entry.value;
            }
          }
        }
      }
    } catch (_) {
      /* A damaged local receipt must not block the editor. */
    }
    if (!mounted) return;
    await loadCatalog();
    if (mounted && widget.initialReel != null && sourceId != null) {
      selectSource(sourceId);
      final initial = widget.initialReel!;
      final manifest = initial['source_manifest'];
      final raw =
          initial['shots'] ?? (manifest is Map ? manifest['shots'] : null);
      if (raw is List && raw.isNotEmpty) {
        final restored = <Map<String, dynamic>>[];
        for (final value in raw.whereType<Map>()) {
          final id = value['source_reel_id'] ?? value['asset_id'];
          final matches = sources.where(
            (asset) => asset['id'] == id && asset['account'] == editorAccount,
          );
          final start = value['trim_in_seconds'];
          final end = value['trim_out_seconds'];
          if (matches.isEmpty ||
              start is! num ||
              end is! num ||
              start < 0 ||
              end <= start) {
            continue;
          }
          final asset = matches.first;
          if (value['sha256'] != null && value['sha256'] != asset['sha256']) {
            continue;
          }
          restored.add({
            'source_reel_id': id,
            'trim_in_seconds': start.toDouble(),
            'trim_out_seconds': end.toDouble(),
            'title': asset['title'] ?? id,
            'item': asset,
          });
        }
        if (restored.length == raw.length && restored.length <= 12) {
          setState(() => sequenceDrafts[editorAccount] = restored);
        }
      }
    }
    if (mounted && pendingRenderJobs.isNotEmpty) poll();
  }

  Future<void> persistJobs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        jobStorageKey,
        jsonEncode({
          'jobs': renderJobs.toJson(),
          'keys': renderKeys,
          'sequences': sequenceDrafts,
        }),
      );
    } catch (_) {
      /* In-memory receipts remain available if device storage fails. */
    }
  }

  @override
  void dispose() {
    client.close(force: true);
    caption.dispose();
    revisionBrief.dispose();
    sequenceTitle.dispose();
    super.dispose();
  }

  Future<dynamic> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (widget.requestOverride != null) {
      return widget.requestOverride!(method, path, body);
    }
    final HttpClientRequest req = method == 'GET'
        ? await client.getUrl(Uri.parse('${widget.base}$path'))
        : await client.postUrl(Uri.parse('${widget.base}$path'));
    if (method == 'GET') {
      await TrialCredentials.attachIfAvailable(req, widget.base);
    } else {
      await TrialCredentials.attach(req, widget.base);
    }
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
    }
    final HttpClientResponse res = await req.close().timeout(
      const Duration(seconds: 15),
    );
    final dynamic decoded = jsonDecode(
      await utf8.decoder.bind(res).join().timeout(const Duration(seconds: 15)),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        decoded is Map
            ? decoded['detail'] ?? decoded['error'] ?? 'Gateway request failed'
            : 'Gateway request failed',
      );
    }
    return decoded;
  }

  Future<void> loadCatalog() async {
    final int generation = ++_catalogGeneration;
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
        libraryError = null;
      });
    }
    try {
      // Existing reels are the first useful editor surface. Render them before
      // loading optional library, music and taste data so a slow source index
      // cannot make the whole editor appear frozen.
      final dynamic data = await request('GET', '/reels/catalog');
      if (!mounted || generation != _catalogGeneration) return;
      final List<dynamic> list = data is List
          ? data
          : (data['items'] ?? data['reels'] ?? <dynamic>[]);
      if (mounted) {
        setState(() {
          reels = list
              .whereType<Map>()
              .map((x) => Map<String, dynamic>.from(x))
              .where((x) => x['id'] != null && x['status'] != 'archived')
              .toList();
          loading = false;
        });
      }
      final Future<dynamic> libraryRequest = canBrowseSourceLibrary
          ? request(
              'GET',
              '/reels/library?limit=60&account=${Uri.encodeComponent(editorAccount)}',
            ).catchError(
              (Object _) => <String, dynamic>{'_library_error': true},
            )
          : Future<dynamic>.value(<String, dynamic>{'assets': <dynamic>[]});
      final Future<dynamic> musicRequest = request(
        'GET',
        '/reels/music?account=${Uri.encodeComponent(editorAccount)}',
      ).catchError((Object _) => <String, dynamic>{});
      final Future<dynamic> tasteRequest = canBrowseSourceLibrary
          ? request(
              'GET',
              '/reels/source-taste?account=${Uri.encodeComponent(editorAccount)}',
            ).catchError((Object _) => <String, dynamic>{})
          : Future<dynamic>.value(<String, dynamic>{});
      // source-finalists is deliberately not fetched here. Nothing in build()
      // reads it -- it is only ever the contents of the "Review shortlist"
      // dialog -- and on the first editor open after a backend restart it is
      // the slowest of these requests, because the server re-hashes every
      // reviewed source clip on its first call per process. It is fetched on
      // demand instead, in openFinalistSummary().
      final List<dynamic> results = await Future.wait<dynamic>(
        <Future<dynamic>>[libraryRequest, musicRequest, tasteRequest],
      );
      if (!mounted || generation != _catalogGeneration) return;
      final dynamic library = results[0];
      final List<dynamic> assets = library is Map && library['assets'] is List
          ? library['assets'] as List<dynamic>
          : <dynamic>[];
      if (mounted) {
        setState(() {
          libraryNext = library is Map && library['next_offset'] is int
              ? library['next_offset']
              : null;
          visibleLibraryCount = 24;
          libraryError = library is Map && library['_library_error'] == true
              ? 'Source library is unavailable. Your existing reels are still here.'
              : null;
          libraryAssets = assets
              .whereType<Map>()
              .map(
                (x) => <String, dynamic>{
                  ...Map<String, dynamic>.from(x),
                  'library': true,
                },
              )
              .toList();
          musicAssets = parseMusicAssets(results[1]);
          sourceTaste = <String, Map<String, dynamic>>{
            for (final dynamic row
                in ((results[2] as Map?)?['reviews'] as List? ?? <dynamic>[]))
              if (row is Map && row['asset_id'] != null)
                row['asset_id'].toString(): Map<String, dynamic>.from(row),
          };
        });
      }
    } catch (_) {
      if (mounted && generation == _catalogGeneration) {
        setState(() {
          error =
              'Couldn’t load your clips. Check your connection and try again.';
          loading = false;
        });
      }
    }
  }

  Future<void> moreLibrary() async {
    if (loadingMore) return;
    if (visibleLibraryCount < accountLibraryAssets.length) {
      setState(() => visibleLibraryCount += 24);
      return;
    }
    if (libraryNext == null) return;
    final owner = editorAccount;
    setState(() => loadingMore = true);
    try {
      final result = await request(
        'GET',
        '/reels/library?limit=60&account=${Uri.encodeComponent(owner)}&offset=$libraryNext',
      );
      if (!mounted || owner != editorAccount) return;
      setState(() {
        libraryNext = result['next_offset'] is int
            ? result['next_offset']
            : null;
        final merged = {for (final asset in libraryAssets) asset['id']: asset};
        for (final row in (result['assets'] as List? ?? [])) {
          if (row is Map) {
            merged[row['id']] = {
              ...Map<String, dynamic>.from(row),
              'library': true,
            };
          }
        }
        libraryAssets = merged.values.toList();
        visibleLibraryCount += 24;
        libraryError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => libraryError =
              'More clips could not load. Tap Show more to retry.',
        );
      }
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  Future<void> saveSourceTaste(
    Map<String, dynamic> item,
    String disposition,
  ) async {
    final String assetId = item['id']?.toString() ?? '';
    final String assetAccount = item['account']?.toString() ?? '';
    if (assetId.isEmpty ||
        assetAccount != editorAccount ||
        savingTaste.contains(assetId)) {
      return;
    }
    setState(() => savingTaste.add(assetId));
    try {
      final dynamic result = await request('POST', '/reels/source-taste', {
        'asset_id': assetId,
        'account': assetAccount,
        'disposition': disposition,
      });
      if (!mounted) return;
      final Map<String, dynamic>? review =
          result is Map && result['review'] is Map
          ? Map<String, dynamic>.from(result['review'] as Map)
          : null;
      setState(() {
        if (review != null) sourceTaste[assetId] = review;
      });
      // Only worth refreshing for someone who has actually opened the
      // shortlist; otherwise this is a request for a dialog nobody has looked
      // at, on every single Use/Maybe/Reject tap.
      if (sourceFinalists != null) await _loadFinalists();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Saved source review only. No reel was approved or changed.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save source review: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => savingTaste.remove(assetId));
    }
  }

  Future<void> _loadFinalists() async {
    try {
      final dynamic result = await request(
        'GET',
        '/reels/source-finalists?account=${Uri.encodeComponent(editorAccount)}',
      );
      if (mounted && result is Map) {
        setState(() => sourceFinalists = Map<String, dynamic>.from(result));
      }
    } catch (_) {
      // The source review itself remains visible if the summary refresh fails.
    }
  }

  /// Fetch-then-show, so the dialog never opens on a null summary and shows
  /// "0 Use / 0 Maybe / 0 Reject" for data the server has.
  Future<void> openFinalistSummary() async {
    if (sourceFinalists == null) await _loadFinalists();
    if (!mounted) return;
    showFinalistSummary();
  }

  void showFinalistSummary() {
    final Map<String, dynamic> summary = sourceFinalists ?? <String, dynamic>{};
    final Map<dynamic, dynamic> counts = summary['review_counts'] is Map
        ? summary['review_counts'] as Map
        : <dynamic, dynamic>{};
    final Map<dynamic, dynamic> readiness =
        summary['generation_readiness'] is Map
        ? summary['generation_readiness'] as Map
        : <dynamic, dynamic>{};
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Source shortlist'),
        content: Text(
          '${counts['use'] ?? 0} Use · ${counts['maybe'] ?? 0} Maybe · '
          '${counts['reject'] ?? 0} Reject\n\n'
          '${summary['count'] ?? 0} distinct, current finalists\n\n'
          '${readiness['next_action'] ?? 'Mark source clips Use, then generate review-only drafts.'}',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get accountLibraryAssets =>
      libraryAssets.where((item) => item['account'] == editorAccount).toList();
  List<Map<String, dynamic>> get sources => <String, Map<String, dynamic>>{
    for (final Map<String, dynamic> item in <Map<String, dynamic>>[
      ...reels,
      ...libraryAssets,
    ])
      item['id'].toString(): item,
  }.values.where((item) => item['account'] == editorAccount).toList();
  Map<String, dynamic> get selectedSource => sources.firstWhere(
    (Map<String, dynamic> item) => item['id'].toString() == sourceId,
    orElse: () => <String, dynamic>{},
  );
  double get sourceDuration =>
      (double.tryParse('${selectedSource['duration_seconds'] ?? 90}') ?? 90)
          .clamp(.5, 86400)
          .toDouble();
  double get musicCueMax {
    final song = musicAssets.firstWhere(
      (item) => item['id'] == musicAssetId,
      orElse: () => <String, dynamic>{},
    );
    final duration =
        double.tryParse('${song['duration_seconds'] ?? 180}') ?? 180;
    return math.max(0, duration - (outPoint - inPoint));
  }

  double get effectiveCue => math.min(cue, musicCueMax);
  void selectSource(String? id) {
    if (id == null) return;
    setState(() {
      sourceId = id;
      inPoint = 0;
      outPoint = math.min(sourceDuration, 90);
      showLibrary = false;
    });
  }

  TrialReelEditDraft draftFor(String id) => TrialReelEditDraft(
    sourceReelId: id,
    inPoint: inPoint,
    outPoint: outPoint,
    caption: caption.text.trim(),
    captionStyle: caption.text.trim().isEmpty ? 'center_white' : style,
    captionColor: captionColor,
    captionX: captionX,
    captionY: captionY,
    captionSize: captionSize,
    musicAssetId: musicAssetId,
    musicCueSeconds: effectiveCue,
  );
  Future<dynamic> requestRender(String id) async {
    final body = draftFor(id).toJson();
    final signature = jsonEncode(body);
    final key = renderKeys.putIfAbsent(
      signature,
      () => 'editor-${DateTime.now().microsecondsSinceEpoch}',
    );
    await persistJobs();
    final dynamic result =
        await request('POST', '/reels/render', <String, Object?>{
          ...body,
          'account': editorAccount,
          'source_sha256': sources.firstWhere(
            (source) => source['id'] == id,
            orElse: () => <String, dynamic>{},
          )['sha256'],
          'idempotency_key': key,
        });
    renderJobs.submitted(
      result,
      sourceId: id,
      account: editorAccount,
      signature: signature,
      title: sources
          .firstWhere(
            (source) => source['id'] == id,
            orElse: () => <String, dynamic>{},
          )['title']
          ?.toString(),
    );
    await persistJobs();
    return result;
  }

  Future<void> queueEdit() async {
    if (sourceId == null || sending) return;
    final body = <String, Object?>{
      ...draftFor(sourceId!).toJson(),
      'account': editorAccount,
      'reel_sha256': selectedSource['sha256'],
      'cadence': cadence,
      'brief': revisionBrief.text.trim(),
      'shots': sequenceShots
          .map(
            (shot) => <String, Object?>{
              for (final key in [
                'source_reel_id',
                'trim_in_seconds',
                'trim_out_seconds',
              ])
                key: shot[key],
            },
          )
          .toList(),
    };
    if (jsonEncode(body).length > 3200) {
      setState(
        () => error =
            'This recipe is too long. Shorten the revision brief before saving.',
      );
      return;
    }
    final signature = 'queue:${jsonEncode(body)}';
    final id = renderKeys.putIfAbsent(
      signature,
      () => 'native-${DateTime.now().microsecondsSinceEpoch}',
    );
    setState(() {
      sending = true;
      error = null;
    });
    try {
      await persistJobs();
      final result = await request('POST', '/trial-message', {
        'id': id,
        'reel_id': sourceId,
        'reel_sha256': selectedSource['sha256'],
        'account': editorAccount,
        'text':
            'Review-only edit request for $sourceId. Preserve original, save to revision bucket, do not execute automatically. Recipe: ${jsonEncode(body)}',
      });
      if (result is! Map || result['intake_verified'] != true) {
        throw Exception(
          'Receipt not confirmed. Retry preserves this request ID.',
        );
      }
      if (mounted) {
        setState(() => status = 'Revision queued · waiting for edit batch');
        widget.onReviewReady?.call(sourceId!);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> createExport() async {
    if (!canCreateReviewExports ||
        cadence != 'Preserve existing pacing' ||
        revisionBrief.text.trim().isNotEmpty) {
      await queueEdit();
      return;
    }
    if (sourceId == null) {
      setState(() => error = 'Choose an existing reel first.');
      return;
    }
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Create review export?'),
        content: const Text(
          'This renders a new version for review only. It will not schedule or publish.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      sending = true;
      status = 'Submitting…';
      error = null;
      reviewId = null;
      jobId = null;
    });
    try {
      final dynamic result = await requestRender(sourceId!);
      if (!mounted) return;
      jobId = result['job_id']?.toString();
      setState(() {
        status = result['status']?.toString() ?? 'queued';
        if (status == 'ready_for_review') {
          reviewId = result['asset']?['id']?.toString();
          sending = false;
        }
        if (status == 'failed') {
          sending = false;
          renderKeys.remove(jsonEncode(draftFor(sourceId!).toJson()));
          error = 'This render failed. Try again to create a new attempt.';
        }
        if (jobId == null) sending = false;
      });
      if (jobId != null) poll();
    } catch (e) {
      if (mounted) {
        setState(() {
          sending = false;
          status = 'failed';
          error = e.toString();
        });
      }
    }
  }

  Future<void> _pickBulkSources() async {
    final Set<String> selected = Set<String>.from(bulkSourceIds);
    final List<String> groups =
        accountLibraryAssets
            .map(
              (Map<String, dynamic> item) =>
                  (item['source_group'] ?? 'Library').toString(),
            )
            .toSet()
            .toList()
          ..sort();
    String? category;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: SandLayout.sheet),
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheet) {
          final List<Map<String, dynamic>> visible = accountLibraryAssets
              .where(
                (Map<String, dynamic> item) =>
                    category == null ||
                    (item['source_group'] ?? 'Library').toString() == category,
              )
              .toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .75,
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                'Select clips',
                                style: TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${selected.length} of 12 selected',
                                style: const TextStyle(
                                  color: SandDark.onSurfaceLow,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: DropdownButtonFormField<String>(
                      initialValue: category,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: <DropdownMenuItem<String>>[
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('All categories'),
                        ),
                        ...groups.map(
                          (String group) => DropdownMenuItem<String>(
                            value: group,
                            child: Text(group, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (String? value) =>
                          setSheet(() => category = value),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: <Widget>[
                        TextButton(
                          onPressed: selected.length >= 12
                              ? null
                              : () => setSheet(() {
                                  for (final Map<String, dynamic> item
                                      in visible) {
                                    if (selected.length >= 12) break;
                                    selected.add(item['id'].toString());
                                  }
                                }),
                          child: const Text('Select up to 12'),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: selected.isEmpty
                              ? null
                              : () => setSheet(selected.clear),
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (_, int index) {
                        final Map<String, dynamic> item = visible[index];
                        final String id = item['id'].toString();
                        return CheckboxListTile(
                          value: selected.contains(id),
                          title: Text(
                            (item['title'] ?? id).toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${item['source_group'] ?? 'Library'} · ${item['duration_seconds'] ?? '?'}s',
                          ),
                          onChanged:
                              !selected.contains(id) && selected.length >= 12
                              ? null
                              : (bool? value) => setSheet(() {
                                  if (value == true) {
                                    selected.add(id);
                                  } else {
                                    selected.remove(id);
                                  }
                                }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted) {
      setState(() {
        bulkSourceIds
          ..clear()
          ..addAll(selected);
      });
    }
  }

  Future<void> _createBatchExports() async {
    if (!canCreateReviewExports ||
        cadence != 'Preserve existing pacing' ||
        revisionBrief.text.trim().isNotEmpty) {
      await queueEdit();
      return;
    }
    if (bulkSourceIds.isEmpty) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text('Create ${bulkSourceIds.length} review exports?'),
        content: const Text(
          'The same trim, caption, color, position, and music recipe will be applied. Each export stays review-only and is never scheduled or posted.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Create batch'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      sending = true;
      status = 'Queueing ${bulkSourceIds.length} review exports…';
      error = null;
    });
    try {
      int queued = 0;
      final selected = bulkSourceIds.toList();
      for (final String id in selected) {
        await request('POST', '/reels/render', <String, Object?>{
          ...draftFor(id).toJson(),
          'validate_only': true,
        });
      }
      for (final String id in selected) {
        await requestRender(id);
        queued++;
        bulkSourceIds.remove(id);
      }
      if (mounted) {
        setState(() {
          sending = pendingRenderJobs.isNotEmpty;
          status = '$queued review-only exports queued';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          sending = false;
          error =
              'Batch stopped: $e. Only the remaining selections will be retried.';
        });
      }
    } finally {
      if (mounted && pendingRenderJobs.isNotEmpty) poll();
    }
  }

  void addSequenceShot() {
    if (sourceId == null || sequenceShots.length >= 12) return;
    final item = sources.firstWhere((item) => item['id'] == sourceId);
    setState(
      () => sequenceShots.add({
        'source_reel_id': sourceId,
        'trim_in_seconds': inPoint,
        'trim_out_seconds': outPoint,
        'title': item['title'] ?? 'Source range',
        'item': item,
      }),
    );
    persistJobs();
  }

  Future<void> renderSequence() async {
    if (!canCreateReviewExports ||
        cadence != 'Preserve existing pacing' ||
        revisionBrief.text.trim().isNotEmpty) {
      await queueEdit();
      return;
    }
    if (sending || !validSequence) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Render combined preview?'),
        content: Text(
          '${sequenceShots.length} ranges, ${sequenceDuration.toStringAsFixed(1)} seconds. This creates one new review export. Nothing posts automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Render preview'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final payload = draftFor(sourceId ?? '').toJson()
        ..remove('source_reel_id')
        ..remove('trim_in_seconds')
        ..remove('trim_out_seconds');
      payload.addAll({
        'account': editorAccount,
        'title': sequenceTitle.text.trim().isEmpty
            ? 'Studio sequence'
            : sequenceTitle.text.trim(),
        'post_caption': '',
        'music_cue_seconds': cue,
        'shots': sequenceShots
            .map(
              (shot) => {
                for (final key in [
                  'source_reel_id',
                  'trim_in_seconds',
                  'trim_out_seconds',
                ])
                  key: shot[key],
              },
            )
            .toList(),
      });
      await request('POST', '/reels/render', {
        ...payload,
        'validate_only': true,
      });
      final signature = jsonEncode(payload);
      final key = renderKeys.putIfAbsent(
        signature,
        () => 'sequence-${DateTime.now().microsecondsSinceEpoch}',
      );
      await persistJobs();
      final result = await request('POST', '/reels/render', {
        ...payload,
        'idempotency_key': key,
      });
      renderJobs.submitted(
        result,
        sourceId: 'sequence',
        account: editorAccount,
        signature: signature,
        title: payload['title'] as String,
      );
      await persistJobs();
      if (mounted) await poll();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          sending = false;
        });
      }
    }
  }

  Widget sequenceEditor() => _section(
    'Combine clips into one reel',
    CupertinoIcons.film,
    [
      const Text(
        'Add each source range, set the order, then render a combined preview to check transitions and sound.',
      ),
      TextField(
        controller: sequenceTitle,
        maxLength: 120,
        decoration: const InputDecoration(labelText: 'Sequence title'),
      ),
      OutlinedButton(
        onPressed: sending || sourceId == null || sequenceShots.length >= 12
            ? null
            : addSequenceShot,
        child: const Text('Add current range'),
      ),
      for (final entry in sequenceShots.asMap().entries)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${entry.key + 1}. ${entry.value['title']}'),
                Row(
                  children: [
                    for (final key in ['trim_in_seconds', 'trim_out_seconds'])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: TextFormField(
                            key: ValueKey(
                              '${identityHashCode(entry.value)}-$key',
                            ),
                            initialValue: '${entry.value[key]}',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            enabled: !sending,
                            decoration: InputDecoration(
                              labelText: key == 'trim_in_seconds'
                                  ? 'In seconds'
                                  : 'Out seconds',
                            ),
                            onChanged: (value) {
                              setState(
                                () => entry.value[key] =
                                    double.tryParse(value) ?? double.nan,
                              );
                              persistJobs();
                            },
                          ),
                        ),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    IconButton(
                      tooltip: 'Move earlier',
                      onPressed: sending || entry.key == 0
                          ? null
                          : () {
                              setState(() {
                                final row = sequenceShots.removeAt(entry.key);
                                sequenceShots.insert(entry.key - 1, row);
                              });
                              persistJobs();
                            },
                      icon: const Icon(CupertinoIcons.arrow_up),
                    ),
                    IconButton(
                      tooltip: 'Move later',
                      onPressed:
                          sending || entry.key == sequenceShots.length - 1
                          ? null
                          : () {
                              setState(() {
                                final row = sequenceShots.removeAt(entry.key);
                                sequenceShots.insert(entry.key + 1, row);
                              });
                              persistJobs();
                            },
                      icon: const Icon(CupertinoIcons.arrow_down),
                    ),
                    TextButton(
                      onPressed: sending
                          ? null
                          : () {
                              final shot = entry.value;
                              final item = Map<String, dynamic>.from(
                                shot['item'],
                              );
                              if (!sources.any(
                                (item) => item['id'] == shot['source_reel_id'],
                              )) {
                                libraryAssets.add(item);
                              }
                              selectSource(shot['source_reel_id']);
                              setState(() {
                                inPoint = (shot['trim_in_seconds'] as num)
                                    .toDouble();
                                outPoint = (shot['trim_out_seconds'] as num)
                                    .toDouble();
                              });
                            },
                      child: const Text('Preview range'),
                    ),
                    TextButton(
                      onPressed: sending
                          ? null
                          : () {
                              setState(() => sequenceShots.removeAt(entry.key));
                              persistJobs();
                            },
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      Text(
        '${sequenceShots.length} ranges · ${sequenceDuration.toStringAsFixed(1)}s / 90s',
      ),
      if (sequenceShots.isNotEmpty && !validSequence)
        const Text(
          'Check the ranges: each needs at least 0.5s, at most 90s in total.',
        ),
      FilledButton(
        onPressed: sending || !validSequence ? null : renderSequence,
        child: const Text('Render combined preview'),
      ),
    ],
  );

  Future<void> poll() async {
    if (!canCreateReviewExports || pollingJobs) return;
    pollingJobs = true;
    try {
      while (mounted && pendingRenderJobs.isNotEmpty) {
        bool interrupted = false;
        for (final job in pendingRenderJobs.toList()) {
          try {
            final dynamic result = await request(
              'GET',
              '/reels/render/${Uri.encodeComponent(job['id'])}',
            );
            if (!mounted) return;
            renderJobs.update(job['id'], result);
            if (job['status'] == 'failed') renderKeys.remove(job['signature']);
          } catch (e) {
            job['status'] = 'interrupted';
            job['error'] =
                'Status unavailable. Check again before creating another version.';
            interrupted = true;
          }
        }
        await persistJobs();
        if (!mounted) return;
        setState(() {
          sending = pendingRenderJobs.isNotEmpty;
          status = sending
              ? 'Checking ${pendingRenderJobs.length} review exports'
              : 'Batch finished; review each result below';
        });
        if (interrupted || pendingRenderJobs.isEmpty) break;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    } finally {
      if (mounted) {
        setState(() => pollingJobs = false);
      } else {
        pollingJobs = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit reel')),
    body: SafeArea(
      child: loading
          ? const Center(child: CupertinoActivityIndicator(radius: 14))
          // The clip you are cutting, and the controls that cut it. On a phone
          // that is one scrolling column, in the order it shipped: choose an
          // account, choose a clip, browse the library, see the preview, then
          // trim, caption, score and export. On an iPad it is the standard
          // editing split — the library and the live preview on the left, the
          // controls on the right — so changing a caption no longer means
          // scrolling the frame it is drawn on off the screen.
          : ConPanes(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              keyboardDismiss: true,
              primary: <Widget>[
                const Text(
                  'Make it yours.',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.8,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Preview your cut, captions, and sound before export.',
                  style: TextStyle(color: SandDark.onSurfaceLow, height: 1.4),
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: editorAccount,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Account'),
                  items:
                      (widget.allowedAccounts ??
                              const <String>[
                                '@zionboggan',
                                '@barcrawls.arizona',
                                '@barcrawling',
                                '@gabejlove',
                              ])
                          .map(
                            (String account) => DropdownMenuItem<String>(
                              value: account,
                              child: Text(account),
                            ),
                          )
                          .toList(),
                  onChanged: sending
                      ? null
                      : (value) {
                          setState(() {
                            editorAccount = value!;
                            sourceId = null;
                            bulkSourceIds.clear();
                            caption.clear();
                            musicAssetId = null;
                            cue = 0;
                            showLibrary = true;
                            _applyCaptionDefaultsForAccount(editorAccount);
                          });
                          loadCatalog();
                        },
                ),
                const SizedBox(height: 16),
                if (error != null && sources.isEmpty) ...<Widget>[
                  Text(error!, style: const TextStyle(color: SandDark.error)),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: loadCatalog,
                    child: const Text('Try again'),
                  ),
                ],
                if (libraryError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      libraryError!,
                      style: const TextStyle(color: SandDark.error),
                    ),
                  ),
                if (sources.isNotEmpty) ...<Widget>[
                  DropdownButtonFormField<String>(
                    key: ValueKey<String?>('source-$sourceId'),
                    initialValue: sourceId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Source clip',
                      hintText: 'Choose a clip',
                    ),
                    items: sources
                        .map(
                          (Map<String, dynamic> item) =>
                              DropdownMenuItem<String>(
                                value: item['id'].toString(),
                                child: Text(
                                  (item['title'] ?? item['id']).toString(),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                        )
                        .toList(),
                    onChanged: sending ? null : selectSource,
                  ),
                  const SizedBox(height: 12),
                ],
                if (accountLibraryAssets.isNotEmpty) ...<Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${accountLibraryAssets.length} library clips',
                          style: const TextStyle(color: SandDark.onSurfaceLow),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => showLibrary = !showLibrary),
                        child: Text(
                          showLibrary ? 'Hide library' : 'Browse library',
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: openFinalistSummary,
                      icon: const Icon(CupertinoIcons.checkmark_seal),
                      label: const Text('Review shortlist'),
                    ),
                  ),
                  if (showLibrary) ...<Widget>[
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: accountLibraryAssets.length.clamp(
                        0,
                        visibleLibraryCount,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: .72,
                          ),
                      itemBuilder: (BuildContext context, int index) {
                        final Map<String, dynamic> item =
                            accountLibraryAssets[index];
                        final bool selected = sourceId == item['id'];
                        final Map<String, dynamic>? taste =
                            sourceTaste[item['id']?.toString()];
                        final bool saving = savingTaste.contains(
                          item['id']?.toString(),
                        );
                        return Semantics(
                          button: true,
                          selected: selected,
                          label: (item['title'] ?? 'Source clip').toString(),
                          child: InkWell(
                            onTap: sending
                                ? null
                                : () => selectSource(item['id'].toString()),
                            borderRadius: BorderRadius.circular(SandRadius.r2),
                            child: Container(
                              decoration: BoxDecoration(
                                // Selection is IRON, never orange: orange is
                                // reserved for actions.
                                border: Border.all(
                                  color: selected
                                      ? SandDark.secondary
                                      : SandDark.outline,
                                  width: selected
                                      ? SandBorder.selected
                                      : SandBorder.hairline,
                                ),
                                borderRadius: BorderRadius.circular(
                                  SandRadius.r2,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  SandRadius.r2,
                                ),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: <Widget>[
                                    Image.network(
                                      '${widget.base}/reels/library/${Uri.encodeComponent(item['id'].toString())}/poster',
                                      fit: BoxFit.cover,
                                      cacheWidth: 320,
                                      headers: TrialCredentials.mediaHeaders(
                                        widget.base,
                                      ),
                                      errorBuilder: (_, __, ___) =>
                                          const SandMediaPlaceholder(
                                            compact: true,
                                          ),
                                    ),
                                    Align(
                                      alignment: Alignment.bottomLeft,
                                      child: Container(
                                        width: double.infinity,
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: <Color>[
                                              Colors.transparent,
                                              Colors.black87,
                                            ],
                                          ),
                                        ),
                                        padding: const EdgeInsets.fromLTRB(
                                          8,
                                          24,
                                          8,
                                          8,
                                        ),
                                        child: Text(
                                          (item['title'] ?? 'Clip').toString(),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (selected)
                                      const Positioned(
                                        right: 8,
                                        top: 8,
                                        child: Icon(
                                          CupertinoIcons.checkmark_circle_fill,
                                          color: SandDark.secondaryBright,
                                        ),
                                      ),
                                    // The selection signature: a 3px iron bar
                                    // along the bottom edge of the thumbnail.
                                    if (selected)
                                      const Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: 0,
                                        height: SandBorder.marker,
                                        child: ColoredBox(
                                          color: SandDark.secondary,
                                        ),
                                      ),
                                    Positioned(
                                      left: 2,
                                      top: 2,
                                      child: PopupMenuButton<String>(
                                        tooltip: 'Save source review',
                                        enabled: !saving && !sending,
                                        icon: Icon(
                                          taste?['disposition'] == 'use'
                                              ? CupertinoIcons.heart_fill
                                              : taste?['disposition'] ==
                                                    'reject'
                                              ? CupertinoIcons.xmark_circle_fill
                                              : CupertinoIcons
                                                    .ellipsis_circle_fill,
                                          color: taste?['disposition'] == 'use'
                                              ? SandDark.primary
                                              : taste?['disposition'] ==
                                                    'reject'
                                              ? SandDark.error
                                              : SandDark.onSurfaceLow,
                                        ),
                                        onSelected: (String value) =>
                                            saveSourceTaste(item, value),
                                        itemBuilder: (BuildContext context) =>
                                            const <PopupMenuEntry<String>>[
                                              PopupMenuItem(
                                                value: 'use',
                                                child: Text('Use / favorite'),
                                              ),
                                              PopupMenuItem(
                                                value: 'maybe',
                                                child: Text('Maybe'),
                                              ),
                                              PopupMenuItem(
                                                value: 'reject',
                                                child: Text('Reject'),
                                              ),
                                            ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    if (visibleLibraryCount < accountLibraryAssets.length ||
                        libraryNext != null)
                      TextButton(
                        onPressed: loadingMore ? null : moreLibrary,
                        child: Text(
                          loadingMore
                              ? 'Loading clips…'
                              : 'Show more source clips',
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                ],
                if (sourceId != null) ...<Widget>[
                  RepaintBoundary(
                    child: SourcePreview(
                      key: ValueKey<String>(
                        'preview-$sourceId-$_previewAttempt',
                      ),
                      base: widget.base,
                      account: editorAccount,
                      item: selectedSource,
                      onRetry: () => setState(() => _previewAttempt++),
                      caption: caption.text,
                      style: style,
                      captionColor: captionColor,
                      captionX: captionX,
                      captionY: captionY,
                      captionSize: captionSize,
                      musicAssetId: musicAssetId,
                      musicCueSeconds: effectiveCue,
                      trimInSeconds: inPoint,
                      trimOutSeconds: outPoint,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
              secondary: <Widget>[
                _section('Trim', CupertinoIcons.scissors, <Widget>[
                  slider(
                    'Start',
                    '${inPoint.toStringAsFixed(1)}s',
                    inPoint,
                    0,
                    sourceDuration - .5,
                    (double v) => setState(() {
                      inPoint = v;
                      outPoint = math.min(
                        sourceDuration,
                        math.max(v + .5, math.min(outPoint, v + 90)),
                      );
                    }),
                  ),
                  slider(
                    'End',
                    '${outPoint.toStringAsFixed(1)}s',
                    outPoint,
                    inPoint + .5,
                    math.min(sourceDuration, inPoint + 90),
                    (double v) => setState(() => outPoint = v),
                  ),
                ]),
                _section('Captions', CupertinoIcons.textformat, <Widget>[
                  TextField(
                    controller: caption,
                    enabled: !sending,
                    maxLength: 180,
                    maxLines: 3,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'On-screen text',
                      hintText: 'Write your hook…',
                    ),
                  ),
                  const Text(
                    'Existing on-screen text stays. Start with a clean source to replace it.',
                    style: TextStyle(
                      color: SandDark.onSurfaceLow,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  slider(
                    'Text size',
                    '${captionSize.round()} px',
                    captionSize,
                    32,
                    120,
                    (value) => setState(() => captionSize = value),
                  ),
                  Text(
                    editorAccount == '@zionboggan'
                        ? 'Centered condensed text'
                        : 'Roboto Condensed · no outline',
                    style: const TextStyle(
                      color: SandDark.onSurfaceLow,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>('style-$style'),
                    initialValue: style,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Style'),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(
                        value: 'center_white',
                        child: Text('Classic'),
                      ),
                      DropdownMenuItem(
                        value: 'center_yellow',
                        child: Text('Highlight'),
                      ),
                      DropdownMenuItem(
                        value: 'top_white',
                        child: Text('Headline'),
                      ),
                    ],
                    onChanged: sending
                        ? null
                        : (String? v) => setState(() {
                            style = v ?? style;
                            captionY = style == 'top_white' ? 18 : 50;
                            captionColor = style == 'center_yellow'
                                ? '#F6D77A'
                                : '#FFFFFF';
                          }),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Color',
                    style: TextStyle(color: SandDark.onSurfaceLow),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children:
                        <String>[
                              '#FFFFFF',
                              '#FFE19A',
                              '#F6D77A',
                              '#B1EBBD',
                              '#9AD7FF',
                              '#FF9AB5',
                              '#D6A4FF',
                              '#FF8B6B',
                            ]
                            .map(
                              (String hex) => Semantics(
                                label: 'Caption color $hex',
                                selected: captionColor == hex,
                                child: IconButton(
                                  tooltip: hex,
                                  onPressed: sending
                                      ? null
                                      : () =>
                                            setState(() => captionColor = hex),
                                  icon: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: Color(
                                        int.parse(
                                          'FF${hex.substring(1)}',
                                          radix: 16,
                                        ),
                                      ),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: captionColor == hex
                                            ? studioAccent
                                            : Colors.white24,
                                        width: captionColor == hex ? 3 : 1,
                                      ),
                                    ),
                                    child: captionColor == hex
                                        ? const Icon(
                                            CupertinoIcons.checkmark,
                                            size: 18,
                                            color: Colors.black,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                  const SizedBox(height: 12),
                  slider(
                    'Left to right',
                    '${captionX.round()}%',
                    captionX,
                    0,
                    100,
                    (double v) => setState(() => captionX = v),
                  ),
                  slider(
                    'Top to bottom',
                    '${captionY.round()}%',
                    captionY,
                    0,
                    100,
                    (double v) => setState(() => captionY = v),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: sending
                          ? null
                          : () => setState(() {
                              captionX = 50;
                              captionY = 50;
                            }),
                      child: const Text('Center caption'),
                    ),
                  ),
                ]),
                _section('Sound', CupertinoIcons.music_note_2, <Widget>[
                  DropdownButtonFormField<String?>(
                    key: ValueKey<String?>('music-$musicAssetId'),
                    initialValue: musicAssetId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Song'),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Original audio'),
                      ),
                      ...musicAssets.map(
                        (Map<String, dynamic> item) =>
                            DropdownMenuItem<String?>(
                              value: item['id'].toString(),
                              child: Text(
                                (item['label'] ?? item['title'] ?? item['id'])
                                    .toString(),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                      ),
                    ],
                    onChanged: sending
                        ? null
                        : (String? v) => setState(() {
                            musicAssetId = v;
                            cue = 0;
                          }),
                  ),
                  if (musicAssetId != null) ...<Widget>[
                    const SizedBox(height: 18),
                    slider(
                      'Song starts at',
                      '${effectiveCue.toStringAsFixed(1)}s',
                      effectiveCue,
                      0,
                      musicCueMax,
                      (double v) => setState(() => cue = v),
                    ),
                  ],
                  if (musicAssets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Your approved songs will appear here.',
                        style: TextStyle(color: SandDark.onSurfaceLow),
                      ),
                    ),
                ]),
                _section('Pacing & revision brief', CupertinoIcons.pencil, <
                  Widget
                >[
                  DropdownButtonFormField<String>(
                    initialValue: cadence,
                    // MEASURED: "Slower / more breathing room" needs 452 pt
                    // and overflowed a 287 pt box by 165. Every other
                    // dropdown on this screen already declares this; this one
                    // and the account picker did not, and a two-pane iPad
                    // layout is narrower than a whole page, so it showed.
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Cadence'),
                    items:
                        [
                              'Preserve existing pacing',
                              'Faster cuts',
                              'Slower / more breathing room',
                              'Match music beats',
                              'One word at a time',
                            ]
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                    onChanged: (value) =>
                        setState(() => cadence = value ?? cadence),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: revisionBrief,
                    maxLines: 3,
                    maxLength: 1800,
                    decoration: const InputDecoration(
                      labelText: 'What should change?',
                      hintText:
                          'Replace the intro, move existing captions, remix the hook…',
                    ),
                  ),
                  const Text(
                    'Existing captions and cuts in a finished video are flattened. Use this brief to rebuild them from original sources. A preview overlay does not remove existing captions.',
                    style: TextStyle(
                      color: SandDark.onSurfaceLow,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: sending || sourceId == null ? null : queueEdit,
                    icon: const Icon(CupertinoIcons.archivebox),
                    label: const Text('Save recipe to revision queue'),
                  ),
                ]),
                sequenceEditor(),
                _section('Batch edit', CupertinoIcons.square_stack, <Widget>[
                  const Text(
                    'Apply these settings to up to 12 clips. Each gets a separate review export.',
                    style: TextStyle(color: SandDark.onSurfaceLow, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: sending || accountLibraryAssets.isEmpty
                        ? null
                        : _pickBulkSources,
                    icon: const Icon(CupertinoIcons.checkmark_circle, size: 18),
                    label: Text(
                      bulkSourceIds.isEmpty
                          ? 'Select clips'
                          : '${bulkSourceIds.length} clips selected',
                    ),
                  ),
                  if (bulkSourceIds.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: FilledButton(
                        onPressed: sending ? null : _createBatchExports,
                        child: const Text('Apply to selected clips'),
                      ),
                    ),
                ]),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: sending || sourceId == null
                        ? null
                        : createExport,
                    icon: sending
                        ? const CupertinoActivityIndicator()
                        : const Icon(CupertinoIcons.square_arrow_up, size: 19),
                    label: Text(
                      sending
                          ? 'Preparing…'
                          : (!canCreateReviewExports ||
                                cadence != 'Preserve existing pacing' ||
                                revisionBrief.text.trim().isNotEmpty)
                          ? 'Save to revision queue'
                          : 'Create review export',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Review and approve before posting.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SandDark.onSurfaceLow, fontSize: 13),
                ),
                for (final job in visibleRenderJobs.where(
                  (job) => job['account'] == editorAccount,
                ))
                  Card(
                    child: ListTile(
                      title: Text('${job['title'] ?? 'Review export'}'),
                      subtitle: Text(
                        job['status'] == 'ready_for_review'
                            ? 'Ready for review'
                            : job['status'] == 'failed' ||
                                  job['status'] == 'interrupted'
                            ? '${job['error'] ?? 'Render failed'}'
                            : 'Preparing review export',
                      ),
                      trailing: job['review_id'] != null
                          ? TextButton(
                              onPressed: () {
                                widget.onReviewReady?.call(job['review_id']);
                                widget.openReview?.call();
                              },
                              child: const Text('Review'),
                            )
                          : null,
                    ),
                  ),
                if (pendingRenderJobs.isNotEmpty)
                  OutlinedButton(
                    onPressed: pollingJobs ? null : poll,
                    child: const Text('Check render status'),
                  ),
                if (status != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Text(
                      status == 'ready_for_review'
                          ? 'Ready to review'
                          : status!.replaceAll('_', ' '),
                      style: const TextStyle(color: studioAccent),
                    ),
                  ),
                if (reviewId != null && widget.openReview != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: OutlinedButton(
                      onPressed: widget.openReview,
                      child: const Text('Open Review'),
                    ),
                  ),
                if (error != null && sources.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: const TextStyle(color: SandDark.error),
                    ),
                  ),
              ],
            ),
    ),
  );

  Widget _section(String title, IconData icon, List<Widget> children) => Card(
    child: ExpansionTile(
      key: ValueKey('editor-section-$title'),
      maintainState: true,
      initiallyExpanded:
          title == 'Trim' ||
          (title == 'Combine clips into one reel' && sequenceShots.isNotEmpty),
      leading: Icon(icon, color: studioAccent, size: 21),
      title: Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ],
    ),
  );

  Widget slider(
    String label,
    String display,
    double value,
    double min,
    double max,
    ValueChanged<double> change,
  ) {
    final double upper = max < min ? min : max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: SandDark.onSurfaceLow,
                  fontSize: 14,
                ),
              ),
            ),
            Text(display, style: const TextStyle(fontSize: 14)),
          ],
        ),
        Slider(
          value: value.clamp(min, upper).toDouble(),
          min: min,
          max: upper,
          onChanged: sending || upper == min ? null : change,
        ),
      ],
    );
  }
}

class SourcePreview extends StatefulWidget {
  const SourcePreview({
    super.key,
    required this.base,
    required this.item,
    this.account,
    required this.caption,
    required this.style,
    required this.captionColor,
    required this.captionX,
    required this.captionY,
    this.captionSize = 68,
    this.musicAssetId,
    required this.musicCueSeconds,
    required this.trimInSeconds,
    required this.trimOutSeconds,
    this.onRetry,
  });
  final String base;
  final String? account;
  final Map<String, dynamic> item;
  final String caption, style, captionColor;
  final String? musicAssetId;
  final VoidCallback? onRetry;
  final double musicCueSeconds,
      trimInSeconds,
      trimOutSeconds,
      captionX,
      captionY,
      captionSize;
  @override
  State<SourcePreview> createState() => _SourcePreviewState();
}

class _SourcePreviewState extends State<SourcePreview>
    with WidgetsBindingObserver {
  late final VideoPlayerController controller;
  VideoPlayerController? music;
  late final Future<void> ready;
  String? musicError;
  bool musicLoading = false;
  bool _syncing = false;
  int _musicGeneration = 0;
  Timer? _editDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final bool library = widget.item['library'] == true;
    // The library preview proxy is a fixed 0.25s-in, 8s-long teaser
    // (server: media_library.preview(), media_library.py:342-351) reused
    // indefinitely from cache. Well over half the real library is longer
    // than that (measured 2026-09-15: 2160/4070 indexed assets exceed 8s),
    // so trimming past 8 seconds was blind: the handle could be dragged
    // anywhere in the real duration, but nothing beyond 8s ever played.
    // Render already re-seeks the *original* file for export
    // (reel_gate.start_native_render -> media_library.source(), never the
    // proxy), so this was a preview-only defect, not an export-correctness
    // one -- but it made the editor lie about what you were about to cut.
    // /original streams the untouched NAS file with real HTTP range
    // support (chat.py send_media(), RFC 7233). Measured server-local
    // 2026-09-15 against a 34s/13MB real clip: /original cold first 64KiB
    // in 53ms, full file in 108ms (120 MB/s); by contrast an *uncached*
    // /preview costs a fresh ffmpeg encode, measured at 1337ms before its
    // first byte. /original is not slower to open and it is honest about
    // the whole clip.
    final String path = library
        ? '/reels/library/${Uri.encodeComponent(widget.item['id'].toString())}/original'
        : '/reels/file/${Uri.encodeComponent(widget.item['id'].toString())}';
    controller = VideoPlayerController.networkUrl(
      Uri.parse('${widget.base}$path'),
      httpHeaders: TrialCredentials.mediaHeaders(widget.base),
    );
    ready = _initialize();
  }

  Duration get _start =>
      Duration(milliseconds: (widget.trimInSeconds * 1000).round());
  Duration get _end {
    final Duration requested = Duration(
      milliseconds: (widget.trimOutSeconds * 1000).round(),
    );
    return requested > controller.value.duration
        ? controller.value.duration
        : requested;
  }

  Duration get _musicPosition => Duration(
    milliseconds:
        ((widget.musicCueSeconds +
                    (controller.value.position.inMilliseconds / 1000 -
                        widget.trimInSeconds)) *
                1000)
            .round(),
  );

  Future<void> _initialize() async {
    await controller.initialize().timeout(const Duration(seconds: 20));
    if (!mounted) return;
    await controller.seekTo(_start);
    if (!mounted) return;
    controller.addListener(_watchSource);
    await _configureMusic();
  }

  @override
  void didUpdateWidget(covariant SourcePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Caption, color and placement updates are paint-only: never recreate the
    // media controllers while typing or moving a slider.
    if (!controller.value.isInitialized) return;
    if (oldWidget.musicAssetId != widget.musicAssetId ||
        oldWidget.account != widget.account) {
      _configureMusic();
    } else if (oldWidget.musicCueSeconds != widget.musicCueSeconds ||
        oldWidget.trimInSeconds != widget.trimInSeconds ||
        oldWidget.trimOutSeconds != widget.trimOutSeconds) {
      _editDebounce?.cancel();
      _editDebounce = Timer(const Duration(milliseconds: 120), _syncEdit);
    }
  }

  Future<void> _configureMusic() async {
    final int generation = ++_musicGeneration;
    final VideoPlayerController? previous = music;
    music = null;
    if (mounted) {
      setState(() {
        musicLoading = widget.musicAssetId != null;
        musicError = null;
      });
    }
    await controller.pause();
    await previous?.dispose();
    if (!mounted || generation != _musicGeneration) return;
    await controller.setVolume(widget.musicAssetId == null ? 1 : 0);
    if (widget.musicAssetId == null) return;
    final VideoPlayerController candidate = VideoPlayerController.networkUrl(
      Uri.parse(
        '${widget.base}/reels/music/${Uri.encodeComponent(widget.musicAssetId!)}'
        '?account=${Uri.encodeComponent(widget.account ?? widget.item['account']?.toString() ?? '')}',
      ),
      httpHeaders: TrialCredentials.mediaHeaders(widget.base),
    );
    try {
      await candidate.initialize().timeout(const Duration(seconds: 15));
      if (!mounted || generation != _musicGeneration) {
        await candidate.dispose();
        return;
      }
      await candidate.setVolume(1);
      await candidate.seekTo(_musicPosition);
      if (!mounted || generation != _musicGeneration) {
        await candidate.dispose();
        return;
      }
      music = candidate;
      setState(() => musicLoading = false);
    } catch (_) {
      await candidate.dispose();
      if (mounted && generation == _musicGeneration) {
        setState(() {
          musicLoading = false;
          musicError =
              'Couldn’t preview this song. Try it again before exporting.';
        });
      }
    }
  }

  Future<void> _syncEdit() async {
    if (!mounted || !controller.value.isInitialized) return;
    await controller.pause();
    await music?.pause();
    if (!mounted) return;
    final Duration position = controller.value.position;
    if (position < _start || position >= _end) await controller.seekTo(_start);
    if (mounted && music?.value.isInitialized == true) {
      await music!.seekTo(_musicPosition);
    }
  }

  void _watchSource() {
    if (!mounted || _syncing) return;
    if (controller.value.isPlaying && controller.value.position >= _end) {
      _pause();
    }
    if (mounted) setState(() {});
  }

  Future<void> _pause() async {
    _syncing = true;
    try {
      await controller.pause();
      await music?.pause();
    } finally {
      _syncing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _seek(double milliseconds) async {
    await _pause();
    if (!mounted) return;
    await controller.seekTo(Duration(milliseconds: milliseconds.round()));
    if (mounted && music?.value.isInitialized == true) {
      await music!.seekTo(_musicPosition);
    }
  }

  Future<void> _toggle() async {
    if (controller.value.isPlaying) {
      await _pause();
      return;
    }
    _editDebounce?.cancel();
    if (controller.value.position < _start ||
        controller.value.position >= _end) {
      await controller.seekTo(_start);
    }
    if (!mounted) return;
    final VideoPlayerController? song = music;
    if (song != null && song.value.isInitialized) {
      await song.seekTo(_musicPosition);
      if (!mounted || song != music) return;
      await song.play();
    }
    if (mounted) await controller.play();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _musicGeneration++;
    _editDebounce?.cancel();
    controller.removeListener(_watchSource);
    controller.dispose();
    music?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: ready,
    builder: (_, AsyncSnapshot<void> snap) {
      if (snap.connectionState != ConnectionState.done) {
        return const SizedBox(
          height: 240,
          child: Center(child: CupertinoActivityIndicator(radius: 14)),
        );
      }
      if (snap.hasError) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: <Widget>[
                const Icon(
                  CupertinoIcons.exclamationmark_circle,
                  color: SandDark.onSurfaceLow,
                  size: 32,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Couldn’t load this preview.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SandDark.error),
                ),
                if (widget.onRetry != null)
                  TextButton(
                    onPressed: widget.onRetry,
                    child: const Text('Try again'),
                  ),
              ],
            ),
          ),
        );
      }
      final double endMs = _end.inMilliseconds.toDouble();
      final double startMs = _start.inMilliseconds.toDouble().clamp(0, endMs);
      return Card(
        color: Colors.black,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 420,
              child: Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: LayoutBuilder(
                    builder: (context, frame) => Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        Positioned.fill(
                          child: ClipRect(
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: controller.value.size.width,
                                height: controller.value.size.height,
                                child: VideoPlayer(controller),
                              ),
                            ),
                          ),
                        ),
                        if (widget.caption.trim().isNotEmpty)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Align(
                                alignment: Alignment(
                                  widget.captionX / 50 - 1,
                                  widget.captionY / 50 - 1,
                                ),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: frame.maxWidth * 950 / 1080,
                                  ),
                                  child: Text(
                                    widget.caption.trim(),
                                    textAlign: TextAlign.center,
                                    textScaler: TextScaler.noScaling,
                                    style: TextStyle(
                                      fontSize:
                                          widget.captionSize *
                                          frame.maxWidth /
                                          1080,
                                      fontFamily:
                                          widget.item['account'] ==
                                              '@zionboggan'
                                          ? 'DejaVuSansCondensed'
                                          : 'RobotoCondensed',
                                      fontWeight: FontWeight.w400,
                                      color: Color(
                                        int.parse(
                                          'FF${widget.captionColor.substring(1)}',
                                          radix: 16,
                                        ),
                                      ),
                                      shadows:
                                          widget.item['account'] ==
                                                  '@barcrawls.arizona' ||
                                              widget.item['account'] ==
                                                  '@barcrawling' ||
                                              widget.item['account'] ==
                                                  '@gabejlove'
                                          ? null
                                          : const <Shadow>[
                                              Shadow(
                                                color: Colors.black,
                                                blurRadius: 1,
                                                offset: Offset(1, 1),
                                              ),
                                            ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: <Widget>[
                  Text(
                    _time(controller.value.position),
                    style: const TextStyle(
                      color: SandDark.onSurfaceLow,
                      fontSize: 12,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: controller.value.position.inMilliseconds
                          .toDouble()
                          .clamp(startMs, endMs),
                      min: startMs,
                      max: endMs,
                      onChanged: musicLoading || startMs == endMs
                          ? null
                          : _seek,
                      semanticFormatterCallback: (double value) =>
                          _time(Duration(milliseconds: value.round())),
                    ),
                  ),
                  Text(
                    _time(_end),
                    style: const TextStyle(
                      color: SandDark.onSurfaceLow,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.musicAssetId == null
                          ? 'Original audio · Live captions'
                          : 'Selected song · Live captions',
                      style: const TextStyle(
                        color: SandDark.onSurfaceLow,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: controller.value.isPlaying
                        ? 'Pause preview'
                        : 'Play preview',
                    onPressed: musicLoading ? null : _toggle,
                    icon: musicLoading || controller.value.isBuffering
                        ? const CupertinoActivityIndicator()
                        : Icon(
                            controller.value.isPlaying
                                ? CupertinoIcons.pause_fill
                                : CupertinoIcons.play_fill,
                          ),
                  ),
                ],
              ),
            ),
            if (musicError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Column(
                  children: <Widget>[
                    Text(
                      musicError!,
                      style: const TextStyle(
                        color: SandDark.error,
                        fontSize: 12,
                      ),
                    ),
                    TextButton(
                      onPressed: _configureMusic,
                      child: const Text('Retry song'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
  String _time(Duration value) =>
      '${value.inMinutes}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}

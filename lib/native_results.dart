import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_motion.dart';
import 'console_shell.dart' show conCardRows;
import 'app_experience.dart';
import 'trial_credentials.dart';

/// Provider observations, grouped by reel. Missing values stay missing.
class NativeResults extends StatefulWidget {
  const NativeResults({
    super.key,
    required this.base,
    required this.selectedAccounts,
    required this.catalog,
    required this.accountStatus,
    required this.load,
    required this.connect,
    required this.preview,
  });
  final String base;
  final Set<String> selectedAccounts;
  final List<Map<String, dynamic>> catalog, accountStatus;
  final Future<dynamic> Function() load;
  final void Function(String) connect;
  final void Function(Map<String, dynamic>) preview;
  @override
  State<NativeResults> createState() => _NativeResultsState();
}

class _NativeResultsState extends State<NativeResults> {
  late Future<dynamic> observations;
  bool _activity = false;
  @override
  void initState() {
    super.initState();
    observations = widget.load();
  }

  bool selected(dynamic account) =>
      widget.selectedAccounts.contains('all') ||
      widget.selectedAccounts.contains(account);
  void retry() => setState(() => observations = widget.load());

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      for (final account in widget.accountStatus.where(
        (item) => selected(item['account']),
      ))
        if ((account['insights'] is Map
                    ? account['insights']['status']
                    : null) !=
                'ready' &&
            (account['insights'] is! Map ||
                account['insights']['data_status'] != 'available'))
          Card(
            child: ListTile(
              leading: const Icon(
                CupertinoIcons.chart_bar,
                color: studioAccent,
              ),
              title: Text(
                '${account['account'] ?? 'Instagram'}',
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: const Text('Connect reach, views and saves'),
              trailing: TextButton(
                onPressed: () => widget.connect('${account['account']}'),
                child: const Text('Connect'),
              ),
            ),
          ),
      FutureBuilder<dynamic>(
        future: observations,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(28),
              child: CupertinoActivityIndicator(),
            );
          }
          if (snapshot.hasError || snapshot.data is! Map) {
            return Card(
              child: ListTile(
                title: const Text('Results couldn’t load'),
                subtitle: const Text(
                  'Your reels and schedules are still saved',
                ),
                trailing: TextButton(
                  onPressed: retry,
                  child: const Text('Retry'),
                ),
              ),
            );
          }
          final Map data = snapshot.data as Map;
          // Result cards deal into the same grid Review uses. One column on a
          // phone, which is the list that shipped.
          final int columns = SandLayout.columnsFor(
            MediaQuery.sizeOf(context).width,
          );
          final history = _activityRecords(data);
          final List<Map> records =
              (data['records'] is List ? data['records'] as List : <dynamic>[])
                  .whereType<Map>()
                  .where((item) => selected(item['account']))
                  .toList();
          final DateTime? observed = DateTime.tryParse(
            '${data['observed_at'] ?? ''}',
          )?.toLocal();
          final List<Map> rankedRecords = List<Map>.of(records)
            ..sort(
              (Map left, Map right) =>
                  (_reach(right) ?? -1).compareTo(_reach(left) ?? -1),
            );
          final Map? topRecord = rankedRecords.isEmpty
              ? null
              : rankedRecords.firstWhere(
                  (record) => _reach(record) != null,
                  orElse: () => <dynamic, dynamic>{},
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _tabs(records.length, history.length),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      observed == null
                          ? 'Latest results'
                          : 'Updated ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(observed))}',
                      style: const TextStyle(
                        color: SandDark.onSurfaceLow,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: retry,
                    tooltip: 'Refresh results',
                    icon: const Icon(CupertinoIcons.arrow_clockwise, size: 20),
                  ),
                ],
              ),
              AnimatedSwitcher(
                duration: CdMotion.duration(context, CdMotion.screen),
                switchInCurve: CdMotion.out,
                switchOutCurve: CdMotion.into,
                child: _activity
                    ? _activityView(history, data['history'] is List)
                    : Column(
                        key: const ValueKey('published-results'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (records.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 36),
                              child: Text(
                                'Results appear here after your reviewed reels are published.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          if (topRecord != null && topRecord.isNotEmpty)
                            _summary(topRecord),
                          if (rankedRecords.isNotEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 16, bottom: 8),
                              child: Text(
                                'Top reels',
                                style: TextStyle(
                                  color: SandDark.onSurfaceLowest,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: .8,
                                ),
                              ),
                            ),
                          // A result card is a card, so on an iPad the top
                          // three sit side by side and are compared rather
                          // than scrolled past. One per row on a phone: the
                          // list that shipped.
                          ...conCardRows(<Widget>[
                            for (final entry in rankedRecords.take(3).indexed)
                              CdEnter(
                                // Results arrive as a list; a short stagger preserves the
                                // list's order without holding up the refresh interaction.
                                key: ValueKey<Object?>(entry.$2['id']),
                                delay: CdMotion.stagger * entry.$1,
                                child: _resultCard(entry.$2),
                              ),
                          ], columns),
                          if (rankedRecords.length > 3)
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text(
                                'All results (${rankedRecords.length})',
                                style: const TextStyle(fontSize: 13),
                              ),
                              children: conCardRows(<Widget>[
                                for (final entry
                                    in rankedRecords.skip(3).indexed)
                                  CdEnter(
                                    key: ValueKey<Object?>(entry.$2['id']),
                                    delay: CdMotion.stagger * entry.$1,
                                    child: _resultCard(entry.$2),
                                  ),
                              ], columns),
                            ),
                          if (records.isNotEmpty)
                            const Text(
                              'Compare reels at similar ages. A dash means Instagram hasn’t supplied that metric.',
                              style: TextStyle(
                                color: SandDark.onSurfaceLow,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    ],
  );

  Widget _tabs(int published, int activity) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: SandDark.surfaceBase,
        border: Border.all(color: SandDark.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: CdTabIndicator(
          index: _activity ? 1 : 0,
          count: 2,
          color: studioAccent,
          child: Row(
            children: [
              for (final index in [0, 1])
                Expanded(
                  child: Semantics(
                    selected: _activity == (index == 1),
                    button: true,
                    child: CdPressFeedback(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                          backgroundColor: _activity == (index == 1)
                              ? SandDark.primaryContainer
                              : Colors.transparent,
                          shape: const RoundedRectangleBorder(),
                        ),
                        onPressed: () => setState(() => _activity = index == 1),
                        child: Text(
                          '${index == 0 ? 'Published' : 'Activity'} ${index == 0 ? published : activity}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, height: 1.3),
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
  );

  List<({DateTime at, int count})> _activityRecords(Map data) {
    final output = <({DateTime at, int count})>[];
    final seen = <String>{};
    for (final entry
        in (data['history'] is List ? data['history'] as List : const [])
            .whereType<Map>()) {
      final at = DateTime.tryParse('${entry['observed_at'] ?? ''}');
      if (at == null || entry['records'] is! List) continue;
      final ids = <Object>{};
      for (final record in (entry['records'] as List).whereType<Map>()) {
        if (!selected(record['account']) ||
            record['account'] is! String ||
            record['id'] == null) {
          continue;
        }
        final metrics = record['metrics'];
        if (metrics is Map &&
            metrics.values.any((v) => v is num && v.isFinite)) {
          ids.add('${record['account']}:${record['id']}');
        }
      }
      if (ids.isNotEmpty && seen.add(at.toUtc().toIso8601String())) {
        output.add((at: at.toLocal(), count: ids.length));
      }
    }
    output.sort((left, right) => right.at.compareTo(left.at));
    return output;
  }

  Widget _activityView(
    List<({DateTime at, int count})> history,
    bool available,
  ) => Column(
    key: const ValueKey('results-activity'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          history.isEmpty
              ? available
                    ? 'No recorded insights activity for this account yet.'
                    : 'Activity history is not available yet.'
              : 'Recorded insights checks for the selected accounts. These are measurements, not posting confirmations.',
          style: const TextStyle(
            fontSize: 14,
            color: SandDark.onSurfaceLow,
            height: 1.5,
          ),
        ),
      ),
      for (final entry in history.take(20))
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Insights checked',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  '${entry.count} ${entry.count == 1 ? 'reel has' : 'reels have'} available measurements.',
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 6),
                Text(
                  '${MaterialLocalizations.of(context).formatMediumDate(entry.at)} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(entry.at))}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: SandDark.onSurfaceLow,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      if (history.length > 20)
        const Text(
          'Showing the latest 20 checks.',
          style: TextStyle(fontSize: 13, color: SandDark.onSurfaceLow),
        ),
    ],
  );

  Widget _resultCard(Map record) {
    final Map<String, dynamic> reel = widget.catalog.firstWhere(
      (item) =>
          item['id'] == record['id'] && item['account'] == record['account'],
      orElse: () => <String, dynamic>{
        'id': record['id'],
        'title': 'Published reel',
        'account': record['account'],
      },
    );
    final Map fields = record['media_fields'] is Map
        ? record['media_fields'] as Map
        : <String, dynamic>{};
    final Map metrics =
        record['state'] == 'observed' && record['metrics'] is Map
        ? record['metrics'] as Map
        : <String, dynamic>{};
    final DateTime? published = DateTime.tryParse(
      '${fields['timestamp'] ?? ''}',
    )?.toLocal();
    final String title = '${reel['title'] ?? 'Published reel'}'.trim();
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: SandDark.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            CdPressFeedback(
              child: InkWell(
                onTap: () => widget.preview(reel),
                borderRadius: BorderRadius.circular(SandRadius.r2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(SandRadius.r2),
                      child: Image.network(
                        '${widget.base}/reels/file/${Uri.encodeComponent('${record['id']}')}.poster',
                        width: 54,
                        height: 76,
                        fit: BoxFit.cover,
                        cacheWidth: 180,
                        headers: TrialCredentials.mediaHeaders(widget.base),
                        errorBuilder: (_, error, stackTrace) => const SizedBox(
                          width: 54,
                          height: 76,
                          child: Icon(
                            CupertinoIcons.play_rectangle,
                            color: studioAccent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            title,
                            softWrap: true,
                            style: const TextStyle(
                              fontSize: 17,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${record['account'] ?? ''}',
                            style: const TextStyle(
                              color: SandDark.onSurfaceLow,
                              fontSize: 12,
                            ),
                          ),
                          if (published != null)
                            Text(
                              MaterialLocalizations.of(
                                context,
                              ).formatMediumDate(published),
                              style: const TextStyle(
                                color: SandDark.onSurfaceLow,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(left: 8, top: 2),
                      child: Icon(
                        CupertinoIcons.play_circle,
                        color: studioAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final double scale =
                    MediaQuery.textScalerOf(context).scale(12) / 12;
                final int columns = constraints.maxWidth >= 280 && scale <= 1.2
                    ? 3
                    : 2;
                final List<(String, dynamic)> values = <(String, dynamic)>[
                  ('Views', metrics['views']),
                  ('Reach', metrics['reach']),
                  ('Likes', fields['like_count']),
                  ('Comments', fields['comments_count']),
                  ('Shares', metrics['shares']),
                  ('Saves', metrics['saved'] ?? metrics['saves']),
                ];
                return Wrap(
                  runSpacing: 20,
                  children: <Widget>[
                    for (final entry in values.indexed)
                      SizedBox(
                        width: constraints.maxWidth / columns,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            border: entry.$1 % columns == 0
                                ? null
                                : const Border(
                                    left: BorderSide(color: SandDark.outline),
                                  ),
                          ),
                          child: _metric(entry.$2.$1, entry.$2.$2),
                        ),
                      ),
                  ],
                );
              },
            ),
            if (record['state'] != 'observed')
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Text(
                  'Full analytics pending',
                  style: TextStyle(color: SandDark.warning, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  num? _reach(Map record) {
    if (record['state'] != 'observed') return null;
    final dynamic metrics = record['metrics'];
    return metrics is Map && metrics['reach'] is num
        ? metrics['reach'] as num
        : null;
  }

  num? _interactions(Map record) {
    if (record['state'] != 'observed') return null;
    final dynamic metrics = record['metrics'];
    if (metrics is Map && metrics['total_interactions'] is num) {
      return metrics['total_interactions'] as num;
    }
    final dynamic fields = record['media_fields'];
    return fields is Map && fields['total_interactions'] is num
        ? fields['total_interactions'] as num
        : null;
  }

  /// A compact, factual opening for the packet's Results screen. It uses a
  /// measured best reel and never synthesizes trends, deltas, or sparklines.
  Widget _summary(Map record) {
    final num? reach = _reach(record);
    final num? interactions = _interactions(record);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: <Widget>[
          Expanded(child: _summaryMetric('Best reach', reach)),
          if (interactions != null) ...<Widget>[
            const SizedBox(width: 9),
            Expanded(child: _summaryMetric('Interactions', interactions)),
          ],
        ],
      ),
    );
  }

  Widget _summaryMetric(String label, num? value) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value?.toString() ?? 'Not available',
            style: TextStyle(
              fontSize: value == null ? 12 : 24,
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(color: SandDark.onSurfaceLow, fontSize: 12),
          ),
        ],
      ),
    ),
  );

  // Unknown is not zero. Keep the primary numbers quiet and truthful.
  Widget _metric(String label, dynamic value) => Semantics(
    container: true,
    label: '$label: ${value is num ? value : 'Not available'}',
    excludeSemantics: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value is num ? '$value' : '–',
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              color: value is num ? studioAccent : SandDark.onSurfaceLow,
            ),
          ),
        ),
        Text(
          label,
          softWrap: true,
          style: const TextStyle(
            fontSize: 12,
            height: 1.4,
            color: SandDark.onSurfaceLow,
          ),
        ),
      ],
    ),
  );
}

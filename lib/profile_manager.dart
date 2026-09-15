import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'console_shell.dart';
import 'app_motion.dart';
import 'app_theme.dart';

String _words(dynamic value, [String fallback = 'Not available']) {
  if (value is! String || value.trim().isEmpty) return fallback;
  final text = value.trim().replaceAll('_', ' ');
  return text[0].toUpperCase() + text.substring(1);
}

String _reference(dynamic value) {
  if (value is! String || value.trim().isEmpty) return 'No reference supplied';
  return _words(
    value
        .replaceAll('-', ' ')
        .replaceAllMapped(
          RegExp(r'\bv(\d+)\b'),
          (match) => 'version ${match[1]}',
        ),
  );
}

String _recommendationTitle(Map row) => switch (row['id']) {
  'resolve_queue' => 'Check posts that need attention',
  'analytics_coverage' => 'Refresh your results',
  'taste_unavailable' => 'Source reviews are unavailable',
  'review_reference' => 'Review a high-view reel',
  _ => _words(row['title'], 'Suggested next step'),
};

String _recommendationReason(Map row) => switch (row['id']) {
  'resolve_queue' => 'Open Schedule and check these posts before adding more.',
  'analytics_coverage' =>
    'Some results are missing or out of date. Comparisons may be incomplete.',
  'taste_unavailable' =>
    'Your saved source choices could not be loaded. This does not mean your reviews were lost.',
  'review_reference' =>
    'This reel has more recorded views. Compare posts at the same age before drawing conclusions.',
  _ => _words(
    row['reason'],
    'Review the available details before making a change.',
  ),
};

String _missing(dynamic value) {
  if (value is! String) return 'Some supporting data is unavailable.';
  if (value.contains('source-taste-reviews.json')) {
    return 'Saved source reviews could not be loaded.';
  }
  if (value.contains('provider-insights-cache.json')) {
    return 'Saved Instagram results could not be loaded.';
  }
  if (value.contains('catalog.json')) {
    return 'The clip library could not be loaded.';
  }
  if (value.contains('Retention curves')) {
    return 'Audience retention is available only when Instagram supplies it.';
  }
  if (value.contains('skip-rate')) {
    return 'Watch time and skip rate are kept separate until their units are verified.';
  }
  if (value.contains('source bytes')) {
    return 'Source reviews come from saved history. This brief does not recheck the original files.';
  }
  if (value.contains('owned funnel route')) {
    return 'Funnel connection status is unavailable.';
  }
  if (value.contains('owner draft library')) {
    return 'The draft library is unavailable.';
  }
  if (value.contains('.json')) {
    return 'Some saved supporting data could not be loaded.';
  }
  return _words(value);
}

class ProfileManagerCard extends StatefulWidget {
  const ProfileManagerCard({
    super.key,
    required this.accounts,
    required this.read,
  });
  final List<String> accounts;
  final Future<dynamic> Function(String) read;
  @override
  State<ProfileManagerCard> createState() => _ProfileManagerCardState();
}

class _ProfileManagerCardState extends State<ProfileManagerCard> {
  String? account;
  Future<dynamic>? brief;
  void load(String selected) {
    setState(() {
      account = selected;
      brief = widget.read(
        '/reels/profile-manager?account=${Uri.encodeComponent(selected)}',
      );
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.accounts.isNotEmpty) load(widget.accounts.first);
  }

  @override
  void didUpdateWidget(covariant ProfileManagerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.accounts.contains(account)) {
      if (widget.accounts.isEmpty) {
        account = null;
        brief = null;
      } else {
        load(widget.accounts.first);
      }
    }
  }

  List<Map> rows(dynamic value) =>
      value is List ? value.whereType<Map>().toList() : [];

  String date(dynamic value, {String empty = 'Not available'}) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) return empty;
    final local = parsed.toLocal();
    final format = MaterialLocalizations.of(context);
    return '${format.formatMediumDate(local)} · ${format.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  Widget field(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Ty.meta.copyWith(color: Con.ink3)),
        const SizedBox(height: 3),
        Text(value, style: Ty.label.copyWith(height: 1.45)),
      ],
    ),
  );

  Widget evidence(dynamic value, {int depth = 0}) {
    if (value == null ||
        (value is Map && value.isEmpty) ||
        (value is List && value.isEmpty)) {
      return const Text('No supporting details are available yet.');
    }
    if (depth > 3) {
      return const Text('Additional supporting details are unavailable here.');
    }
    if (value is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in value)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Con.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Con.rule),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: entry is String
                      ? field('Reference', _reference(entry))
                      : evidence(entry, depth: depth + 1),
                ),
              ),
            ),
        ],
      );
    }
    if (value is Map) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in value.entries)
            if (entry.value is Map || entry.value is List)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_words(entry.key), style: Ty.label),
                    evidence(entry.value, depth: depth + 1),
                  ],
                ),
              )
            else
              field(
                switch (entry.key) {
                  'reel_id' || 'parent_reel_id' || 'id' => 'Reference',
                  'observed_at' => 'Last measured',
                  'scheduled_at' => 'Scheduled for',
                  'matched_reels' => 'Reels with matching results',
                  'stale' => 'Results freshness',
                  'state' => 'Status',
                  _ => _words(entry.key),
                },
                switch (entry.key) {
                  'reel_id' ||
                  'parent_reel_id' ||
                  'id' => _reference(entry.value),
                  'observed_at' => date(entry.value),
                  'scheduled_at' => date(entry.value, empty: 'No time set'),
                  'stale' =>
                    entry.value == true
                        ? 'Out of date'
                        : entry.value == false
                        ? 'Current'
                        : 'Unknown',
                  _ =>
                    entry.value is num
                        ? entry.value.toString()
                        : entry.value is bool
                        ? entry.value == true
                              ? 'Yes'
                              : 'No'
                        : _words(entry.value),
                },
              ),
        ],
      );
    }
    return Text(value is num ? '$value' : _words(value));
  }

  void details(Map data) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: SandLayout.sheet),
      sheetAnimationStyle: AnimationStyle(
        duration: CdMotion.duration(context, CdMotion.hero),
        reverseDuration: CdMotion.duration(context, CdMotion.screen),
      ),
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .8,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Profile manager · $account',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'Recommendations and draft ideas. Nothing runs or posts automatically.',
              ),
              const SizedBox(height: 16),
              if (rows(data['recommendations']).isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No changes suggested right now.'),
                ),
              ...rows(data['recommendations']).map(
                (row) => ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  expansionAnimationStyle: AnimationStyle(
                    duration: CdMotion.duration(context, CdMotion.hero),
                    curve: CdMotion.out,
                  ),
                  title: Text(
                    _recommendationTitle(row),
                    style: Ty.label.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _recommendationReason(row),
                      style: Ty.meta.copyWith(height: 1.5),
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
                      child: evidence(row['evidence']),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Experiment drafts',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (rows(data['draft_experiments']).isEmpty)
                const Text(
                  'More matched performance data is needed before recommending a creative experiment.',
                ),
              ...rows(data['draft_experiments']).map(
                (row) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _words(row['variable'], 'Creative experiment'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _words(
                            row['direction'],
                            'No direction supplied yet.',
                          ),
                          style: Ty.meta.copyWith(height: 1.5),
                        ),
                        const SizedBox(height: 8),
                        field('Reference', _reference(row['parent_reel_id'])),
                        field(
                          'How to compare',
                          row['measurement'] ==
                                  'Compare distinct reels at matched 24h/72h/7d ages; preserve raw units and do not infer causality.'
                              ? 'Compare different reels after 24 hours, 72 hours and 7 days. Keep each metric separate. A difference does not prove what caused it.'
                              : _words(
                                  row['measurement'],
                                  'A measurement plan has not been supplied yet.',
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ExpansionTile(
                title: const Text('Data coverage'),
                expansionAnimationStyle: AnimationStyle(
                  duration: CdMotion.duration(context, CdMotion.hero),
                  curve: CdMotion.out,
                ),
                children: [
                  ListTile(
                    title: const Text('Last measured'),
                    subtitle: Text(
                      date(
                        data['analytics'] is Map
                            ? data['analytics']['observed_at']
                            : null,
                      ),
                    ),
                  ),
                  if (data['missing_data'] is! List ||
                      (data['missing_data'] as List).isEmpty)
                    const ListTile(
                      title: Text('No additional data limits were reported.'),
                    ),
                  ...(data['missing_data'] is List
                          ? data['missing_data'] as List
                          : const [])
                      .map(
                        (value) => ListTile(
                          title: Text(
                            _missing(value),
                            style: Ty.meta.copyWith(height: 1.5),
                          ),
                        ),
                      ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DoctorCard(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Con.signal.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  CupertinoIcons.person_fill,
                  color: Con.signalBright,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Profile manager', style: Ty.title),
                    const SizedBox(height: 4),
                    Text(
                      'Choose an account for prompts and ideas',
                      style: Ty.meta,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.accounts.isNotEmpty)
            DropdownButton<String>(
              isExpanded: true,
              value: account,
              items: widget.accounts
                  .map(
                    (name) => DropdownMenuItem(value: name, child: Text(name)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) load(value);
              },
            ),
          FutureBuilder<dynamic>(
            key: ValueKey(account),
            future: brief,
            builder: (context, snapshot) {
              if (account == null) {
                return const Text('Choose an account to see its brief.');
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Loading your brief…'),
                );
              }
              if (snapshot.hasError || snapshot.data is! Map) {
                return Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Brief unavailable. Your reels and schedule still work.',
                      ),
                    ),
                    TextButton(
                      onPressed: account == null ? null : () => load(account!),
                      child: const Text('Retry'),
                    ),
                  ],
                );
              }
              final data = snapshot.data as Map;
              final recommendations = rows(data['recommendations']);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recommendations.isEmpty
                        ? 'No changes suggested right now.'
                        : _recommendationTitle(recommendations.first),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (recommendations.isNotEmpty)
                    Text(
                      _recommendationReason(recommendations.first),
                      style: Ty.meta.copyWith(height: 1.5),
                    ),
                  TextButton(
                    onPressed: () => details(data),
                    child: const Text('View brief & experiment ideas'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}

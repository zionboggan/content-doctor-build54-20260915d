import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'console_shell.dart';

typedef GenerationRead = Future<dynamic> Function(String path);
typedef GenerationWrite =
    Future<dynamic> Function(String path, Map<String, dynamic> payload);

class GenerationPage extends StatefulWidget {
  const GenerationPage({
    super.key,
    required this.accounts,
    required this.read,
    required this.write,
  });
  final List<String> accounts;
  final GenerationRead read;
  final GenerationWrite write;

  @override
  State<GenerationPage> createState() => _GenerationPageState();
}

class _GenerationPageState extends State<GenerationPage> {
  static const List<Map<String, String>> defaults = <Map<String, String>>[
    {'id': 'tech_larp', 'label': 'Tech LARP'},
    {'id': 'luxury_lifestyle', 'label': 'Luxury lifestyle'},
    {'id': 'interview', 'label': 'Interview'},
    {'id': 'festival', 'label': 'Festival'},
    {'id': 'promotion', 'label': 'Promotion'},
  ];
  static const List<String> intensityLabels = <String>[
    'No captions',
    'Clean',
    'Confident',
    'Bold',
    'Maximum energy',
  ];
  List<Map<String, String>> templates = List<Map<String, String>>.from(
    defaults,
  );
  List<Map<String, String>> musicOptions = <Map<String, String>>[];
  List<Map<String, dynamic>> plans = <Map<String, dynamic>>[];
  Map<String, dynamic>? finalists;
  String? account;
  String template = 'tech_larp';
  String? batchId;
  double duration = 10, intensity = 2;
  bool busy = false, reviewed = false, finalistsOnly = false;
  int _discoverGeneration = 0;
  String message = 'Choose a recipe, then generate five editable drafts.';

  @override
  void initState() {
    super.initState();
    account = widget.accounts.isEmpty ? null : widget.accounts.first;
    _discover();
  }

  Future<void> _discover() async {
    final int generation = ++_discoverGeneration;
    final String? requestedAccount = account;
    try {
      final List<dynamic>
      responses = await Future.wait<dynamic>(<Future<dynamic>>[
        widget.read(
          '/reels/generation/options?account=${Uri.encodeComponent(requestedAccount ?? '')}',
        ),
        widget
            .read(
              '/reels/source-finalists?account=${Uri.encodeComponent(requestedAccount ?? '')}',
            )
            .catchError((Object _) => <String, dynamic>{}),
      ]);
      final dynamic value = responses[0];
      if (!mounted ||
          generation != _discoverGeneration ||
          requestedAccount != account ||
          value is! Map ||
          value['templates'] is! List) {
        return;
      }
      final List<Map<String, String>> available = <Map<String, String>>[];
      for (final dynamic raw in value['templates']) {
        if (raw is! Map) continue;
        final String id = '${raw['id'] ?? raw['value'] ?? ''}';
        if (id.isEmpty) continue;
        available.add(<String, String>{
          'id': id,
          'label': '${raw['label'] ?? raw['name'] ?? id}',
        });
      }
      final List<Map<String, String>> songs = <Map<String, String>>[];
      if (value['music'] is List) {
        for (final dynamic raw in value['music']) {
          if (raw is! Map || raw['id'] == null) continue;
          songs.add(<String, String>{
            'id': '${raw['id']}',
            'label': '${raw['label'] ?? raw['id']}',
          });
        }
      }
      setState(() {
        if (available.isNotEmpty) {
          templates = available;
          template = available.first['id']!;
        }
        musicOptions = songs;
        finalists = responses[1] is Map
            ? Map<String, dynamic>.from(responses[1] as Map)
            : null;
      });
    } catch (_) {
      if (mounted &&
          generation == _discoverGeneration &&
          requestedAccount == account) {
        setState(() {
          message =
              'Generation service is still coming online. Your choices stay here.';
        });
      }
    }
  }

  Map<String, dynamic> _payload(bool randomize) => <String, dynamic>{
    'account': account,
    'template_id': template,
    'duration_seconds': duration.round(),
    'caption_intensity': intensity.round(),
    'owner_finalists_only': finalistsOnly,
    'randomize': randomize,
    if (randomize && batchId != null) 'parent_batch_id': batchId,
    if (randomize)
      'randomize_nonce': DateTime.now().microsecondsSinceEpoch.toString(),
  };

  Future<void> _generate(bool randomize) async {
    if (account == null || busy) return;
    final Map<String, dynamic>? readiness =
        finalists?['generation_readiness'] is Map
        ? Map<String, dynamic>.from(finalists!['generation_readiness'] as Map)
        : null;
    if (finalistsOnly && readiness?['ready_for_review_only_preview'] != true) {
      setState(
        () => message =
            '${readiness?['next_action'] ?? 'Choose at least five current source finalists first.'}',
      );
      return;
    }
    setState(() {
      busy = true;
      reviewed = false;
      message = randomize ? 'Building a fresh mix…' : 'Building five plans…';
    });
    try {
      final dynamic result = await widget.write(
        '/reels/generation/preview',
        _payload(randomize),
      );
      final dynamic rows = result is Map
          ? (result['plans'] ?? result['drafts'])
          : null;
      if (rows is! List || rows.isEmpty) {
        throw StateError(
          'No drafts were returned. Your previous plan is safe.',
        );
      }
      if (!mounted) return;
      setState(() {
        batchId = '${result['batch_id'] ?? ''}';
        plans = rows.indexed.map((entry) {
          final int index = entry.$1;
          final Map<String, dynamic> row = Map<String, dynamic>.from(
            entry.$2 as Map,
          );
          final Map<String, dynamic> render = row['render_payload'] is Map
              ? Map<String, dynamic>.from(row['render_payload'] as Map)
              : <String, dynamic>{};
          final Map<String, String> sourceNames = <String, String>{};
          if (row['attribution'] is Map &&
              row['attribution']['sources'] is List) {
            for (final dynamic source in row['attribution']['sources']) {
              if (source is Map && source['asset_id'] != null) {
                sourceNames['${source['asset_id']}'] =
                    '${source['title'] ?? source['asset_id']}';
              }
            }
          }
          final List<dynamic> clips =
              List<dynamic>.from(
                (row['clips'] ?? render['shots'] ?? const []) as List,
              ).map((dynamic clip) {
                if (clip is! Map) return clip;
                final Map<String, dynamic> copy = Map<String, dynamic>.from(
                  clip,
                );
                final String id =
                    '${copy['id'] ?? copy['source_reel_id'] ?? ''}';
                copy['title'] ??= sourceNames[id];
                return copy;
              }).toList();
          final Map<String, dynamic>? songBucket =
              row['attribution'] is Map &&
                  row['attribution']['song_bucket'] is Map
              ? Map<String, dynamic>.from(
                  row['attribution']['song_bucket'] as Map,
                )
              : null;
          return <String, dynamic>{
            ...row,
            'plan_id': row['plan_id'] ?? row['id'] ?? 'plan-${index + 1}',
            'title': row['title'] ?? render['title'] ?? 'Draft ${index + 1}',
            'clips': clips,
            'caption':
                row['caption_text'] ??
                row['caption'] ??
                render['caption'] ??
                '',
            'music': row['music_id'] ?? render['music_asset_id'] ?? '',
            'music_label':
                row['music_label'] ??
                row['music_id'] ??
                (row['attribution'] is Map &&
                        row['attribution']['song_bucket'] is Map
                    ? row['attribution']['song_bucket']['label']
                    : null) ??
                render['music_asset_id'] ??
                '',
            'music_cue_seconds':
                row['music_cue_seconds'] ?? songBucket?['cue_seconds'],
            'music_cue_basis':
                row['music_cue_basis'] ?? songBucket?['cue_basis'],
            'schedule_suggestion': row['schedule_suggestion'],
            'selected': true,
          };
        }).toList();
        message =
            'Adjust the five plans, then review what should enter editing.';
      });
    } on Object catch (error) {
      if (mounted) setState(() => message = '$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _queue() async {
    if (!reviewed || busy || account == null) return;
    final List<Map<String, dynamic>> selected = plans
        .where((Map<String, dynamic> row) => row['selected'] == true)
        .toList();
    if (selected.isEmpty) return;
    setState(() => busy = true);
    try {
      final dynamic result = await widget.write('/reels/generation/queue', {
        'batch_id': batchId,
        'account': account,
        'plan_ids': selected.map((row) => row['plan_id']).toList(),
        'adjustments': {
          for (final row in selected)
            '${row['plan_id']}': {
              'clip_order': (row['clips'] as List)
                  .map(
                    (clip) => clip is Map
                        ? (clip['id'] ?? clip['source_reel_id'])
                        : clip,
                  )
                  .toList(),
              'caption_text': row['caption'],
              'music_id': row['music'],
            },
        },
        'confirm_review': true,
      });
      if (!mounted) return;
      setState(() {
        message = result is Map && result['message'] != null
            ? '${result['message']}'
            : 'Drafts queued for editing and review. Nothing was scheduled.';
      });
    } on Object catch (error) {
      if (mounted) setState(() => message = '$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _move(List<dynamic> clips, int from, int delta) {
    final int to = from + delta;
    if (to < 0 || to >= clips.length) return;
    setState(() {
      final dynamic item = clips.removeAt(from);
      clips.insert(to, item);
      reviewed = false;
    });
  }

  void _recipeChanged(VoidCallback change) {
    setState(() {
      change();
      plans.clear();
      batchId = null;
      reviewed = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Generate five reels')),
    body: SafeArea(
      // The recipe, and the five drafts it produced. On a phone they are one
      // column in the order they shipped; on an iPad the recipe stays on the
      // left while the drafts fill the right, so changing the style and
      // seeing what it did to the batch is one screen instead of two scrolls.
      child: ConPanes(
        primary: <Widget>[
          const Text(
            'Choose one account and creative recipe. Every result waits for review.',
            style: TextStyle(color: SandDark.onSurfaceLow),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: account,
            decoration: const InputDecoration(labelText: 'Account'),
            items: widget.accounts
                .map(
                  (name) =>
                      DropdownMenuItem<String>(value: name, child: Text(name)),
                )
                .toList(),
            onChanged: busy
                ? null
                : (value) {
                    _recipeChanged(() => account = value);
                    _discover();
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: template,
            decoration: const InputDecoration(labelText: 'Content style'),
            items: templates
                .map(
                  (item) => DropdownMenuItem<String>(
                    value: item['id'],
                    child: Text(item['label']!),
                  ),
                )
                .toList(),
            onChanged: busy
                ? null
                : (value) => _recipeChanged(() => template = value!),
          ),
          const SizedBox(height: 16),
          Text('Length · ${duration.round()} seconds'),
          Slider(
            value: duration,
            min: 5,
            max: 20,
            divisions: 15,
            label: '${duration.round()} seconds',
            onChanged: busy
                ? null
                : (value) => _recipeChanged(() => duration = value),
          ),
          Text('Caption energy · ${intensityLabels[intensity.round()]}'),
          Slider(
            value: intensity,
            min: 0,
            max: 4,
            divisions: 4,
            label: intensityLabels[intensity.round()],
            onChanged: busy
                ? null
                : (value) => _recipeChanged(() => intensity = value),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: finalistsOnly,
            title: const Text('Use only my current source finalists'),
            subtitle: Text(
              finalists?['generation_readiness']?['next_action']?.toString() ??
                  'Mark source clips Use in Studio to build a focused batch.',
            ),
            onChanged: busy
                ? null
                : (value) =>
                      _recipeChanged(() => finalistsOnly = value == true),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : () => _generate(false),
                  icon: const Icon(CupertinoIcons.sparkles),
                  label: const Text('Generate 5'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy || plans.isEmpty
                      ? null
                      : () => _generate(true),
                  icon: const Icon(CupertinoIcons.shuffle),
                  label: const Text('Randomize'),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              message,
              style: const TextStyle(color: SandDark.warning),
            ),
          ),
        ],
        secondary: <Widget>[
          for (int index = 0; index < plans.length; index++)
            _PlanCard(
              key: ValueKey<String>('generation-${plans[index]['plan_id']}'),
              plan: plans[index],
              musicOptions: musicOptions,
              index: index,
              changed: () => setState(() => reviewed = false),
              move: (from, delta) =>
                  _move(plans[index]['clips'] as List<dynamic>, from, delta),
            ),
          if (plans.isNotEmpty) ...<Widget>[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: reviewed,
              title: const Text(
                'I reviewed the clips, captions, music and account.',
              ),
              subtitle: const Text('Keep every result review-only.'),
              onChanged: (value) => setState(() => reviewed = value == true),
            ),
            FilledButton(
              onPressed: reviewed && !busy ? _queue : null,
              child: const Text('Send selected drafts to review'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _PlanCard extends StatefulWidget {
  const _PlanCard({
    super.key,
    required this.plan,
    required this.index,
    required this.changed,
    required this.move,
    required this.musicOptions,
  });
  final Map<String, dynamic> plan;
  final int index;
  final VoidCallback changed;
  final void Function(int from, int delta) move;
  final List<Map<String, String>> musicOptions;

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  late final TextEditingController caption;
  late final TextEditingController music;
  @override
  void initState() {
    super.initState();
    caption = TextEditingController(text: '${widget.plan['caption'] ?? ''}');
    music = TextEditingController(text: '${widget.plan['music_label'] ?? ''}');
  }

  @override
  void dispose() {
    caption.dispose();
    music.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic> clips = widget.plan['clips'] as List<dynamic>;
    final num? cueSeconds = num.tryParse(
      '${widget.plan['music_cue_seconds'] ?? ''}',
    );
    final String cueBasis = '${widget.plan['music_cue_basis'] ?? ''}'.trim();
    final String cueSubtitle = cueSeconds != null && cueBasis.isNotEmpty
        ? 'Starts at $cueBasis · ${cueSeconds % 1 == 0 ? cueSeconds.toInt() : cueSeconds}s'
        : '';
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: widget.plan['selected'] == true,
              title: Text(
                '${widget.plan['title'] ?? 'Draft ${widget.index + 1}'}',
              ),
              subtitle: const Text('Review-only plan'),
              onChanged: (value) {
                widget.plan['selected'] = value == true;
                widget.changed();
              },
            ),
            if (cueSubtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 8),
                child: Text(
                  cueSubtitle,
                  style: const TextStyle(
                    color: SandDark.onSurfaceLow,
                    fontSize: 12,
                  ),
                ),
              ),
            if (widget.plan['schedule_suggestion'] is Map &&
                widget.plan['schedule_suggestion']['suggested_at'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Suggested posting window · ${widget.plan['schedule_suggestion']['suggested_at']} · review before scheduling',
                  style: const TextStyle(
                    color: SandDark.onSurfaceLow,
                    fontSize: 12,
                  ),
                ),
              ),
            for (int i = 0; i < clips.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  clips[i] is Map
                      ? '${clips[i]['title'] ?? clips[i]['name'] ?? clips[i]['id'] ?? clips[i]['source_reel_id'] ?? 'Clip ${i + 1}'}'
                      : '$clips[i]',
                ),
                trailing: Wrap(
                  children: <Widget>[
                    IconButton(
                      onPressed: i == 0 ? null : () => widget.move(i, -1),
                      icon: const Icon(CupertinoIcons.arrow_up),
                    ),
                    IconButton(
                      onPressed: i == clips.length - 1
                          ? null
                          : () => widget.move(i, 1),
                      icon: const Icon(CupertinoIcons.arrow_down),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: caption,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Caption'),
              onChanged: (value) {
                widget.plan['caption'] = value;
                widget.changed();
              },
            ),
            const SizedBox(height: 10),
            if (widget.musicOptions.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue:
                    widget.musicOptions.any(
                      (song) => song['id'] == widget.plan['music'],
                    )
                    ? '${widget.plan['music']}'
                    : widget.musicOptions.first['id'],
                decoration: const InputDecoration(labelText: 'Music or audio'),
                items: widget.musicOptions
                    .map(
                      (song) => DropdownMenuItem<String>(
                        value: song['id'],
                        child: Text(song['label']!),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  widget.plan['music'] = value;
                  widget.changed();
                },
              )
            else
              TextField(
                controller: music,
                decoration: const InputDecoration(labelText: 'Music or audio'),
                onChanged: (value) {
                  widget.plan['music'] = value;
                  widget.changed();
                },
              ),
          ],
        ),
      ),
    );
  }
}

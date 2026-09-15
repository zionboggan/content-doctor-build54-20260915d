// Flyer and carousel composer.
//
// One slide is a flyer; two to ten slides are an Instagram carousel. This is
// the app surface over the Desert Events deck composer; the render itself is
// dispatched by the backend's /flyers/render route and polled through the same
// RenderJobs state machine the reel editor already uses.
//
// Two rules shape this screen, and both are the reason it looks plain:
//
//  1. Nothing is invented. Every string that lands on a slide is typed here,
//     verbatim. A blank required slot is refused with its name, or - only if
//     the operator deliberately asks for it - rendered as a visible [SLOT]
//     token. There is no mode that derives one field from another, so a date
//     never gains a weekday and a venue never gains a city.
//  2. Nothing publishes. Every render is review-only, exactly like every other
//     export path in this app.
//
// HUD Ticket is the only implemented template. Energy Photo (Mode A) is
// declared in the locked spec but was refused pending approval, so it has no
// control here rather than a disabled one that implies it is coming.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'console_shell.dart' show ConPanes;
import 'render_jobs.dart';

typedef FlyerRead = Future<dynamic> Function(String path);
typedef FlyerWrite =
    Future<dynamic> Function(String path, Map<String, dynamic> payload);

/// Slot ids come straight from the composer's allow-list. Anything not here is
/// a hard error server-side, so the form cannot offer a field that would be
/// refused.
const Map<String, String> flyerSlotLabels = <String, String>{
  'ARTIST_NAME': 'Artist name',
  'DATE': 'Date',
  'VENUE': 'Venue',
  'CITY': 'City',
  'EVENT_ID': 'Event ID',
  'CTA': 'Call to action',
  'SECTION_LABEL': 'Section label',
  'BODY_LINE': 'Line',
};

/// Per-role slots, in the order the locked hierarchy renders them.
const Map<String, List<String>> flyerRoleSlots = <String, List<String>>{
  'hook': <String>['ARTIST_NAME', 'DATE', 'VENUE', 'CITY', 'EVENT_ID', 'CTA'],
  'body': <String>['SECTION_LABEL'],
  'cta': <String>['CTA'],
};

const List<Map<String, String>> flyerRoles = <Map<String, String>>[
  <String, String>{'id': 'hook', 'label': 'Hook · the full flyer'},
  <String, String>{'id': 'body', 'label': 'Body · details list'},
  <String, String>{'id': 'cta', 'label': 'Call to action'},
];

/// HUD Ticket only. Energy Photo stays unbuilt and unoffered.
const List<Map<String, String>> flyerTemplates = <Map<String, String>>[
  <String, String>{'id': 'hud_ticket', 'label': 'HUD Ticket'},
];

const List<String> flyerBrandMarks = <String>[
  'Desert Events 2.png',
  'Desert Events 1.png',
  'DE Full.png',
  'DE Badge.png',
  'DE Alt.png',
];

const int flyerMaxSlides = 10;
const int flyerBodyLines = 4;

/// One slide's editable state. Owns its controllers so a reorder moves the
/// typed text with the slide instead of leaving it behind.
class FlyerSlideDraft {
  FlyerSlideDraft(this.id, this.role) {
    for (final String slot in flyerRoleSlots[role]!) {
      fields[slot] = TextEditingController();
    }
    if (role == 'body') {
      for (int i = 0; i < flyerBodyLines; i++) {
        lines.add(TextEditingController());
      }
    }
  }

  final String id;
  final String role;
  final Map<String, TextEditingController> fields =
      <String, TextEditingController>{};
  final List<TextEditingController> lines = <TextEditingController>[];

  void dispose() {
    for (final TextEditingController c in fields.values) {
      c.dispose();
    }
    for (final TextEditingController c in lines) {
      c.dispose();
    }
  }

  /// Values the operator actually typed. Blank stays blank.
  List<Map<String, String>> textLayers() {
    final List<Map<String, String>> layers = <Map<String, String>>[];
    for (final String slot in flyerRoleSlots[role]!) {
      final String value = fields[slot]!.text.trim();
      if (value.isNotEmpty) {
        layers.add(<String, String>{'field': slot, 'value': value});
      }
    }
    for (final TextEditingController line in lines) {
      final String value = line.text.trim();
      if (value.isNotEmpty) {
        layers.add(<String, String>{'field': 'BODY_LINE', 'value': value});
      }
    }
    return layers;
  }

  /// Names of the required slots the operator has left empty, in slide order.
  List<String> blanks() {
    final List<String> missing = <String>[];
    for (final String slot in flyerRoleSlots[role]!) {
      if (fields[slot]!.text.trim().isEmpty) missing.add(slot);
    }
    if (role == 'body' &&
        lines.every((TextEditingController c) => c.text.trim().isEmpty)) {
      missing.add('BODY_LINE');
    }
    return missing;
  }
}

/// Problems that must be fixed before a deck may be sent, each naming the
/// exact slide and slot. Returns an empty list when the deck is submittable.
List<String> flyerDeckProblems({
  required String deckId,
  required String? account,
  required List<FlyerSlideDraft> slides,
  required bool allowPlaceholders,
}) {
  final List<String> problems = <String>[];
  if (account == null || account.isEmpty) {
    problems.add('Choose an account.');
  }
  if (deckId.isEmpty) {
    problems.add('Give this flyer a name.');
  } else if (!RegExp(r'^[a-z0-9][a-z0-9-]{2,63}$').hasMatch(deckId)) {
    problems.add(
      'The name must be 3 to 64 lowercase letters, numbers or hyphens.',
    );
  }
  if (slides.isEmpty) {
    problems.add('Add at least one slide.');
  } else if (slides.length > flyerMaxSlides) {
    problems.add(
      'Instagram takes one image or a 2 to $flyerMaxSlides image carousel.',
    );
  }
  if (!allowPlaceholders) {
    for (int i = 0; i < slides.length; i++) {
      final List<String> blanks = slides[i].blanks();
      if (blanks.isEmpty) continue;
      problems.add(
        'Slide ${i + 1} is missing ${blanks.map((String slot) => flyerSlotLabels[slot]!.toLowerCase()).join(', ')}.',
      );
    }
  }
  return problems;
}

class FlyerComposerPage extends StatefulWidget {
  const FlyerComposerPage({
    super.key,
    required this.accounts,
    required this.read,
    required this.write,
  });

  /// Account scoping, same permitted-account list the native editor is given.
  final List<String> accounts;
  final FlyerRead read;
  final FlyerWrite write;

  @override
  State<FlyerComposerPage> createState() => _FlyerComposerPageState();
}

class _FlyerComposerPageState extends State<FlyerComposerPage> {
  final TextEditingController deckName = TextEditingController();
  final List<FlyerSlideDraft> slides = <FlyerSlideDraft>[];
  final RenderJobs renderJobs = RenderJobs();
  final Map<String, Map<String, dynamic>> manifests =
      <String, Map<String, dynamic>>{};

  String? account;
  String template = 'hud_ticket';
  String brandMark = flyerBrandMarks.first;
  bool demo = true;
  bool allowPlaceholders = false;
  bool reviewed = false;
  bool busy = false;
  bool polling = false;
  int _slideSeed = 0;
  Map<String, dynamic>? renderer;
  String message =
      'Type every event detail exactly as it should appear. Nothing is filled in for you.';

  Iterable<Map<String, dynamic>> get pendingJobs => renderJobs.pending;

  @override
  void initState() {
    super.initState();
    account = widget.accounts.isEmpty ? null : widget.accounts.first;
    slides.add(FlyerSlideDraft('slide-${_slideSeed++}', 'hook'));
    _checkRenderer();
  }

  @override
  void dispose() {
    deckName.dispose();
    for (final FlyerSlideDraft slide in slides) {
      slide.dispose();
    }
    super.dispose();
  }

  /// Ask the backend whether the render host is answering, so the screen can
  /// say so before the operator types a whole deck.
  Future<void> _checkRenderer() async {
    try {
      final dynamic value = await widget.read('/flyers/renderer');
      if (!mounted || value is! Map) return;
      setState(() => renderer = Map<String, dynamic>.from(value));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        renderer = <String, dynamic>{
          'reachable': false,
          'message':
              'The render service did not answer, so no flyer can be rendered right now.',
        };
      });
    }
  }

  void _addSlide(String role) {
    if (slides.length >= flyerMaxSlides) return;
    setState(() {
      slides.add(FlyerSlideDraft('slide-${_slideSeed++}', role));
      reviewed = false;
    });
  }

  void _removeSlide(int index) {
    if (slides.length <= 1) return;
    setState(() {
      slides.removeAt(index).dispose();
      reviewed = false;
    });
  }

  void _move(int from, int delta) {
    final int to = from + delta;
    if (to < 0 || to >= slides.length) return;
    setState(() {
      slides.insert(to, slides.removeAt(from));
      reviewed = false;
    });
  }

  Map<String, dynamic> _payload() => <String, dynamic>{
    'deck_id': deckName.text.trim(),
    'account': account,
    'brand_profile': 'desert_events',
    'demo': demo,
    'logo_asset': brandMark,
    'on_missing_field': allowPlaceholders ? 'placeholder' : 'fail',
    'slides': <Map<String, dynamic>>[
      for (int i = 0; i < slides.length; i++)
        <String, dynamic>{
          'index': i,
          'role': slides[i].role,
          'layout': template,
          'text_layers': slides[i].textLayers(),
        },
    ],
  };

  Future<void> _render() async {
    if (busy || !reviewed) return;
    final List<String> problems = flyerDeckProblems(
      deckId: deckName.text.trim(),
      account: account,
      slides: slides,
      allowPlaceholders: allowPlaceholders,
    );
    if (problems.isNotEmpty) {
      setState(() => message = problems.join('\n'));
      return;
    }
    final Map<String, dynamic> payload = _payload();
    final String signature = payload.toString();
    setState(() {
      busy = true;
      message = 'Sending the deck to the render host…';
    });
    try {
      final dynamic result = await widget
          .write('/flyers/render', <String, dynamic>{
            ...payload,
            'idempotency_key':
                'flyer-${DateTime.now().microsecondsSinceEpoch}-$signature'
                    .hashCode
                    .toString(),
          });
      renderJobs.submitted(
        result,
        sourceId: payload['deck_id'] as String,
        account: account!,
        signature: signature,
        title: payload['deck_id'] as String,
      );
      if (!mounted) return;
      setState(() {
        reviewed = false;
        message =
            'Sent for rendering. Nothing was published, scheduled or approved.';
      });
      await _poll();
    } on Object catch (error) {
      if (mounted) setState(() => message = '$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Same polling shape as the reel editor: only states that can progress on
  /// their own are polled, and a status call that fails marks the job
  /// interrupted rather than spinning.
  Future<void> _poll() async {
    if (polling) return;
    polling = true;
    try {
      while (mounted && pendingJobs.isNotEmpty) {
        bool interrupted = false;
        for (final Map<String, dynamic> job in pendingJobs.toList()) {
          try {
            final dynamic result = await widget.read(
              '/flyers/render/${Uri.encodeComponent('${job['id']}')}',
            );
            if (!mounted) return;
            renderJobs.update('${job['id']}', result);
            if (result is Map && result['manifest'] is Map) {
              manifests['${job['id']}'] = Map<String, dynamic>.from(
                result['manifest'] as Map,
              );
            }
          } catch (_) {
            job['status'] = 'interrupted';
            job['error'] =
                'Status unavailable. Check again before rendering another version.';
            interrupted = true;
          }
        }
        if (!mounted) return;
        setState(
          () => message = pendingJobs.isNotEmpty
              ? 'Rendering ${pendingJobs.length} deck${pendingJobs.length == 1 ? '' : 's'}…'
              : 'Rendering finished. Review each result below.',
        );
        if (interrupted || pendingJobs.isEmpty) break;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    } finally {
      polling = false;
    }
  }

  String _jobSubtitle(Map<String, dynamic> job) {
    final String status = '${job['status']}';
    if (status == 'ready_for_review') {
      final Map<String, dynamic>? manifest = manifests['${job['id']}'];
      final dynamic ordered = manifest?['publish_contract'] is Map
          ? (manifest!['publish_contract'] as Map)['ordered_assets']
          : null;
      final int count = ordered is List ? ordered.length : 0;
      return count > 0
          ? 'Ready for review · $count slide${count == 1 ? '' : 's'} in order · nothing published'
          : 'Ready for review · nothing published';
    }
    if (status == 'failed' || status == 'interrupted') {
      return '${job['error'] ?? 'The render failed.'}';
    }
    return 'Preparing the slides';
  }

  @override
  Widget build(BuildContext context) {
    final bool rendererDown =
        renderer != null && renderer!['reachable'] != true;
    return Scaffold(
      appBar: AppBar(title: const Text('Make a flyer')),
      body: SafeArea(
        // The deck's settings, and the deck. On a phone they are one column in
        // the order they shipped — account, name, template, options, then the
        // slides and the render button. On an iPad the settings hold the left
        // pane while every slide in the carousel is edited on the right,
        // which is the point of a deck editor.
        child: ConPanes(
          primary: <Widget>[
            const Text(
              'One slide is a flyer. Two to ten slides are a carousel. Every result waits for review.',
              style: TextStyle(color: SandDark.onSurfaceLow),
            ),
            if (renderer != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '${renderer!['message'] ?? ''}',
                  key: const ValueKey<String>('flyer-renderer-status'),
                  style: TextStyle(
                    color: rendererDown
                        ? SandDark.warning
                        : SandDark.onSurfaceLow,
                  ),
                ),
              ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              key: const ValueKey<String>('flyer-account'),
              initialValue: account,
              decoration: const InputDecoration(labelText: 'Account'),
              items: widget.accounts
                  .map(
                    (String name) => DropdownMenuItem<String>(
                      value: name,
                      child: Text(name),
                    ),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (String? value) => setState(() {
                      account = value;
                      reviewed = false;
                    }),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('flyer-deck-name'),
              controller: deckName,
              decoration: const InputDecoration(
                labelText: 'Flyer name',
                helperText: 'Lowercase letters, numbers and hyphens',
              ),
              onChanged: (_) => setState(() => reviewed = false),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const ValueKey<String>('flyer-template'),
              initialValue: template,
              decoration: const InputDecoration(labelText: 'Template'),
              items: flyerTemplates
                  .map(
                    (Map<String, String> item) => DropdownMenuItem<String>(
                      value: item['id'],
                      child: Text(item['label']!),
                    ),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (String? value) => setState(() => template = value!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const ValueKey<String>('flyer-brand-mark'),
              initialValue: brandMark,
              decoration: const InputDecoration(labelText: 'Brand mark'),
              items: flyerBrandMarks
                  .map(
                    (String name) => DropdownMenuItem<String>(
                      value: name,
                      child: Text(name),
                    ),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (String? value) => setState(() => brandMark = value!),
            ),
            CheckboxListTile(
              key: const ValueKey<String>('flyer-demo'),
              contentPadding: EdgeInsets.zero,
              value: demo,
              title: const Text('Stamp every slide as a template demo'),
              subtitle: const Text(
                'Leave this on until the details below are a real, confirmed booking.',
              ),
              onChanged: busy
                  ? null
                  : (bool? value) => setState(() => demo = value == true),
            ),
            CheckboxListTile(
              key: const ValueKey<String>('flyer-placeholders'),
              contentPadding: EdgeInsets.zero,
              value: allowPlaceholders,
              title: const Text('Render blank slots as visible placeholders'),
              subtitle: const Text(
                'Off, a blank slot is refused by name. On, it renders as [SLOT]. Nothing is ever guessed for you.',
              ),
              onChanged: busy
                  ? null
                  : (bool? value) => setState(() {
                      allowPlaceholders = value == true;
                      reviewed = false;
                    }),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                message,
                key: const ValueKey<String>('flyer-message'),
                style: const TextStyle(color: SandDark.warning),
              ),
            ),
          ],
          secondary: <Widget>[
            for (int index = 0; index < slides.length; index++)
              _SlideCard(
                key: ValueKey<String>(slides[index].id),
                slide: slides[index],
                index: index,
                total: slides.length,
                changed: () => setState(() => reviewed = false),
                move: (int delta) => _move(index, delta),
                remove: () => _removeSlide(index),
              ),
            Row(
              children: <Widget>[
                for (final Map<String, String> role in flyerRoles)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: OutlinedButton(
                        key: ValueKey<String>('flyer-add-${role['id']}'),
                        onPressed: busy || slides.length >= flyerMaxSlides
                            ? null
                            : () => _addSlide(role['id']!),
                        child: Text('Add ${role['id']}'),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            CheckboxListTile(
              key: const ValueKey<String>('flyer-reviewed'),
              contentPadding: EdgeInsets.zero,
              value: reviewed,
              title: const Text(
                'I checked every date, venue, city and event ID against the booking.',
              ),
              subtitle: const Text('Keep every result review-only.'),
              onChanged: busy
                  ? null
                  : (bool? value) => setState(() => reviewed = value == true),
            ),
            FilledButton.icon(
              key: const ValueKey<String>('flyer-render'),
              onPressed: reviewed && !busy ? _render : null,
              icon: const Icon(CupertinoIcons.doc_richtext),
              label: const Text('Render for review'),
            ),
            for (final Map<String, dynamic> job in renderJobs.items)
              Card(
                key: ValueKey<String>('flyer-job-${job['id']}'),
                margin: const EdgeInsets.only(top: 14),
                child: ListTile(
                  title: Text('${job['title'] ?? 'Flyer'}'),
                  subtitle: Text(_jobSubtitle(job)),
                ),
              ),
            if (pendingJobs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton(
                  key: const ValueKey<String>('flyer-check-status'),
                  onPressed: polling ? null : _poll,
                  child: const Text('Check render status'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SlideCard extends StatelessWidget {
  const _SlideCard({
    super.key,
    required this.slide,
    required this.index,
    required this.total,
    required this.changed,
    required this.move,
    required this.remove,
  });

  final FlyerSlideDraft slide;
  final int index, total;
  final VoidCallback changed, remove;
  final void Function(int delta) move;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Slide ${index + 1} · ${flyerRoles.firstWhere((Map<String, String> r) => r['id'] == slide.role)['label']}',
                ),
              ),
              IconButton(
                onPressed: index == 0 ? null : () => move(-1),
                icon: const Icon(CupertinoIcons.arrow_up),
              ),
              IconButton(
                onPressed: index == total - 1 ? null : () => move(1),
                icon: const Icon(CupertinoIcons.arrow_down),
              ),
              IconButton(
                key: ValueKey<String>('flyer-remove-${slide.id}'),
                onPressed: total <= 1 ? null : remove,
                icon: const Icon(CupertinoIcons.delete),
              ),
            ],
          ),
          const Text(
            'Slide order is the posting order.',
            style: TextStyle(color: SandDark.onSurfaceLow, fontSize: 12),
          ),
          const SizedBox(height: 10),
          for (final String slot in flyerRoleSlots[slide.role]!)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                key: ValueKey<String>('flyer-${slide.id}-$slot'),
                controller: slide.fields[slot],
                decoration: InputDecoration(
                  labelText: flyerSlotLabels[slot],
                  helperText: slot == 'DATE'
                      ? 'Rendered exactly as typed. No weekday is added.'
                      : null,
                ),
                onChanged: (_) => changed(),
              ),
            ),
          for (int line = 0; line < slide.lines.length; line++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                key: ValueKey<String>('flyer-${slide.id}-BODY_LINE-$line'),
                controller: slide.lines[line],
                decoration: InputDecoration(
                  labelText: 'Line ${line + 1}',
                  helperText: line == 0
                      ? 'At least one line is required'
                      : null,
                ),
                onChanged: (_) => changed(),
              ),
            ),
        ],
      ),
    ),
  );
}

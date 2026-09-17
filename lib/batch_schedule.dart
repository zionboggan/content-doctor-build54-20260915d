// Batch scheduling: turn a pile of approved exports into a week of queued
// Trial reels in one pass.
//
// This screen composes a plan and hands it back as entries. It never talks to
// a gateway itself, and it never touches a posting path: the endpoint its
// caller uses is /reels/schedule, which writes a queued TRIAL state. Posting
// remains a separate, explicit act.
//
// Times are Phoenix wall time, like everything else in this product's
// calendar. The clock is injected so a rendered plan is stable in a test and
// on a phone in another zone.

import 'package:flutter/cupertino.dart';

import 'console_shell.dart';

typedef BatchConfirm =
    Future<void> Function(List<Map<String, dynamic>> entries);

String _text(dynamic value, [String fallback = '']) =>
    value == null ? fallback : '$value';

/// The backend accepts 1-20 entries in one call. The UI holds the same limit
/// so an operator is told before they build a plan that cannot be sent.
const int kBatchLimit = 20;

/// One reel's place in a plan.
class BatchPlanRow {
  const BatchPlanRow({
    required this.item,
    required this.when,
    required this.caption,
  });

  final Map<String, dynamic> item;

  /// Phoenix wall time.
  final DateTime when;
  final String caption;

  String get id => _text(item['id']);
  String get sha => _text(item['sha256']);
}

/// Spreads selected reels across days from a first slot.
///
/// Pure, so the plan a test asserts is the plan the screen renders.
List<BatchPlanRow> buildPlan({
  required List<Map<String, dynamic>> selected,
  required DateTime firstSlot,
  required int everyDays,
  required String template,
  required Map<String, String> overrides,
}) {
  final List<BatchPlanRow> rows = <BatchPlanRow>[];
  final int step = everyDays < 1 ? 1 : everyDays;
  for (int index = 0; index < selected.length; index++) {
    final Map<String, dynamic> item = selected[index];
    final String id = _text(item['id']);
    final String override = overrides[id] ?? '';
    final String caption = override.trim().isNotEmpty
        ? override.trim()
        : (template.trim().isNotEmpty
              ? template.trim()
              // Neither a per-reel override nor a template: the reel keeps the
              // caption it was approved with. Sending an empty caption would
              // silently strip it.
              : _text(item['caption']));
    rows.add(
      BatchPlanRow(
        item: item,
        when: firstSlot.add(Duration(days: step * index)),
        caption: caption,
      ),
    );
  }
  return rows;
}

/// Wall-clock label, Phoenix, matching the calendar's own phrasing.
String batchSlotLabel(DateTime wall) {
  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final int hour12 = wall.hour % 12 == 0 ? 12 : wall.hour % 12;
  final String minute = wall.minute.toString().padLeft(2, '0');
  final String meridiem = wall.hour < 12 ? 'AM' : 'PM';
  return '${months[wall.month - 1]} ${wall.day} · $hour12:$minute $meridiem';
}

class BatchSchedulePage extends StatefulWidget {
  const BatchSchedulePage({
    super.key,
    required this.items,
    required this.phoenixNow,
    required this.wallToUtc,
    required this.onConfirm,
    this.limit = kBatchLimit,
  });

  /// How many reels one batch may carry. Matches the backend's own cap;
  /// injectable so the guard can be exercised without building a 20-row plan.
  final int limit;

  /// Approved, schedulable exports for the current account scope.
  final List<Map<String, dynamic>> items;
  final DateTime Function() phoenixNow;
  final DateTime Function(DateTime) wallToUtc;
  final BatchConfirm onConfirm;

  @override
  State<BatchSchedulePage> createState() => _BatchSchedulePageState();
}

class _BatchSchedulePageState extends State<BatchSchedulePage> {
  final List<String> selected = <String>[];
  final Map<String, String> overrides = <String, String>{};
  final TextEditingController template = TextEditingController();
  late DateTime firstSlot;
  int everyDays = 1;
  bool sending = false;
  String? failure;

  @override
  void initState() {
    super.initState();
    final DateTime now = widget.phoenixNow();
    // Tomorrow at 9am reads as a deliberate choice; "now plus a minute" reads
    // as an accident, and the backend refuses a slot in the past anyway.
    firstSlot = DateTime(now.year, now.month, now.day + 1, 9);
  }

  @override
  void dispose() {
    template.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _selectedItems => <Map<String, dynamic>>[
    for (final String id in selected)
      ...widget.items.where((Map<String, dynamic> x) => _text(x['id']) == id),
  ];

  List<BatchPlanRow> get _plan => buildPlan(
    selected: _selectedItems,
    firstSlot: firstSlot,
    everyDays: everyDays,
    template: template.text,
    overrides: overrides,
  );

  void _toggle(String id) {
    setState(() {
      failure = null;
      if (selected.remove(id)) return;
      if (selected.length >= widget.limit) {
        failure = 'One batch holds ${widget.limit} reels. Send this one first.';
        return;
      }
      selected.add(id);
    });
  }

  Future<void> _pickFirstSlot() async {
    DateTime draft = firstSlot;
    final DateTime? chosen = await showConSheet<DateTime>(
      context,
      (BuildContext sheet) => ConSheet(
        title: 'First slot',
        children: <Widget>[
          SizedBox(
            height: 216,
            child: CupertinoDatePicker(
              initialDateTime: firstSlot,
              minimumDate: widget.phoenixNow(),
              use24hFormat: false,
              onDateTimeChanged: (DateTime value) => draft = value,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: ConButton(
              label: 'Use this time',
              kind: ConButtonKind.signalFill,
              expand: true,
              onPressed: () => Navigator.of(sheet).pop(draft),
            ),
          ),
        ],
      ),
    );
    if (chosen != null) setState(() => firstSlot = chosen);
  }

  Future<void> _editCaption(BatchPlanRow row) async {
    final TextEditingController field = TextEditingController(
      text: overrides[row.id] ?? row.caption,
    );
    final String? result = await showConSheet<String>(
      context,
      (BuildContext sheet) => ConSheet(
        title: 'Caption for ${row.id}',
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: CupertinoTextField(
              controller: field,
              autofocus: true,
              maxLines: 5,
              maxLength: 2200,
              placeholder: 'Caption for this reel',
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: ConButton(
              label: 'Use for this reel',
              kind: ConButtonKind.signalFill,
              expand: true,
              onPressed: () => Navigator.of(sheet).pop(field.text),
            ),
          ),
        ],
      ),
    );
    field.dispose();
    if (result != null) {
      setState(() => overrides[row.id] = result);
    }
  }

  Future<void> _confirm() async {
    final List<BatchPlanRow> plan = _plan;
    if (plan.isEmpty) return;
    final DateTime now = widget.phoenixNow();
    if (plan.first.when.isBefore(now)) {
      setState(() => failure = 'The first slot is in the past. Pick a new time.');
      return;
    }
    setState(() {
      sending = true;
      failure = null;
    });
    try {
      await widget.onConfirm(<Map<String, dynamic>>[
        for (final BatchPlanRow row in plan)
          <String, dynamic>{
            'id': row.item['id'],
            'sha256': row.item['sha256'],
            'account': row.item['account'],
            'caption': row.caption,
            'confirm': true,
            'scheduled_at': widget
                .wallToUtc(row.when)
                .toUtc()
                .toIso8601String(),
          },
      ]);
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } on Object catch (error) {
      if (!mounted) return;
      final String reason = '$error'
          .replaceFirst('HttpException: ', '')
          .replaceFirst('Exception: ', '')
          .trim();
      setState(() {
        sending = false;
        failure = reason.isEmpty || reason.length > 240
            ? 'The gateway did not accept that batch.'
            : reason;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<BatchPlanRow> plan = _plan;
    return CupertinoPageScaffold(
      backgroundColor: Con.ground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: Con.surface1,
        border: const Border(bottom: BorderSide(color: Con.rule)),
        middle: Text('Batch schedule', style: Ty.title.copyWith(color: Con.ink)),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text('Close', style: Ty.body.copyWith(color: Con.holdBright)),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: <Widget>[
            if (failure != null)
              ConBanner(
                headline: 'Batch not scheduled',
                detail: failure!,
                tone: Con.wait,
              ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  const _Heading('SELECT REELS'),
                  if (widget.items.isEmpty)
                    const ConEmpty(
                      title: 'Nothing approved yet',
                      body:
                          'Approve reels in Review and they become available '
                          'to schedule here.',
                    ),
                  for (final Map<String, dynamic> item in widget.items)
                    ConSheetRow(
                      label: _text(item['title'], _text(item['id'])),
                      detail: _text(item['account']),
                      selected: selected.contains(_text(item['id'])),
                      leadingBar: selected.contains(_text(item['id']))
                          ? Con.hold
                          : null,
                      onTap: sending ? null : () => _toggle(_text(item['id'])),
                    ),
                  const _Heading('WHEN'),
                  ConSheetRow(
                    label: 'First slot',
                    detail: batchSlotLabel(firstSlot),
                    onTap: sending ? null : () => unawaitedPick(_pickFirstSlot),
                  ),
                  ConSheetRow(
                    label: 'Spacing',
                    detail: everyDays == 1 ? 'One a day' : 'Every $everyDays days',
                    onTap: sending
                        ? null
                        : () => setState(
                            () => everyDays = everyDays >= 3 ? 1 : everyDays + 1,
                          ),
                  ),
                  const _Heading('SHARED CAPTION'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: CupertinoTextField(
                      controller: template,
                      maxLines: 3,
                      maxLength: 2200,
                      placeholder: 'Leave blank to keep each reel’s caption',
                      placeholderStyle: Ty.body.copyWith(color: Con.ink3),
                      style: Ty.body.copyWith(color: Con.ink),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Con.surface3,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Con.rule),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (plan.isNotEmpty) ...<Widget>[
                    const _Heading('REVIEW'),
                    for (final BatchPlanRow row in plan)
                      ConSheetRow(
                        label: batchSlotLabel(row.when),
                        detail: row.caption.isEmpty
                            ? row.id
                            : '${row.id} · ${row.caption}',
                        trailing: Text(
                          overrides.containsKey(row.id) ? 'EDITED' : 'EDIT',
                          style: Ty.caps.copyWith(
                            color: overrides.containsKey(row.id)
                                ? Con.holdBright
                                : Con.ink3,
                          ),
                        ),
                        onTap: sending ? null : () => unawaitedPick(() => _editCaption(row)),
                      ),
                  ],
                  ConProse(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Text(
                        'Scheduling queues each reel as a Trial reel at its '
                        'slot. Nothing posts now, and nothing posts without '
                        'the queue running.',
                        style: Ty.meta.copyWith(color: Con.ink3, height: 1.4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Rule(strong: true),
            Padding(
              padding: const EdgeInsets.all(16),
              child: ConButton(
                label: sending
                    ? 'Scheduling…'
                    : plan.isEmpty
                    ? 'Select reels to schedule'
                    : 'Schedule ${plan.length} ${plan.length == 1 ? 'reel' : 'reels'}',
                kind: ConButtonKind.signalFill,
                expand: true,
                height: 44,
                onPressed: sending || plan.isEmpty ? null : () => unawaitedPick(_confirm),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fire-and-forget for a tap handler, kept named so the intent is legible.
void unawaitedPick(Future<void> Function() action) {
  action();
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
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

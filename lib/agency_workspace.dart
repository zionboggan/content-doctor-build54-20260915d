// White-label agency workspace.
//
// This surface lets an agency owner put their own name, mark and colour on
// what their *client* sees -- the review link -- and place each connected
// account under an agency as a client. It deliberately does not restyle this
// app: Content Doctor's own chrome is a fixed palette, and an agency colour
// here never reaches it. The swatch below is a preview of the client's page,
// not a theme.
//
// Nothing on this surface publishes, schedules, or posts. Client decisions are
// records the operator acts on; a row here is a receipt that someone pressed
// Approve in their browser, never evidence that a reel went anywhere.

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'console_shell.dart';

typedef AgencyGet = Future<dynamic> Function(String path);
typedef AgencyPost =
    Future<dynamic> Function(String path, Map<String, dynamic> body);

String _text(dynamic value, [String fallback = '']) =>
    value == null ? fallback : '$value';

List<Map<String, dynamic>> _rows(dynamic source) {
  if (source is! List) return <Map<String, dynamic>>[];
  return source
      .whereType<Map>()
      .map((Map row) => Map<String, dynamic>.from(row))
      .toList();
}

/// A parsed `#RRGGBB`, or null. Never throws: a malformed colour from the
/// gateway must degrade to "no swatch", not to a crashed accounts tab.
Color? parseBrandColour(dynamic value) {
  final String text = _text(value).trim().toUpperCase();
  if (text.length != 7 || !text.startsWith('#')) return null;
  final int? rgb = int.tryParse(text.substring(1), radix: 16);
  return rgb == null ? null : Color(0xFF000000 | rgb);
}

/// What a client sees on their review link for one account.
class AgencyBrand {
  const AgencyBrand({
    required this.agencyId,
    required this.name,
    required this.primaryColor,
    required this.branded,
    this.logoUrl,
    this.supportEmail,
    this.clientLabel,
  });

  final String? agencyId;
  final String name;
  final String primaryColor;
  final bool branded;
  final String? logoUrl;
  final String? supportEmail;
  final String? clientLabel;

  static AgencyBrand? parse(dynamic raw) {
    if (raw is! Map) return null;
    final String name = _text(raw['name']).trim();
    if (name.isEmpty) return null;
    return AgencyBrand(
      agencyId: raw['agency_id'] == null ? null : _text(raw['agency_id']),
      name: name,
      primaryColor: _text(raw['primary_color'], '#8A8F98'),
      branded: raw['branded'] == true,
      logoUrl: raw['logo_url'] == null ? null : _text(raw['logo_url']),
      supportEmail: raw['support_email'] == null
          ? null
          : _text(raw['support_email']),
      clientLabel: raw['client_label'] == null
          ? null
          : _text(raw['client_label']),
    );
  }
}

/// One client decision recorded against an exact export.
class AgencyDecision {
  const AgencyDecision({
    required this.reelId,
    required this.decision,
    required this.subject,
    required this.note,
    required this.appliesToCurrentExport,
  });

  final String reelId;
  final String decision;
  final String subject;
  final String note;
  final bool appliesToCurrentExport;

  bool get approved => decision == 'approved';

  static AgencyDecision parse(Map<String, dynamic> row) => AgencyDecision(
    reelId: _text(row['reel_id']),
    decision: _text(row['decision']),
    subject: _text(row['subject']),
    note: _text(row['note']),
    // Absent means the gateway did not say. Treat unknown as stale rather
    // than implying an approval still covers the file on disk.
    appliesToCurrentExport: row['applies_to_current_export'] == true,
  );
}

/// The agency group on the Accounts tab.
class AgencyWorkspaceCard extends StatefulWidget {
  const AgencyWorkspaceCard({
    super.key,
    required this.account,
    required this.getJson,
    required this.postJson,
  });

  final String account;
  final AgencyGet getJson;
  final AgencyPost postJson;

  @override
  State<AgencyWorkspaceCard> createState() => _AgencyWorkspaceCardState();
}

class _AgencyWorkspaceCardState extends State<AgencyWorkspaceCard> {
  List<Map<String, dynamic>> agencies = <Map<String, dynamic>>[];
  AgencyBrand? brand;
  List<AgencyDecision> decisions = <AgencyDecision>[];
  String? failure;
  bool loading = false;
  bool saving = false;

  /// True when the gateway does not answer for agency profiles at all. White
  /// label is additive: a gateway that predates it, or one that is simply
  /// down, must leave the Accounts tab exactly as it was rather than put an
  /// error where an operator expects their connection settings. The tab's own
  /// "No connection" banner already covers a real outage.
  bool unavailable = false;
  int request = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(AgencyWorkspaceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account != widget.account) {
      brand = null;
      decisions = <AgencyDecision>[];
      unawaited(_load());
    }
  }

  bool get _scoped => widget.account.trim().isNotEmpty;

  Future<void> _load() async {
    final int current = ++request;
    setState(() {
      loading = true;
      failure = null;
    });
    try {
      final dynamic profiles = await widget.getJson('/reels/agency/profiles');
      // An agency surface exists only if the gateway actually returns the
      // list. A gateway that answers every unknown path with an empty body
      // has no white label, and must not be shown an empty one.
      if (profiles is! Map || profiles['agencies'] is! List) {
        if (!mounted || current != request) return;
        setState(() {
          loading = false;
          unavailable = true;
        });
        return;
      }
      AgencyBrand? loaded;
      List<AgencyDecision> loadedDecisions = <AgencyDecision>[];
      if (_scoped) {
        final String query = Uri.encodeQueryComponent(widget.account);
        loaded = AgencyBrand.parse(
          await widget.getJson('/reels/agency/brand?account=$query'),
        );
        loadedDecisions = await _loadDecisions();
      }
      if (!mounted || current != request) return;
      setState(() {
        agencies = _rows(profiles['agencies']);
        brand = loaded;
        decisions = loadedDecisions;
        loading = false;
        unavailable = false;
      });
    } on Object {
      if (!mounted || current != request) return;
      setState(() {
        loading = false;
        unavailable = true;
      });
    }
  }

  /// Decisions are a nice-to-have on this card: a workspace with no review
  /// links yet must still render its agency profile, so this never fails the
  /// whole load.
  Future<List<AgencyDecision>> _loadDecisions() async {
    try {
      final dynamic result = await widget.postJson(
        '/reels/agency/approval-dispatch',
        <String, dynamic>{
          'action': 'decisions',
          'data': <String, dynamic>{'account': widget.account},
        },
      );
      return _rows(result is Map ? result['decisions'] : null)
          .map(AgencyDecision.parse)
          .toList();
    } on Object {
      return <AgencyDecision>[];
    }
  }

  String _reason(Object error) {
    final String text = '$error'.replaceFirst('HttpException: ', '').trim();
    if (text.isEmpty) return 'The gateway did not answer.';
    return text.length > 240 ? 'The gateway rejected that request.' : text;
  }

  Future<void> _save(String path, Map<String, dynamic> body) async {
    setState(() {
      saving = true;
      failure = null;
    });
    try {
      await widget.postJson(path, body);
      if (!mounted) return;
      setState(() => saving = false);
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        saving = false;
        failure = _reason(error);
      });
    }
  }

  // -------------------------------------------------------------------------
  // Sheets
  // -------------------------------------------------------------------------

  Future<void> _editProfile({Map<String, dynamic>? existing}) async {
    final TextEditingController name = TextEditingController(
      text: _text(existing?['name']),
    );
    final TextEditingController colour = TextEditingController(
      text: _text(existing?['primary_color'], '#E8202E'),
    );
    final TextEditingController email = TextEditingController(
      text: _text(existing?['support_email']),
    );
    final ValueNotifier<String?> problem = ValueNotifier<String?>(null);
    final Map<String, dynamic>? result =
        await showConSheet<Map<String, dynamic>>(
          context,
          (BuildContext sheet) => ConSheet(
            title: existing == null ? 'New agency' : 'Edit agency',
            children: <Widget>[
              _field(
                controller: name,
                label: 'AGENCY NAME',
                placeholder: 'Apex Social',
                maxLength: 60,
                autofocus: true,
              ),
              _field(
                controller: colour,
                label: 'CLIENT PAGE COLOUR',
                placeholder: '#RRGGBB',
                maxLength: 7,
                formatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]')),
                ],
              ),
              _field(
                controller: email,
                label: 'SUPPORT EMAIL (OPTIONAL)',
                placeholder: 'hello@apexsocial.co',
                maxLength: 200,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'This is what your client sees on their review link. It does '
                  'not change how this app looks.',
                  style: Ty.meta.copyWith(color: Con.ink3, height: 1.4),
                ),
              ),
              ValueListenableBuilder<String?>(
                valueListenable: problem,
                builder: (BuildContext context, String? message, _) =>
                    message == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          message,
                          style: Ty.meta.copyWith(color: Con.failBright),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: ConButton(
                  label: existing == null ? 'Create agency' : 'Save agency',
                  kind: ConButtonKind.signalFill,
                  expand: true,
                  onPressed: () {
                    final String trimmedName = name.text.trim();
                    if (trimmedName.isEmpty) {
                      problem.value = 'Give the agency a name.';
                      return;
                    }
                    if (parseBrandColour(colour.text) == null) {
                      problem.value =
                          'The colour must be a six-digit hex value, like #E8202E.';
                      return;
                    }
                    Navigator.of(sheet).pop(<String, dynamic>{
                      if (existing != null) 'agency_id': existing['agency_id'],
                      'name': trimmedName,
                      'primary_color': colour.text.trim(),
                      'support_email': email.text.trim(),
                    });
                  },
                ),
              ),
            ],
          ),
        );
    name.dispose();
    colour.dispose();
    email.dispose();
    problem.dispose();
    if (result != null) await _save('/reels/agency/profile', result);
  }

  Future<void> _assign() async {
    if (!_scoped) return;
    final TextEditingController label = TextEditingController(
      text: _text(brand?.clientLabel),
    );
    final Map<String, dynamic>? result =
        await showConSheet<Map<String, dynamic>>(
          context,
          (BuildContext sheet) => ConSheet(
            title: 'Client for ${widget.account}',
            children: <Widget>[
              _field(
                controller: label,
                label: 'CLIENT NAME ON THE REVIEW LINK',
                placeholder: widget.account,
                maxLength: 60,
                autofocus: true,
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Caps('AGENCY'),
              ),
              for (final Map<String, dynamic> agency in agencies)
                ConSheetRow(
                  label: _text(agency['name']),
                  detail: _text(agency['primary_color']),
                  selected: brand?.agencyId == _text(agency['agency_id']),
                  leadingBar: parseBrandColour(agency['primary_color']),
                  onTap: () => Navigator.of(sheet).pop(<String, dynamic>{
                    'account': widget.account,
                    'agency_id': agency['agency_id'],
                    'client_label': label.text.trim(),
                  }),
                ),
              if (brand?.branded == true)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: ConButton(
                    label: 'Remove from agency',
                    kind: ConButtonKind.redOutline,
                    expand: true,
                    onPressed: () => Navigator.of(sheet).pop(<String, dynamic>{
                      'account': widget.account,
                      'agency_id': null,
                    }),
                  ),
                ),
            ],
          ),
        );
    label.dispose();
    if (result != null) await _save('/reels/agency/assign', result);
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String placeholder,
    required int maxLength,
    bool autofocus = false,
    List<TextInputFormatter>? formatters,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Caps(label),
        const SizedBox(height: 6),
        CupertinoTextField(
          controller: controller,
          autofocus: autofocus,
          maxLength: maxLength,
          inputFormatters: formatters,
          placeholder: placeholder,
          placeholderStyle: Ty.body.copyWith(color: Con.ink3),
          style: Ty.body.copyWith(color: Con.ink),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Con.surface3,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Con.rule),
          ),
        ),
      ],
    ),
  );

  // -------------------------------------------------------------------------
  // Render
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AgencyBrand? current = brand;
    // Nothing at all, not an empty labelled section, when the gateway has no
    // agency surface to show.
    if (unavailable) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _AgencyGroupLabel(),
        if (failure != null)
          ConBanner(
            headline: 'That agency change did not save',
            detail: failure!,
            tone: Con.wait,
          ),
        if (loading && current == null && agencies.isEmpty)
          const ConSkeletonRow()
        else if (agencies.isEmpty)
          ConEmpty(
            title: 'No agency yet',
            body:
                'Create an agency profile to put your own name and mark on the '
                'review links your clients open.',
            actions: <Widget>[
              ConButton(
                label: 'Create agency',
                kind: ConButtonKind.signalFill,
                onPressed: saving ? null : () => unawaited(_editProfile()),
              ),
            ],
          )
        else ...<Widget>[
          for (final Map<String, dynamic> agency in agencies)
            DoctorCard(
              child: _AgencyRow(
                agency: agency,
                isCurrentAccountAgency:
                    current?.agencyId == _text(agency['agency_id']),
                onEdit: saving
                    ? null
                    : () => unawaited(_editProfile(existing: agency)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: <Widget>[
                ConButton(
                  label: 'New agency',
                  onPressed: saving ? null : () => unawaited(_editProfile()),
                ),
                const SizedBox(width: 8),
                if (_scoped)
                  ConButton(
                    label: current?.branded == true
                        ? 'Change client'
                        : 'Assign client',
                    kind: ConButtonKind.signalOutline,
                    onPressed: saving ? null : () => unawaited(_assign()),
                  ),
              ],
            ),
          ),
        ],
        if (_scoped) _clientLine(current),
        if (decisions.isNotEmpty) ...<Widget>[
          const Rule(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Caps('CLIENT DECISIONS'),
          ),
          for (final AgencyDecision decision in decisions.take(8))
            _DecisionRow(decision: decision),
          ConProse(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                'A client decision is a record. Nothing posts or schedules '
                'until you act on it here.',
                style: Ty.meta.copyWith(color: Con.ink3, height: 1.4),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _clientLine(AgencyBrand? current) => ConProse(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Text(
        current == null || !current.branded
            ? '${widget.account} is not assigned to an agency. Its review links '
                  'stay unbranded.'
            : '${widget.account} appears to clients as '
                  '${current.clientLabel?.isNotEmpty == true ? current.clientLabel : widget.account}, '
                  'under ${current.name}.',
        style: Ty.meta.copyWith(color: Con.ink2, height: 1.4),
      ),
    ),
  );
}

/// Matches the Accounts tab's own group headings. Kept here rather than in the
/// shell so the whole section, heading included, can be absent.
class _AgencyGroupLabel extends StatelessWidget {
  const _AgencyGroupLabel();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Container(
        height: 32,
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: const Caps('AGENCY'),
      ),
      const Rule(),
    ],
  );
}

class _AgencyRow extends StatelessWidget {
  const _AgencyRow({
    required this.agency,
    required this.isCurrentAccountAgency,
    required this.onEdit,
  });

  final Map<String, dynamic> agency;
  final bool isCurrentAccountAgency;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final Color? swatch = parseBrandColour(agency['primary_color']);
    final int clients = _rows(agency['accounts']).length;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The client's colour, shown as a sample only. It is never applied
          // to this app's own surfaces.
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: swatch ?? Con.surface3,
              borderRadius: BorderRadius.circular(SandRadius.r1),
              border: Border.all(color: Con.rule),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _text(agency['name']),
                  style: Ty.title.copyWith(color: Con.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  clients == 1 ? '1 client' : '$clients clients',
                  style: Ty.meta.copyWith(color: Con.ink3),
                ),
                if (isCurrentAccountAgency) ...<Widget>[
                  const SizedBox(height: 6),
                  const Caps('THIS ACCOUNT'),
                ],
              ],
            ),
          ),
          ConButton(label: 'Edit', onPressed: onEdit, height: 32),
        ],
      ),
    );
  }
}

class _DecisionRow extends StatelessWidget {
  const _DecisionRow({required this.decision});

  final AgencyDecision decision;

  @override
  Widget build(BuildContext context) => ConSheetRow(
    label: decision.reelId,
    detail: decision.note.isEmpty
        ? (decision.approved ? 'Approved' : 'Changes requested')
        : decision.note,
    // An approval against a re-rendered export is not an approval of the file
    // that exists now, and must not read like one.
    leadingBar: !decision.appliesToCurrentExport
        ? Con.ink3
        : (decision.approved ? Con.hold : Con.wait),
    trailing: Text(
      decision.appliesToCurrentExport
          ? (decision.approved ? 'APPROVED' : 'CHANGES')
          : 'RE-RENDERED',
      style: Ty.caps.copyWith(
        color: !decision.appliesToCurrentExport
            ? Con.ink3
            : (decision.approved ? Con.holdBright : Con.wait),
      ),
    ),
  );
}

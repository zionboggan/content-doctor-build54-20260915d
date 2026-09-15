// Native Inbox and Automations surfaces.
//
// These panels intentionally render only the account-scoped, review-first DM
// records the coordinator exposes. They do not infer a reply window, create an
// enabled rule, or imply that a draft was sent: the provider path currently
// permits inbound review and draft creation only.

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_motion.dart';
import 'console_shell.dart';

typedef InboxGet = Future<dynamic> Function(String path);
typedef InboxPost =
    Future<dynamic> Function(String path, Map<String, dynamic> body);

String _accountQuery(String account) =>
    '?account=${Uri.encodeQueryComponent(account)}';

String _text(dynamic value, [String fallback = '']) =>
    value == null ? fallback : '$value';

List<Map<String, dynamic>> _rows(dynamic source) {
  if (source is! List) return <Map<String, dynamic>>[];
  return source
      .whereType<Map>()
      .map((Map row) => Map<String, dynamic>.from(row))
      .toList();
}

/// Account-scoped local Instagram inbox. Tapping a row opens the summary
/// which the coordinator has actually received; message transcripts are not
/// currently exposed by its API.
class InboxPanel extends StatefulWidget {
  const InboxPanel({
    super.key,
    required this.account,
    required this.getJson,
    required this.postJson,
    this.onAutomations,
  });

  final String account;
  final InboxGet getJson;
  final InboxPost postJson;
  final VoidCallback? onAutomations;

  @override
  State<InboxPanel> createState() => _InboxPanelState();
}

class _InboxPanelState extends State<InboxPanel> {
  Map<String, dynamic>? status;
  List<Map<String, dynamic>> threads = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> drafts = <Map<String, dynamic>>[];
  Map<String, dynamic>? selected;
  String? failure;
  bool loading = false;
  bool saving = false;
  int request = 0;
  final TextEditingController reply = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(InboxPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account != widget.account) {
      request++;
      status = null;
      threads = <Map<String, dynamic>>[];
      drafts = <Map<String, dynamic>>[];
      selected = null;
      reply.clear();
      _load();
    }
  }

  @override
  void dispose() {
    reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final int current = ++request;
    if (widget.account.trim().isEmpty) {
      setState(() {
        loading = false;
        failure = 'Choose an account to open its inbox.';
      });
      return;
    }
    setState(() {
      loading = true;
      failure = null;
    });
    try {
      final List<dynamic> result = await Future.wait<dynamic>(<Future<dynamic>>[
        widget.getJson('/reels/dms/status${_accountQuery(widget.account)}'),
        widget.getJson(
          '/reels/dms/threads${_accountQuery(widget.account)}&limit=50',
        ),
        widget.getJson('/reels/dms/drafts${_accountQuery(widget.account)}'),
      ]);
      if (!mounted || current != request) return;
      final Map<String, dynamic>? existing = selected;
      final List<Map<String, dynamic>> nextThreads = result[1] is Map
          ? _rows((result[1] as Map)['threads'])
          : <Map<String, dynamic>>[];
      setState(() {
        status = result[0] is Map
            ? Map<String, dynamic>.from(result[0] as Map)
            : null;
        threads = nextThreads;
        drafts = result[2] is Map
            ? _rows((result[2] as Map)['drafts'])
            : <Map<String, dynamic>>[];
        if (existing != null) {
          selected = nextThreads.cast<Map<String, dynamic>?>().firstWhere(
            (Map<String, dynamic>? row) => row?['id'] == existing['id'],
            orElse: () => null,
          );
        }
      });
    } catch (error) {
      if (!mounted || current != request) return;
      setState(() => failure = 'Couldn\'t refresh this inbox. Try again.');
    } finally {
      if (mounted && current == request) setState(() => loading = false);
    }
  }

  Future<void> _useSuggestion() async {
    if (selected == null || widget.account.trim().isEmpty) return;
    final String account = widget.account;
    final int scopeRequest = request;
    try {
      final dynamic body = await widget.getJson(
        '/reels/dms/suggestions${_accountQuery(account)}&intent=follow_up',
      );
      final List<dynamic> choices = body is Map && body['suggestions'] is List
          ? body['suggestions'] as List<dynamic>
          : <dynamic>[];
      if (!mounted ||
          account != widget.account ||
          scopeRequest != request ||
          choices.isEmpty) {
        return;
      }
      setState(() => reply.text = _text(choices.first));
    } catch (error) {
      if (mounted && account == widget.account && scopeRequest == request) {
        setState(() => failure = 'Couldn\'t load a suggestion. Try again.');
      }
    }
  }

  Future<void> _saveDraft() async {
    final Map<String, dynamic>? thread = selected;
    final String text = reply.text.trim();
    if (thread == null || text.isEmpty || saving) return;
    final String account = widget.account;
    final int scopeRequest = request;
    setState(() {
      saving = true;
      failure = null;
    });
    try {
      await widget.postJson('/reels/dms/drafts', <String, dynamic>{
        'account': account,
        'conversation_id': _text(thread['id']),
        'text': text,
        'source': 'manual',
      });
      if (!mounted || account != widget.account || scopeRequest != request) {
        return;
      }
      reply.clear();
      // Cleared before the reload, not after. _load() increments `request`,
      // so the finally guard below — scopeRequest == request — is false by
      // the time it runs and `saving` never went back to false: a draft that
      // saved successfully left the Save button disabled forever with no
      // error to explain it.
      setState(() => saving = false);
      await _load();
    } catch (error) {
      if (mounted && account == widget.account && scopeRequest == request) {
        setState(
          () => failure = 'Couldn\'t save that draft. Nothing was sent.',
        );
      }
    } finally {
      if (mounted && account == widget.account && scopeRequest == request) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> capability = status?['capability'] is Map
        ? Map<String, dynamic>.from(status!['capability'] as Map)
        : <String, dynamic>{};
    final int unread = (status?['local_unread_count'] as num?)?.toInt() ?? 0;
    return ListView(
      key: const PageStorageKey<String>('inbox-panel'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: <Widget>[
        CdEnter(
          child: _PanelHeader(
            title: 'Inbox',
            account: widget.account,
            action: ConIconButton(
              icon: CupertinoIcons.refresh,
              semanticLabel: 'Refresh inbox',
              onPressed: loading ? null : _load,
            ),
          ),
        ),
        const SizedBox(height: 12),
        CdEnter(
          delay: CdMotion.stagger,
          child: _StatusCard(
            title: '${status?['local_conversations'] ?? 0} local conversations',
            detail: capability.isEmpty
                ? 'Loading account capability…'
                : _text(capability['reason']),
            badge: unread == 0 ? 'REVIEW ONLY' : '$unread UNREAD',
            tone: unread == 0 ? Con.hold : Con.signal,
          ),
        ),
        if (failure != null) ...<Widget>[
          const SizedBox(height: 10),
          _Notice(text: failure!, tone: Con.fail),
        ],
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            const Expanded(child: Caps('Inbound threads')),
            Text(
              '${threads.length} shown',
              style: Ty.meta.copyWith(color: Con.ink3),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (loading && status == null)
          const _LoadingRows()
        else if (threads.isEmpty)
          const _Notice(
            text:
                'No signed inbound conversations are stored for this account yet.',
            tone: Con.ink3,
          )
        else
          for (int index = 0; index < threads.length; index++) ...<Widget>[
            CdEnter(
              key: ValueKey<String>('inbox-enter:${threads[index]['id']}'),
              delay: CdMotion.stagger * (index + 2),
              child: _ThreadCard(
                row: threads[index],
                selected: selected?['id'] == threads[index]['id'],
                onTap: () => setState(() {
                  selected = threads[index];
                  reply.clear();
                }),
              ),
            ),
            const SizedBox(height: 8),
          ],
        if (selected != null) ...<Widget>[
          const SizedBox(height: 12),
          _ThreadDetail(
            thread: selected!,
            controller: reply,
            saving: saving,
            onSuggestion: _useSuggestion,
            onSave: _saveDraft,
          ),
        ],
        const SizedBox(height: 20),
        _DraftSummary(drafts: drafts),
        if (widget.onAutomations != null) ...<Widget>[
          const SizedBox(height: 10),
          ConButton(
            label: 'Review automations',
            leading: CupertinoIcons.bolt,
            onPressed: widget.onAutomations,
            expand: true,
          ),
        ],
      ],
    );
  }
}

/// The automation surface represents the one durable workflow available in
/// the coordinator: a human-created review plan. No toggle is rendered because
/// no route exists to enable a rule or set business hours.
class AutomationsPanel extends StatefulWidget {
  const AutomationsPanel({
    super.key,
    required this.account,
    required this.getJson,
    required this.postJson,
  });
  final String account;
  final InboxGet getJson;
  final InboxPost postJson;

  @override
  State<AutomationsPanel> createState() => _AutomationsPanelState();
}

class _AutomationsPanelState extends State<AutomationsPanel> {
  List<Map<String, dynamic>> threads = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> drafts = <Map<String, dynamic>>[];
  String? selectedConversation;
  String? failure;
  bool loading = false;
  bool saving = false;
  int request = 0;
  final TextEditingController commentId = TextEditingController();
  final TextEditingController keyword = TextEditingController();
  final TextEditingController publicReply = TextEditingController();
  final TextEditingController dmText = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AutomationsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account != widget.account) {
      request++;
      threads = <Map<String, dynamic>>[];
      drafts = <Map<String, dynamic>>[];
      selectedConversation = null;
      _load();
    }
  }

  @override
  void dispose() {
    commentId.dispose();
    keyword.dispose();
    publicReply.dispose();
    dmText.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final int current = ++request;
    if (widget.account.trim().isEmpty) {
      setState(() {
        loading = false;
        failure = 'Choose an account to review its workflows.';
      });
      return;
    }
    setState(() {
      loading = true;
      failure = null;
    });
    try {
      final List<dynamic> result = await Future.wait<dynamic>(<Future<dynamic>>[
        widget.getJson(
          '/reels/dms/threads${_accountQuery(widget.account)}&limit=100',
        ),
        widget.getJson('/reels/dms/drafts${_accountQuery(widget.account)}'),
      ]);
      if (!mounted || current != request) return;
      final List<Map<String, dynamic>> next = result[0] is Map
          ? _rows((result[0] as Map)['threads'])
          : <Map<String, dynamic>>[];
      setState(() {
        threads = next;
        drafts = result[1] is Map
            ? _rows((result[1] as Map)['drafts'])
            : <Map<String, dynamic>>[];
        if (selectedConversation != null &&
            !next.any((row) => row['id'] == selectedConversation)) {
          selectedConversation = null;
        }
      });
    } catch (error) {
      if (mounted && current == request) {
        setState(() => failure = 'Couldn\'t refresh these drafts. Try again.');
      }
    } finally {
      if (mounted && current == request) setState(() => loading = false);
    }
  }

  Future<void> _createPlan() async {
    if (saving || selectedConversation == null) return;
    final String account = widget.account;
    final int scopeRequest = request;
    setState(() {
      saving = true;
      failure = null;
    });
    try {
      await widget.postJson('/reels/dms/keyword-plan', <String, dynamic>{
        'account': account,
        'conversation_id': selectedConversation,
        'comment_id': commentId.text.trim(),
        'keyword': keyword.text.trim(),
        'public_reply': publicReply.text.trim(),
        'dm_text': dmText.text.trim(),
      });
      if (!mounted || account != widget.account || scopeRequest != request) {
        return;
      }
      commentId.clear();
      keyword.clear();
      publicReply.clear();
      dmText.clear();
      // See _saveDraft: cleared before the reload, because _load() moves the
      // request counter the finally guard compares against.
      setState(() => saving = false);
      await _load();
    } catch (error) {
      if (mounted && account == widget.account && scopeRequest == request) {
        setState(
          () =>
              failure = 'Couldn\'t create that review plan. Nothing was sent.',
        );
      }
    } finally {
      if (mounted && account == widget.account && scopeRequest == request) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    key: const PageStorageKey<String>('automations-panel'),
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
    children: <Widget>[
      CdEnter(
        child: _PanelHeader(
          title: 'Automations',
          account: widget.account,
          action: ConIconButton(
            icon: CupertinoIcons.refresh,
            semanticLabel: 'Refresh workflows',
            onPressed: loading ? null : _load,
          ),
        ),
      ),
      const SizedBox(height: 12),
      CdEnter(
        delay: CdMotion.stagger,
        child: const _Notice(
          text:
              'Automatic replies are not active. You can prepare review drafts here; nothing sends from this app.',
          tone: Con.wait,
        ),
      ),
      if (failure != null) ...<Widget>[
        const SizedBox(height: 10),
        _Notice(text: failure!, tone: Con.fail),
      ],
      const SizedBox(height: 20),
      const Caps('Keyword comment review plan'),
      const SizedBox(height: 8),
      _PlanForm(
        threads: threads,
        selectedConversation: selectedConversation,
        commentId: commentId,
        keyword: keyword,
        publicReply: publicReply,
        dmText: dmText,
        saving: saving,
        onConversation: (String? id) =>
            setState(() => selectedConversation = id),
        onCreate: _createPlan,
      ),
      const SizedBox(height: 20),
      _DraftSummary(drafts: drafts),
    ],
  );
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.title,
    required this.account,
    required this.action,
  });
  final String title, account;
  final Widget action;
  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Ty.title.copyWith(color: Con.ink, fontSize: 21)),
            const SizedBox(height: 3),
            Text(
              account.isEmpty ? 'No account selected' : account,
              style: Ty.meta.copyWith(color: Con.ink2),
            ),
          ],
        ),
      ),
      action,
    ],
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.detail,
    required this.badge,
    required this.tone,
  });
  final String title, detail, badge;
  final Color tone;
  @override
  Widget build(BuildContext context) => _Surface(
    stripe: tone,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(title, style: Ty.title.copyWith(color: Con.ink)),
            ),
            _Pill(label: badge, tone: tone),
          ],
        ),
        const SizedBox(height: 6),
        Text(detail, style: Ty.meta.copyWith(color: Con.ink2, height: 1.35)),
      ],
    ),
  );
}

class _ThreadCard extends StatelessWidget {
  const _ThreadCard({
    required this.row,
    required this.selected,
    required this.onTap,
  });
  final Map<String, dynamic> row;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final int unread = (row['unread_count'] as num?)?.toInt() ?? 0;
    final String name = _text(row['participant_label']).isEmpty
        ? 'Inbound conversation'
        : _text(row['participant_label']);
    return Semantics(
      button: true,
      label: '$name${unread > 0 ? ', $unread unread' : ''}',
      child: CdPressFeedback(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: CdMotion.duration(context, CdMotion.std),
            curve: CdMotion.out,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? Con.surface3 : Con.surface2,
              border: Border.all(
                color: selected ? Con.signal : Con.rule,
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Con.surface3,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.chat_bubble_2,
                    color: unread > 0 ? Con.signalBright : Con.ink3,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Ty.label.copyWith(color: Con.ink),
                            ),
                          ),
                          if (unread > 0)
                            _Pill(label: '$unread NEW', tone: Con.signal),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _text(row['preview'], 'No preview recorded'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Ty.meta.copyWith(color: Con.ink2, height: 1.3),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _when(_text(row['last_message_at'])),
                        style: Ty.meta.copyWith(color: Con.ink3),
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
  }
}

class _ThreadDetail extends StatelessWidget {
  const _ThreadDetail({
    required this.thread,
    required this.controller,
    required this.saving,
    required this.onSuggestion,
    required this.onSave,
  });
  final Map<String, dynamic> thread;
  final TextEditingController controller;
  final bool saving;
  final VoidCallback onSuggestion, onSave;
  @override
  Widget build(BuildContext context) => _Surface(
    stripe: Con.hold,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Conversation review', style: Ty.title.copyWith(color: Con.ink)),
        const SizedBox(height: 4),
        Text(
          'The gateway exposes its latest inbound preview, not a message transcript. Any reply below becomes a draft only.',
          style: Ty.meta.copyWith(color: Con.ink2, height: 1.35),
        ),
        const SizedBox(height: 10),
        Text(
          _text(thread['preview'], 'No preview recorded'),
          style: Ty.body.copyWith(color: Con.ink),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          maxLength: 1000,
          maxLines: 4,
          style: Ty.body.copyWith(color: Con.ink),
          decoration: InputDecoration(
            hintText: 'Write a reply for review',
            hintStyle: Ty.body.copyWith(color: Con.ink3),
            counterStyle: Ty.meta.copyWith(color: Con.ink3),
            filled: true,
            fillColor: Con.surface1,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Con.rule),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Expanded(
              child: ConButton(
                label: 'Use follow-up',
                onPressed: onSuggestion,
                kind: ConButtonKind.ironOutline,
                expand: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ConButton(
                label: saving ? 'Saving…' : 'Save draft',
                // Validation remains in the mutation handler. A controller
                // edit does not rebuild this stateless detail each keystroke.
                onPressed: saving ? null : onSave,
                kind: ConButtonKind.signalFill,
                expand: true,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _PlanForm extends StatelessWidget {
  const _PlanForm({
    required this.threads,
    required this.selectedConversation,
    required this.commentId,
    required this.keyword,
    required this.publicReply,
    required this.dmText,
    required this.saving,
    required this.onConversation,
    required this.onCreate,
  });
  final List<Map<String, dynamic>> threads;
  final String? selectedConversation;
  final TextEditingController commentId, keyword, publicReply, dmText;
  final bool saving;
  final ValueChanged<String?> onConversation;
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => _Surface(
    stripe: Con.hold,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Create a review-only plan',
          style: Ty.title.copyWith(color: Con.ink),
        ),
        const SizedBox(height: 4),
        Text(
          'A signed inbound conversation is required. This creates a public-reply draft plus a DM draft; it sends neither.',
          style: Ty.meta.copyWith(color: Con.ink2, height: 1.35),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: selectedConversation,
          isExpanded: true,
          dropdownColor: Con.surface2,
          decoration: _fieldDecoration('Verified inbound conversation'),
          items: threads
              .map(
                (Map<String, dynamic> row) => DropdownMenuItem<String>(
                  value: _text(row['id']),
                  child: Text(
                    _text(row['participant_label'], _text(row['id'])),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: saving || threads.isEmpty ? null : onConversation,
        ),
        const SizedBox(height: 8),
        _field(commentId, 'Provider comment ID'),
        const SizedBox(height: 8),
        _field(keyword, 'Keyword (for review)'),
        const SizedBox(height: 8),
        _field(publicReply, 'Public reply draft', lines: 2),
        const SizedBox(height: 8),
        _field(dmText, 'DM draft', lines: 3),
        const SizedBox(height: 8),
        ConButton(
          label: saving ? 'Creating…' : 'Create review plan',
          onPressed: saving || selectedConversation == null ? null : onCreate,
          kind: ConButtonKind.signalFill,
          expand: true,
        ),
      ],
    ),
  );
}

Widget _field(TextEditingController controller, String hint, {int lines = 1}) =>
    TextField(
      controller: controller,
      maxLines: lines,
      maxLength: lines == 1 ? 256 : 1000,
      style: Ty.body.copyWith(color: Con.ink),
      decoration: _fieldDecoration(
        hint,
      ).copyWith(counterStyle: Ty.meta.copyWith(color: Con.ink3)),
    );

InputDecoration _fieldDecoration(String hint) => InputDecoration(
  labelText: hint,
  labelStyle: Ty.meta.copyWith(color: Con.ink2),
  filled: true,
  fillColor: Con.surface1,
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: Con.rule),
  ),
);

class _DraftSummary extends StatelessWidget {
  const _DraftSummary({required this.drafts});
  final List<Map<String, dynamic>> drafts;
  @override
  Widget build(BuildContext context) => _Surface(
    stripe: drafts.isEmpty ? Con.ruleStrong : Con.wait,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Review drafts',
                style: Ty.title.copyWith(color: Con.ink),
              ),
            ),
            _Pill(
              label: '${drafts.length} DRAFT${drafts.length == 1 ? '' : 'S'}',
              tone: Con.wait,
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          drafts.isEmpty
              ? 'No review-only DM drafts for this account.'
              : 'Drafts are stored locally for human review. Outbound messaging remains disabled.',
          style: Ty.meta.copyWith(color: Con.ink2, height: 1.35),
        ),
        for (final Map<String, dynamic> row in drafts.take(3)) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _text(row['text']),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Ty.meta.copyWith(color: Con.ink),
          ),
        ],
      ],
    ),
  );
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.stripe});
  final Widget child;
  final Color? stripe;
  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(12);
    // A rounded BoxBorder cannot safely mix a 3px left edge with 1px other
    // edges. The status bar is a clipped layer over a uniform card outline.
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        decoration: BoxDecoration(
          color: Con.surface2,
          border: Border.all(color: Con.rule),
          borderRadius: radius,
        ),
        child: Stack(
          children: <Widget>[
            if (stripe != null)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: ColoredBox(color: stripe!),
              ),
            Padding(padding: const EdgeInsets.all(12), child: child),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.tone});
  final String text;
  final Color tone;
  @override
  Widget build(BuildContext context) => _Surface(
    stripe: tone,
    child: Text(text, style: Ty.meta.copyWith(color: Con.ink2, height: 1.4)),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.tone});
  final String label;
  final Color tone;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(label, style: Ty.caps.copyWith(color: tone)),
  );
}

class _LoadingRows extends StatelessWidget {
  const _LoadingRows();
  @override
  Widget build(BuildContext context) => const Column(
    children: <Widget>[
      ConSkeletonRow(),
      SizedBox(height: 8),
      ConSkeletonRow(),
      SizedBox(height: 8),
      ConSkeletonRow(),
    ],
  );
}

String _when(String value) {
  final DateTime? stamp = DateTime.tryParse(value)?.toLocal();
  if (stamp == null) return value.isEmpty ? 'Time not recorded' : value;
  return '${stamp.year}-${stamp.month.toString().padLeft(2, '0')}-${stamp.day.toString().padLeft(2, '0')} ${stamp.hour.toString().padLeft(2, '0')}:${stamp.minute.toString().padLeft(2, '0')}';
}

// Team: conversation with the durable Bot workforce.
//
// There is no chat store behind this screen. A message is a job in the agent
// queue on CT321 and a reply is a receipt on that job, so what the panel shows
// is the state the queue actually holds. A message no Bot has claimed is
// labelled as unclaimed, because queued is not delivered.
//
// The panel owns no credential and no host. It is handed two functions by the
// console shell, so the gateway auth, the media cookie and the account scope
// stay in exactly one place.

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'app_motion.dart';
import 'app_theme.dart';
import 'console_shell.dart';
import 'crew_motion.dart';

typedef TeamGet = Future<dynamic> Function(String path);
typedef TeamPost =
    Future<dynamic> Function(String path, Map<String, dynamic> body);

/// State bar colour for one delivery state. Same meaning as everywhere else:
/// amber waits, iron blue is in hand, sandstorm wants a person, red failed.
Color teamTone(String delivery) => switch (delivery) {
  'queued' => Con.wait,
  'claimed' || 'working' => Con.hold,
  'needs_input' => Con.signal,
  'failed' => Con.fail,
  'expired' => Con.wait,
  _ => Con.ruleStrong,
};

/// Text colour for the state line. Only the states that want attention are
/// tinted; a settled state reads in the ordinary secondary ink.
Color teamInk(String delivery) => switch (delivery) {
  'queued' || 'expired' => Con.wait,
  'needs_input' => Con.signalBright,
  'failed' => Con.failBright,
  _ => Con.ink2,
};

String teamWhen(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final DateTime? parsed = DateTime.tryParse(iso);
  if (parsed == null) return '';
  final DateTime local = parsed.toLocal();
  final String time =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  final DateTime now = DateTime.now();
  final bool sameDay =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  if (sameDay) return time;
  const List<String> months = <String>[
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
  return '${months[local.month - 1]} ${local.day} $time';
}

class TeamPanel extends StatefulWidget {
  const TeamPanel({
    super.key,
    required this.account,
    required this.getJson,
    required this.postJson,
  });

  /// The lane to talk on, or an empty string to let the backend pick the
  /// default lane for the signed in role.
  final String account;
  final TeamGet getJson;
  final TeamPost postJson;

  @override
  State<TeamPanel> createState() => _TeamPanelState();
}

class _TeamPanelState extends State<TeamPanel> {
  List<Map<String, dynamic>> threads = <Map<String, dynamic>>[];
  Map<String, dynamic>? thread;
  String lane = '';
  String openThreadId = '';
  String? failure;
  bool loading = false;
  bool sending = false;
  bool quietThreadRefreshInFlight = false;
  Timer? poller;
  int threadRequest = 0;
  int listRequest = 0;
  int sendRequest = 0;
  final TextEditingController draft = TextEditingController();

  /// True while this panel is the tab being shown. The shell keeps every
  /// visited tab mounted so the open conversation survives a tab switch; a
  /// panel nobody is looking at must not keep polling the gateway for it.
  bool _onScreen = true;

  @override
  void initState() {
    super.initState();
    _loadThreads();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool next = TickerMode.valuesOf(context).enabled;
    if (next == _onScreen) return;
    _onScreen = next;
    // Coming back to Team catches up once rather than showing whatever was on
    // screen when it was left.
    if (next && openThreadId.isNotEmpty) {
      _loadThread(openThreadId, quiet: true);
    }
  }

  @override
  void didUpdateWidget(TeamPanel old) {
    super.didUpdateWidget(old);
    // The lane is part of a thread id, so a scope change is a different set of
    // threads rather than a filter over the same ones. The open thread closes.
    if (old.account != widget.account) {
      threadRequest++;
      listRequest++;
      sendRequest++;
      sending = false;
      draft.clear();
      poller?.cancel();
      poller = null;
      openThreadId = '';
      thread = null;
      threads = <Map<String, dynamic>>[];
      _loadThreads();
    }
  }

  @override
  void dispose() {
    poller?.cancel();
    draft.dispose();
    super.dispose();
  }

  String get _query => widget.account.isEmpty
      ? ''
      : '?account=${Uri.encodeComponent(widget.account)}';

  Future<void> _loadThreads({bool quiet = false}) async {
    final int request = ++listRequest;
    if (!quiet) setState(() => loading = true);
    try {
      final dynamic body = await widget.getJson('/reels/team/threads$_query');
      if (!mounted || request != listRequest) return;
      setState(() {
        lane = body is Map ? '${body['account'] ?? ''}' : '';
        threads = body is Map
            ? List<Map<String, dynamic>>.from(
                (body['threads'] as List<dynamic>? ?? <dynamic>[])
                    .whereType<Map<dynamic, dynamic>>()
                    .map(
                      (Map<dynamic, dynamic> e) => Map<String, dynamic>.from(e),
                    ),
              )
            : <Map<String, dynamic>>[];
        failure = null;
      });
    } catch (_) {
      if (!mounted || request != listRequest) return;
      setState(() => failure = 'The team queue did not answer.');
    } finally {
      if (mounted && request == listRequest) setState(() => loading = false);
    }
  }

  Future<void> _loadThread(String id, {bool quiet = false}) async {
    // Poll ticks must not pile up behind a slow gateway response. A manual
    // open/refresh still wins and invalidates the older result by request id.
    if (quiet && quietThreadRefreshInFlight) return;
    if (quiet) quietThreadRefreshInFlight = true;
    final int request = ++threadRequest;
    if (!quiet) setState(() => loading = true);
    try {
      final dynamic body = await widget.getJson(
        '/reels/team/thread?thread_id=${Uri.encodeComponent(id)}',
      );
      if (!mounted || request != threadRequest || id != openThreadId) return;
      setState(() {
        thread = body is Map ? Map<String, dynamic>.from(body) : null;
        failure = null;
      });
    } catch (_) {
      if (!mounted || request != threadRequest || id != openThreadId) return;
      setState(() => failure = 'That thread could not be read.');
    } finally {
      if (quiet) quietThreadRefreshInFlight = false;
      if (mounted && request == threadRequest) setState(() => loading = false);
    }
  }

  void _startPoll() {
    poller?.cancel();
    poller = Timer.periodic(const Duration(seconds: 5), (Timer t) {
      if (!mounted || openThreadId.isEmpty) {
        t.cancel();
        return;
      }
      // Skip the tick rather than cancel the timer: Team is still mounted so
      // the thread is still open, it is simply not the tab on screen.
      if (!_onScreen) return;
      _loadThread(openThreadId, quiet: true);
    });
  }

  void _open(String id) {
    sendRequest++;
    draft.clear();
    setState(() {
      sending = false;
      openThreadId = id;
      thread = null;
      failure = null;
    });
    _loadThread(id).then((_) {
      if (mounted && openThreadId == id) _startPoll();
    });
  }

  void _close() {
    threadRequest++;
    sendRequest++;
    draft.clear();
    poller?.cancel();
    poller = null;
    setState(() {
      sending = false;
      openThreadId = '';
      thread = null;
      failure = null;
    });
    _loadThreads(quiet: true);
  }

  Future<void> _send() async {
    final Map<String, dynamic>? open = thread;
    final String text = draft.text.trim();
    if (open == null || text.isEmpty || sending) return;
    final int request = ++sendRequest;
    final String target = '${open['thread_id']}';
    setState(() => sending = true);
    try {
      await widget.postJson('/reels/team/message', <String, dynamic>{
        'bot_id': open['bot_id'],
        'account': open['account'],
        'text': text,
        'client_id': 'native-${DateTime.now().toUtc().microsecondsSinceEpoch}',
      });
      if (!mounted || request != sendRequest || target != openThreadId) return;
      if (draft.text.trim() == text) draft.clear();
      HapticFeedback.selectionClick();
      await _loadThread('${open['thread_id']}', quiet: true);
      _startPoll();
    } catch (_) {
      if (!mounted || request != sendRequest || target != openThreadId) return;
      setState(
        () =>
            failure = 'Could not confirm sending. Refresh before trying again.',
      );
    } finally {
      if (mounted && request == sendRequest) setState(() => sending = false);
    }
  }

  Widget _unavailableView() => SingleChildScrollView(
    child: ConEmpty(
      title: 'Team is unavailable',
      body: failure!,
      actions: <Widget>[
        ConButton(
          label: 'Try again',
          kind: ConButtonKind.ironOutline,
          onPressed: () {
            setState(() => failure = null);
            if (openThreadId.isEmpty) {
              _loadThreads();
            } else {
              _loadThread(openThreadId);
            }
          },
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    // The unavailable state used to return before the switcher below, so it
    // was laid out by whatever the shell handed it. The shell handed it a
    // loose, centred Stack, and a SingleChildScrollView shrink-wraps: the
    // result was a 368 pt island in the middle of an 844 pt screen. Routing it
    // through the same StackFit.expand shell as the other two states makes it
    // fill the workspace regardless of what an ancestor offers.
    final bool unavailable =
        failure != null && thread == null && threads.isEmpty;
    // This is a navigation transition between two representations of the same
    // durable queue. It is deliberately independent of polling: new network
    // data does not replay the screen entrance.
    final bool showingThread = openThreadId.isNotEmpty;
    return AnimatedSwitcher(
      duration: CdMotion.duration(context, CdMotion.screen),
      switchInCurve: CdMotion.out,
      switchOutCurve: CdMotion.into,
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) =>
          Stack(
            fit: StackFit.expand,
            children: <Widget>[...previousChildren, ?currentChild],
          ),
      transitionBuilder: (Widget child, Animation<double> animation) {
        final Animation<Offset> slide = Tween<Offset>(
          begin: const Offset(.035, 0),
          end: Offset.zero,
        ).chain(CurveTween(curve: CdMotion.out)).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<String>(
          unavailable
              ? 'unavailable'
              : showingThread
              ? 'thread:$openThreadId'
              : 'roster',
        ),
        child: unavailable
            ? _unavailableView()
            : showingThread
            ? _openThread()
            : _threadList(),
      ),
    );
  }

  /// A conversation, and — where there is room for it — the roster it came
  /// from, still on screen beside it.
  ///
  /// This is iPad Mail's shape and it is the shape this screen already had in
  /// pieces: the roster was simply switched away for the thread. Below 900 pt
  /// it still is, which is every iPhone, every Split View pane and an iPad
  /// mini or 11" held in portrait — there, a 340 pt rail would leave the
  /// conversation narrower than a phone.
  Widget _openThread() {
    if (!SandLayout.isRoomy(MediaQuery.sizeOf(context).width)) {
      return _threadView();
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(width: 340, child: _threadList()),
        const VerticalRule(),
        Expanded(child: _threadView()),
      ],
    );
  }

  Widget _threadList() {
    if (loading && threads.isEmpty) {
      return const SingleChildScrollView(
        child: ConEmpty(
          title: 'Loading the roster',
          body: 'Reading the Bots scoped to this account.',
        ),
      );
    }
    if (threads.isEmpty) {
      return const SingleChildScrollView(
        child: ConEmpty(
          title: 'No Bots on this account',
          body:
              'No Bot in the workforce is scoped to the account you selected.',
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        if (failure != null) _retryNotice(),
        _GroupBar('Crew on ${lane.isEmpty ? 'this account' : lane}'),
        _CrewList(
          threads: threads,
          onOpen: (Map<String, dynamic> row) => _open('${row['thread_id']}'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Text(
            'Ask your crew a question or give them a task. Tasks here do not '
            'post content.',
            style: Ty.meta.copyWith(color: Con.ink2, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _retryNotice() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(failure!, style: Ty.body.copyWith(color: Con.ink2)),
        ),
        CupertinoButton(
          onPressed: () => openThreadId.isEmpty
              ? _loadThreads(quiet: true)
              : _loadThread(openThreadId, quiet: true),
          child: const Text('Retry'),
        ),
      ],
    ),
  );

  Widget _threadView() {
    final Map<String, dynamic>? open = thread;
    final List<Map<String, dynamic>> messages = open == null
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            (open['messages'] as List<dynamic>? ?? <dynamic>[])
                .whereType<Map<dynamic, dynamic>>()
                .map((Map<dynamic, dynamic> e) => Map<String, dynamic>.from(e)),
          );
    final String title = open == null ? 'Loading' : '${open['role_title']}';
    // The composer owns the bottom edge of the conversation. The message list
    // is the only scrolling surface, so it remains reachable above a keyboard
    // and the send affordance never drifts away from the active draft.
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: <Widget>[
              Semantics(
                button: true,
                label: 'Back to the Bot list',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _close,
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Con.rule,
                        width: SandBorder.interactive,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      CupertinoIcons.chevron_left,
                      size: 16,
                      color: Con.ink2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(title, style: Ty.title.copyWith(color: Con.ink)),
                    Text(
                      open == null ? '' : '${open['account']}',
                      style: Ty.meta.copyWith(color: Con.ink2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Rule(),
        if (failure != null) _retryNotice(),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            children: <Widget>[
              if (open == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Getting your conversation.'),
                )
              else if (messages.isEmpty)
                const _ConversationEmpty()
              else
                for (final Map<String, dynamic> m in messages)
                  _MessageBlock(
                    key: ValueKey<String>('job:${m['job_id'] ?? m['at']}'),
                    message: m,
                    roleTitle: title,
                  ),
            ],
          ),
        ),
        if (open != null) _composer(title),
      ],
    );
  }

  Widget _composer(String title) => Container(
    decoration: const BoxDecoration(
      color: Con.surface1,
      border: Border(top: BorderSide(color: Con.rule)),
    ),
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
    child: SafeArea(
      top: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: CupertinoTextField(
              controller: draft,
              minLines: 1,
              maxLines: 4,
              maxLength: 4000,
              placeholder: 'Message $title',
              placeholderStyle: Ty.body.copyWith(color: Con.ink3),
              style: Ty.body.copyWith(color: Con.ink),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              cursorColor: Con.signal,
              decoration: BoxDecoration(
                color: Con.surface2,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Con.rule),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ConButton(
            label: sending ? 'Sending' : 'Send',
            kind: ConButtonKind.signalFill,
            onPressed: sending ? null : _send,
          ),
        ],
      ),
    ),
  );
}

class _ConversationEmpty extends StatelessWidget {
  const _ConversationEmpty();

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
    child: Column(
      children: <Widget>[
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: <Color>[
                Con.signal.withValues(alpha: .13),
                Con.surface2.withValues(alpha: .2),
              ],
            ),
          ),
          child: const Icon(
            CupertinoIcons.bubble_left_bubble_right_fill,
            size: 56,
            color: Con.ink3,
          ),
        ),
        const SizedBox(height: 18),
        Text('Nothing sent yet', style: Ty.title.copyWith(color: Con.ink)),
        const SizedBox(height: 8),
        Text(
          'Ask a question or give your crew a task above.',
          textAlign: TextAlign.center,
          style: Ty.body.copyWith(color: Con.ink2, height: 1.4),
        ),
      ],
    ),
  );
}

class _GroupBar extends StatelessWidget {
  const _GroupBar(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Container(
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(text, style: Ty.body.copyWith(color: Con.ink2)),
      ),
      const Rule(),
    ],
  );
}

/// The handoff's Crew surface, tied directly to the thread roster returned by
/// the queue. There are no locally invented staff, availability or activity
/// signals: one card is one real thread and opens that conversation.
class _CrewList extends StatelessWidget {
  const _CrewList({required this.threads, required this.onOpen});
  final List<Map<String, dynamic>> threads;
  final ValueChanged<Map<String, dynamic>> onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    // A Bot is a card, so the roster is a grid of them on an iPad and a
    // single column on a phone. Measured against the box this list is given
    // rather than the screen, because the same list is also the 340 pt rail
    // beside an open conversation, where one column is right.
    child: LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) => Column(
        children: conCardRows(<Widget>[
          for (int index = 0; index < threads.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: CdEnter(
                key: ValueKey<String>(
                  'crew-enter:${threads[index]['thread_id']}',
                ),
                delay: CdMotion.stagger * index.clamp(0, 4),
                child: _CrewCard(
                  key: ValueKey<String>('crew:${threads[index]['thread_id']}'),
                  row: threads[index],
                  onTap: () => onOpen(threads[index]),
                ),
              ),
            ),
        ], SandLayout.columnsFor(box.maxWidth)),
      ),
    ),
  );
}

String _crewDeliveryLabel(String delivery, int messages) => switch (delivery) {
  'queued' => 'Queued',
  'working' => 'Working',
  'claimed' || 'leased' => 'Picked up',
  'needs_input' => 'Needs you',
  'failed' => 'Needs attention',
  'expired' => 'Expired',
  _ when messages == 0 => 'No messages yet',
  _ => 'Updated',
};

/// Roster previews are a glanceable invitation into a conversation, not an
/// activity log. Keep a normal human sentence intact when possible; hide
/// serialized evidence and implementation prompts until the crew thread is
/// opened, where the original message remains available.
String _crewPreview(Object? value, String fallback) {
  final String raw = '${value ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (raw.isEmpty) return fallback;
  final String lower = raw.toLowerCase();
  if (lower.contains('evidence:') ||
      lower.contains('reel_id:') ||
      lower.contains('scheduled_at:') ||
      lower.contains('cached account context') ||
      lower.contains('implementation check requested')) {
    return 'Open conversation for the full update.';
  }
  if (raw.length <= 88) return raw;
  final int sentenceEnd = raw.indexOf(RegExp(r'[.!?]'));
  if (sentenceEnd >= 0 && sentenceEnd < 88) {
    return raw.substring(0, sentenceEnd + 1);
  }
  final int breakAt = raw.lastIndexOf(' ', 84);
  return '${raw.substring(0, breakAt > 0 ? breakAt : 84)}…';
}

class _CrewCard extends StatelessWidget {
  const _CrewCard({super.key, required this.row, required this.onTap});
  final Map<String, dynamic> row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final int count = (row['message_count'] as num?)?.toInt() ?? 0;
    final int open = (row['open_count'] as num?)?.toInt() ?? 0;
    final String delivery = '${row['last_delivery'] ?? ''}';
    final String state = _crewDeliveryLabel(delivery, count);
    final String preview = _crewPreview(
      row['last_preview'],
      count == 0 ? 'No messages yet' : state,
    );
    return Semantics(
      button: true,
      label: '${row['role_title']}, $state${open > 0 ? ', $open open' : ''}',
      child: CdPressFeedback(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: CdMotion.duration(context, CdMotion.std),
            curve: CdMotion.out,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Con.surface2,
              border: Border.all(color: Con.rule),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              children: <Widget>[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 4,
                    color: open > 0 ? Con.signal : Con.ruleStrong,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 9, 10, 9),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    '${row['role_title'] ?? 'Crew member'}',
                                    style: Ty.title.copyWith(
                                      color: Con.ink,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                                if (open > 0) ...<Widget>[
                                  const SizedBox(width: 8),
                                  Text(
                                    '$open open',
                                    style: Ty.meta.copyWith(
                                      color: Con.signalBright,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Ty.meta.copyWith(
                                color: Con.ink2,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        CupertinoIcons.chevron_right,
                        size: 14,
                        color: Con.ink3,
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

class _MessageBlock extends StatelessWidget {
  const _MessageBlock({
    super.key,
    required this.message,
    required this.roleTitle,
  });
  final Map<String, dynamic> message;
  final String roleTitle;

  @override
  Widget build(BuildContext context) {
    final String delivery = '${message['delivery'] ?? ''}';
    final List<Map<String, dynamic>> replies = List<Map<String, dynamic>>.from(
      (message['replies'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> e) => Map<String, dynamic>.from(e)),
    );
    final String detail = switch (delivery) {
      'queued' => 'Queued — not picked up yet',
      'claimed' || 'leased' => 'Picked up by your crew.',
      'working' => 'Your crew is working on this.',
      'needs_input' => 'Your crew needs your reply.',
      'replied' => 'Replied.',
      'failed' => 'Your crew could not finish this task.',
      'expired' => 'This task expired before it finished.',
      _ => 'Waiting for an update.',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: .88,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 9),
                decoration: BoxDecoration(
                  color: Con.surface3,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(5),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${message['text'] ?? ''}',
                      style: Ty.body.copyWith(color: Con.ink),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: _DeliveryChip(
                            label: detail,
                            delivery: delivery,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          teamWhen('${message['at']}'),
                          style: Ty.meta.copyWith(color: Con.ink3),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          for (final Map<String, dynamic> r in replies)
            CrewReceiptReveal(
              key: ValueKey<String>('receipt:${r['receipt_id'] ?? r['at']}'),
              child: _ReplyBlock(
                key: ValueKey<String>('reply:${r['receipt_id'] ?? r['at']}'),
                reply: r,
                roleTitle: roleTitle,
              ),
            ),
        ],
      ),
    );
  }
}

class _DeliveryChip extends StatelessWidget {
  const _DeliveryChip({required this.label, required this.delivery});
  final String label;
  final String delivery;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: teamTone(delivery).withValues(alpha: .14),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: Ty.meta.copyWith(color: teamInk(delivery), height: 1.1),
    ),
  );
}

String _humanReplyText(Object? value) {
  String text = '${value ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return 'No update yet.';
  final String lower = text.toLowerCase();
  final int evidence = lower.indexOf('evidence:');
  if (evidence > 0) text = text.substring(0, evidence).trim();
  if (text.isEmpty ||
      lower.contains('cached account context') ||
      lower.startsWith('implementation check requested')) {
    return 'This update contains technical queue details.';
  }
  return text;
}

class _ReplyBlock extends StatefulWidget {
  const _ReplyBlock({super.key, required this.reply, required this.roleTitle});
  final Map<String, dynamic> reply;
  final String roleTitle;

  @override
  State<_ReplyBlock> createState() => _ReplyBlockState();
}

class _ReplyBlockState extends State<_ReplyBlock> {
  bool showDetails = false;
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> reply = widget.reply;
    final String text = '${reply['text'] ?? ''}'.trim();
    final String detail = '${reply['display_detail'] ?? ''}'.trim();
    final String status = '${reply['display_status'] ?? ''}';
    final bool isStatus =
        status == 'invalid_placeholder' ||
        status == 'failure' ||
        status == 'status';
    final String message = !isStatus && text.isNotEmpty
        ? text
        : detail.isNotEmpty
        ? detail
        : 'No update yet.';
    final String readable = _humanReplyText(message);
    final bool canExpand = readable.length > 360;
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 30),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 9),
          decoration: BoxDecoration(
            color: Con.surface2,
            border: Border.all(color: Con.rule),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(5),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.roleTitle,
                      style: Ty.meta.copyWith(color: Con.signalBright),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    teamWhen('${reply['at']}'),
                    style: Ty.meta.copyWith(color: Con.ink3),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                readable,
                maxLines: expanded ? null : 5,
                overflow: expanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: Ty.body.copyWith(color: Con.ink, height: 1.4),
              ),
              if (canExpand)
                CupertinoButton(
                  padding: const EdgeInsets.only(top: 4),
                  minimumSize: Size.zero,
                  onPressed: () => setState(() => expanded = !expanded),
                  child: Text(
                    expanded ? 'Show less' : 'Read full update',
                    style: Ty.meta.copyWith(color: Con.signalBright),
                  ),
                ),
              const SizedBox(height: 2),
              if ('${reply['receipt_id'] ?? ''}'.isNotEmpty)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => setState(() => showDetails = !showDetails),
                  child: Text(
                    showDetails ? 'Hide details' : 'Details',
                    style: Ty.meta.copyWith(color: Con.ink3),
                  ),
                ),
              if (showDetails && '${reply['receipt_id'] ?? ''}'.isNotEmpty)
                CrewDetailsReveal(
                  open: true,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Receipt ${reply['receipt_id']}',
                      style: Ty.meta.copyWith(color: Con.ink3),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

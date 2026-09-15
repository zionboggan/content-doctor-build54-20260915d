import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'app_motion.dart';
import 'console_shell.dart';

// The theme moved to app_theme.dart (Adaline dark). It is re-exported here so
// every existing `import 'app_experience.dart'` keeps studioTheme(),
// studioBackground, studioSurface and studioAccent in scope unchanged.
export 'app_theme.dart';

const String tutorialSeenKey = 'trial.tutorial.seen.v1';
const String alwaysShowTipsKey = 'trial.tips.always';

class TutorialStep {
  const TutorialStep(
    this.section,
    this.title,
    this.body,
    this.icon,
    this.action,
  );
  final String section, title, body, action;
  final IconData icon;
}

const List<TutorialStep> tutorialSteps = <TutorialStep>[
  TutorialStep(
    'Welcome',
    'Your content, your call',
    'Turn on Tailscale, then use your private sign-in details. Choose an account before you create, review or schedule. You can return to this guide from Accounts → Replay tutorial.',
    CupertinoIcons.person_crop_circle,
    'Connect · Choose an account · Create',
  ),
  TutorialStep(
    'Review',
    'Watch the whole reel',
    'Open Review and tap Watch. Check the picture, audio and captions. Approve accepts this version; Changes asks for a revision. Approval alone does not post it.',
    CupertinoIcons.play_rectangle,
    'Tap to preview',
  ),
  TutorialStep(
    'Studio',
    'Make it your own',
    'Import a video or audio file from your phone, request a reel, or make variations. Trim and caption your clip, preview the music, then review the finished export.',
    CupertinoIcons.slider_horizontal_3,
    'Preview, then review the export',
  ),
  TutorialStep(
    'Flyers',
    'Make a flyer or carousel',
    'In Studio, choose Make a flyer. Pick the account, name the flyer and type every detail yourself; nothing is filled in for you. One slide is a flyer, two to ten slides are a carousel, and slide order is the posting order. Render for review sends it to review, never to Instagram.',
    CupertinoIcons.doc_richtext,
    'Studio · Create · Make a flyer',
  ),
  TutorialStep(
    'Schedule',
    'Choose the moment',
    'After approval, choose Schedule or Post now when available. Each reel needs your confirmation. A held post needs attention; it is not a successful post.',
    CupertinoIcons.calendar,
    'Approve, then confirm',
  ),
  TutorialStep(
    'Results',
    'See what connects',
    'Results shows available performance data. Check publishing and analytics connections in Accounts. Missing data is not zero, and a connection does not mean posting is enabled.',
    CupertinoIcons.chart_bar,
    'Connect Insights',
  ),
  TutorialStep(
    'Team',
    'Work with your crew',
    'Open Team, pick a role and send a task. Queued means waiting; Working means it has started. Inbox and Automations are in More. Drafting a reply does not send it.',
    CupertinoIcons.chat_bubble_2,
    'Ask · Follow progress · Review the reply',
  ),
];

class GuideChapter {
  const GuideChapter(this.title, this.location, this.icon, this.steps);
  final String title, location;
  final IconData icon;
  final List<String> steps;
}

const guideChapters = <GuideChapter>[
  GuideChapter('Get connected', 'Sign in · Accounts', CupertinoIcons.lock, [
    'Turn on Tailscale on your phone. Open the app and use the private server address and access key supplied to you. Never share your key.',
    'The lock opens Sign in. Use your own details, then tap Unlock. Your access determines which accounts and actions you can use.',
    'Use the account selector to focus your work. All accounts is an overview, not permission to act on every account.',
  ]),
  GuideChapter(
    'Find your way around',
    'Navigation · More',
    CupertinoIcons.square_grid_2x2,
    [
      'Review is your decision desk. Schedule holds planned posts. Studio is where you create and edit.',
      'Results shows performance. Accounts manages connections. Team opens conversations with your crew.',
      'Open More for Inbox, Automations, Search and Refresh. Replay tutorial is on the Accounts tab, under Help. Search and filters narrow the current list; clear them if a clip seems missing.',
      'On a larger screen the same workspaces arrange themselves across more than one column. The tabs, names and controls are identical; only the arrangement changes.',
    ],
  ),
  GuideChapter('Watch and review', 'Review', CupertinoIcons.play_rectangle, [
    'Choose Needs you to focus on pending decisions, or All to browse. Open a clip or tap Watch to check the video, sound and captions.',
    'Watch the required preview before approving. Approve records your decision for this exact version, not future edits.',
    'Tap Changes to describe what should change. Open follows the current revision or available next step. Review a new export again.',
    'The buttons on a clip follow its state: Approve or Watch and Changes while it waits for you, Schedule and Post now once it is approved, and an Edit pencil on a scheduled or queued clip.',
    'The clip menu includes caption editing, Notes and Details when available. A copied private clip link still requires access.',
  ]),
  GuideChapter('Schedule or post', 'Schedule', CupertinoIcons.calendar, [
    'Start with an approved clip. Choose Schedule, pick a time and confirm. Check the displayed time zone before saving.',
    'Today and Upcoming separate planned work. Use the calendar to focus on a day; clear the date filter to see the rest.',
    'Use Reschedule or Cancel schedule to change a plan. Post now, when available, asks for confirmation before proceeding.',
    'Held or failed is not published. Open the item, read the reason and resolve it. If a result is uncertain, refresh and check its status before trying again.',
  ]),
  GuideChapter(
    'Bring in phone media',
    'Studio · Import',
    CupertinoIcons.arrow_up_doc,
    [
      'Choose the destination account first. Choose video opens your phone media picker; Choose audio lets you select an audio file.',
      'Keep each file below 250 MB. Follow the import progress and wait for the result. Imported video arrives for review, not automatic posting.',
      'Imported audio is available to its account in the editor. If an import is interrupted, refresh before retrying so you can check whether it arrived.',
    ],
  ),
  GuideChapter(
    'Create and make variations',
    'Studio · Create',
    CupertinoIcons.sparkles,
    [
      'Request a reel starts a new request from available content. Make variations creates alternatives from existing content.',
      'Choose the account and available source, then describe the result you want. Some creation tools depend on your access.',
      'A submitted request is not a finished video. Follow its status, then watch and review each result before scheduling it.',
    ],
  ),
  GuideChapter(
    'Make a flyer or carousel',
    'Studio · Create · Make a flyer',
    CupertinoIcons.doc_richtext,
    [
      'Open Studio and choose Make a flyer. Pick the destination account first, then give the flyer a name using lowercase letters, numbers and hyphens, and choose its template and brand mark.',
      'One slide is a flyer. Two to ten slides are a carousel, and slide order is the posting order. Add a hook, body or cta slide, move a slide up or down, and remove any slide except the last remaining one.',
      'Type every artist, date, venue, city and event ID yourself. Nothing is guessed or filled in for you: a blank required slot is refused by name, or rendered as a visible placeholder only when you ask for that.',
      'Leave the template demo stamp on until the details are a real, confirmed booking. Confirm you checked them, then choose Render for review and follow the render status.',
      'A flyer render is review-only. This screen has no approve, schedule or publish path, and nothing here posts to Instagram.',
    ],
  ),
  GuideChapter(
    'Edit and export',
    'Studio · Edit reel',
    CupertinoIcons.slider_horizontal_3,
    [
      'Open a clip and choose Edit reel. Set your trim and arrange available clips in the timeline. Keep the important action inside the frame.',
      'Adjust captions and text placement, choose available music and listen to the preview. Check that speech is still easy to hear.',
      'Start the export and follow its progress. Open the finished video and check the beginning, ending, captions and audio before approving.',
      'An edited video needs its own review. An export failure is not a playable result; read the message before retrying.',
    ],
  ),
  GuideChapter(
    'Library and account style',
    'Studio · Profile manager',
    CupertinoIcons.collections,
    [
      'The approved library provides quick access to approved clips. Open a clip to edit it; a changed version still needs review.',
      'In Profile manager, select an account before changing its prompts or settings. Keep directions specific to that account.',
      'View brief & experiment ideas opens the available planning material. Analytics coverage warnings mean recommendations may have incomplete evidence.',
    ],
  ),
  GuideChapter('Understand your results', 'Results', CupertinoIcons.chart_bar, [
    'Published shows available posts and their performance. Activity shows recorded activity; neither is a guarantee that all provider data has arrived.',
    'Use the account filter and refresh to focus on current results. Open a post preview or its available details for context.',
    'Views, reach and interactions measure different things. Missing or stale data is not zero. Connect analytics in Accounts when prompted.',
  ]),
  GuideChapter('Connect Instagram', 'Accounts', CupertinoIcons.link, [
    'Connection and Analytics show separate readiness states. Choose Connect Instagram or Connect for the account you intend to use.',
    'Complete the provider sign-in and permission screens, then return to Content Doctor and refresh. Never enter someone else’s credentials.',
    'Check the resulting status. A connected account can still have publishing held or disabled. Only available, confirmed actions should be treated as ready.',
  ]),
  GuideChapter('Prepare replies', 'More · Inbox', CupertinoIcons.tray, [
    'Select an account and open its available conversations, drafts or suggestions. An empty inbox may mean no conversations are available yet.',
    'Write and save a draft for review. Saving a draft does not send a direct message.',
    'Outbound replies are not active in this version. Use Instagram for an actual reply until the app explicitly supports sending.',
  ]),
  GuideChapter('Plan automations', 'More · Automations', CupertinoIcons.bolt, [
    'Prepare reply ideas and available keyword plans for the selected account. Use the real conversation or comment context requested by the form.',
    'Plans are review-only. Saving one does not turn on automatic replies, send a message or post content.',
    'Automatic replies are not active in this version. Do not rely on a saved plan to respond to your audience.',
  ]),
  GuideChapter('Work with your crew', 'Team', CupertinoIcons.chat_bubble_2, [
    'Choose an account, then a crew role. Give it one clear task, including the desired result and any constraints.',
    'Queued means waiting to be picked up. Picked up means claimed. Working means the task has started. A reply is the crew’s response, not proof of a published post.',
    'Read the reply and ask a follow-up when needed. Open details for supporting information without copying technical identifiers into your next message.',
    'Sending a crew task here does not approve, schedule or publish content. Use the app’s explicit controls for those decisions.',
  ]),
  GuideChapter(
    'Recover and get help',
    'Sign in · Accounts · Replay tutorial',
    CupertinoIcons.arrow_clockwise,
    [
      'If the app cannot connect, check Tailscale and your connection, then retry. If access expires, open the lock and sign in with your own key.',
      'If something is missing, check the selected account and filters. Refresh before repeating an import, export or posting action whose result is uncertain.',
      'Read held and failed messages before trying again. Keep private access keys out of screenshots and crew messages.',
      'This tour opens by itself the first time your workspace loads. Return to it any time from Accounts → Replay tutorial. The tour never changes your content or sends a real task.',
    ],
  ),
];

class TutorialPreferences {
  static Future<bool> shouldShowTutorial() async =>
      (await SharedPreferences.getInstance()).getBool(tutorialSeenKey) != true;
  static Future<void> completeTutorial() async {
    await (await SharedPreferences.getInstance()).setBool(
      tutorialSeenKey,
      true,
    );
  }

  static Future<bool> alwaysShowTips() async =>
      (await SharedPreferences.getInstance()).getBool(alwaysShowTipsKey) ??
      false;
  static Future<void> saveAlwaysShowTips(bool value) async {
    await (await SharedPreferences.getInstance()).setBool(
      alwaysShowTipsKey,
      value,
    );
  }
}

class TutorialPage extends StatefulWidget {
  const TutorialPage({super.key, required this.onFinish});
  final VoidCallback onFinish;
  @override
  State<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> {
  final PageController _pages = PageController();
  int _index = 0;
  bool _guide = false;

  void _move(int index) {
    if (CdMotion.reduced(context)) {
      _pages.jumpToPage(index);
    } else {
      _pages.animateToPage(
        index,
        duration: CdMotion.screen,
        curve: CdMotion.out,
      );
    }
  }

  void _toggleGuide() {
    setState(() => _guide = !_guide);
    if (!_guide) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients) _pages.jumpToPage(_index);
      });
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_guide ? 'Your field guide' : 'A quick tour'),
      actions: <Widget>[
        TextButton(
          onPressed: widget.onFinish,
          child: Text(_guide ? 'Done' : 'Skip'),
        ),
      ],
    ),
    body: SafeArea(
      child: ConColumn(
        child: _guide
            ? CdEnter(child: _buildGuide())
            : Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      children: [
                        Text(
                          'Step ${_index + 1} of ${tutorialSteps.length}',
                          style: const TextStyle(color: SandDark.onSurfaceLow),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 250),
                          child: TextButton(
                            onPressed: _toggleGuide,
                            child: const Text(
                              'Full guide',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: tutorialSteps.length,
                      onPageChanged: (int value) =>
                          setState(() => _index = value),
                      itemBuilder: (BuildContext context, int index) {
                        final TutorialStep step = tutorialSteps[index];
                        return SingleChildScrollView(
                          key: PageStorageKey('tutorial-$index'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 24,
                          ),
                          child: CdEnter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Center(
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 24,
                                    ),
                                    decoration: BoxDecoration(
                                      color: SandDark.primaryContainer,
                                      borderRadius: BorderRadius.circular(
                                        SandRadius.r3,
                                      ),
                                      border: Border.all(
                                        color: SandDark.outline,
                                        width: SandBorder.hairline,
                                      ),
                                    ),
                                    child: Column(
                                      children: <Widget>[
                                        Icon(
                                          step.icon,
                                          size: 44,
                                          color: SandDark.primaryBright,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          step.action,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  step.section,
                                  style: const TextStyle(
                                    color: studioAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  step.title,
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -.8,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  step.body,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    height: 1.5,
                                    color: SandDark.onSurfaceLow,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
                    child: Column(
                      children: <Widget>[
                        Semantics(
                          label:
                              'Step ${_index + 1} of ${tutorialSteps.length}',
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List<Widget>.generate(
                              tutorialSteps.length,
                              (int index) => Container(
                                width: index == _index ? 22 : 6,
                                height: 6,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: index == _index
                                      ? studioAccent
                                      : SandDark.outlineStrong,
                                  borderRadius: BorderRadius.circular(
                                    SandRadius.r1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            if (_index > 0) ...[
                              TextButton(
                                onPressed: () => _move(_index - 1),
                                child: const Text('Back'),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: CdPressFeedback(
                                child: FilledButton(
                                  onPressed: _index == tutorialSteps.length - 1
                                      ? widget.onFinish
                                      : () => _move(_index + 1),
                                  child: Text(
                                    _index == tutorialSteps.length - 1
                                        ? 'Start reviewing'
                                        : 'Next',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    ),
  );

  Widget _buildGuide() => ListView.separated(
    key: const PageStorageKey('full-guide'),
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    itemCount: guideChapters.length + 1,
    separatorBuilder: (_, _) => const SizedBox(height: 8),
    itemBuilder: (context, index) {
      if (index == 0) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Find the next step',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose a chapter. Nothing in this guide changes your content.',
                style: TextStyle(color: SandDark.onSurfaceLow, height: 1.4),
              ),
              TextButton(
                onPressed: _toggleGuide,
                child: const Text('Back to quick tour'),
              ),
            ],
          ),
        );
      }
      final chapter = guideChapters[index - 1];
      return DecoratedBox(
        decoration: BoxDecoration(
          color: SandDark.surfaceBase,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SandDark.outline),
        ),
        child: ExpansionTile(
          key: PageStorageKey('chapter-$index'),
          shape: const Border(),
          collapsedShape: const Border(),
          expansionAnimationStyle: AnimationStyle(
            duration: CdMotion.duration(context, CdMotion.hero),
            curve: CdMotion.out,
          ),
          leading: Icon(chapter.icon, color: studioAccent, size: 24),
          title: Text(
            chapter.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            chapter.location,
            style: const TextStyle(
              fontSize: 12,
              color: SandDark.onSurfaceLow,
              height: 1.4,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: List.generate(
            chapter.steps.length,
            (i) => Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: studioAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      chapter.steps[i],
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: SandDark.onSurfaceLow,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class ContextTip extends StatelessWidget {
  const ContextTip({super.key, required this.section, required this.onHelp});
  final String section;
  final VoidCallback onHelp;
  @override
  Widget build(BuildContext context) {
    final TutorialStep step = tutorialSteps.firstWhere(
      (TutorialStep step) => step.section == section,
      // Looked up by name, not by index. The Accounts tab has no step of its
      // own and borrows the Results one, which talks about connections; an
      // index here silently pointed at a different step the moment a step was
      // inserted above it.
      orElse: () => section == 'Accounts'
          ? tutorialSteps.firstWhere(
              (TutorialStep step) => step.section == 'Results',
            )
          : tutorialSteps.first,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: SandDark.primaryContainer,
          borderRadius: BorderRadius.circular(SandRadius.r3),
        ),
        child: ListTile(
          leading: Icon(step.icon, color: studioAccent),
          title: Text(
            step.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            step.body,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          trailing: const Icon(CupertinoIcons.question_circle, size: 20),
          onTap: onHelp,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
        ),
      ),
    );
  }
}

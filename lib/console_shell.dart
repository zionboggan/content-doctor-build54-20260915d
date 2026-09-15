// Console primitives for Trial Reels: tokens with honest names, the six type
// roles, the cue mark, and the small set of shapes the theme cannot express.
//
// The tokens below alias SandDark rather than restating hex values, so there
// is still exactly one place a colour is defined. The alias exists because a
// token named for its role (signal, hold, wait) survives a redesign and a
// token named for a hue does not.

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
// Only for showConSheet's Material ancestor. The shell is Cupertino chrome;
// this is the one Material widget it needs, so the import is narrowed to it.
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'app_motion.dart';

/// Colour roles. One hue per meaning, and only this role.
class Con {
  const Con._();

  static const Color ground = SandDark.surfaceLowest; // #121315
  static const Color surface1 = SandDark.surfaceLow; // #17191C
  static const Color surface2 = SandDark.surfaceBase; // #1C1F23
  static const Color surface3 = SandDark.surfaceHigh; // #22262B
  static const Color well = SandDark.surfaceDim; // #0E0F11

  static const Color rule = SandDark.outline; // #2E343B
  static const Color ruleStrong = SandDark.outlineStrong; // #3F4750

  static const Color ink = SandDark.onSurfaceBase; // #E8E4DE
  static const Color ink2 = SandDark.onSurfaceLow; // #B8B2A9
  static const Color ink3 = SandDark.onSurfaceLowest; // #8E8880

  /// Needs you.
  static const Color signal = SandDark.primary; // #E8833A
  static const Color signalBright = SandDark.primaryBright; // #F2A05A

  /// The only text colour permitted on a filled [signal] surface. `ink` on
  /// `signal` measures 2.6:1 and is forbidden.
  static const Color onSignal = SandDark.onPrimary; // #1A1206

  /// The system is holding it: approved, scheduled.
  static const Color hold = SandDark.secondary; // #6E9BC4
  static const Color holdBright = SandDark.secondaryBright; // #8FB4D6

  /// Waiting on a person: changes requested, paused.
  static const Color wait = SandDark.warning; // #E3B341

  static const Color fail = SandDark.error; // #E5675C
  static const Color failBright = SandDark.errorBright; // #EF8E86

  /// Flat sheet scrim. No blur anywhere in this product.
  static const Color scrim = Color(0xE00B0C0D);

  static const Duration quick = CdMotion.micro;
  static const Duration present = CdMotion.hero;
}

/// Shared mascot artwork, also used by the installed app icon.
class DoctorAvatar extends StatelessWidget {
  const DoctorAvatar({super.key, this.size = 52});
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(size * .23),
      child: Image.asset(
        'assets/doctor-icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
        errorBuilder: (_, _, _) => SizedBox(
          width: size,
          height: size,
          child: const Center(child: TrialMark(size: 24)),
        ),
      ),
    ),
  );
}

class DoctorCard extends StatelessWidget {
  const DoctorCard({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.margin = const EdgeInsets.fromLTRB(12, 3, 12, 5),
  });
  final Widget child;
  final Duration delay;
  final EdgeInsets margin;
  @override
  Widget build(BuildContext context) => CdEnter(
    delay: delay,
    child: Container(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Con.rule),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Con.surface2, Con.surface1],
        ),
      ),
      child: child,
    ),
  );
}

class DoctorAction extends StatelessWidget {
  const DoctorAction({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => DoctorCard(
    child: Semantics(
      button: true,
      child: CdPressFeedback(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Con.signal.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Con.signalBright, size: 25),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Ty.title.copyWith(color: Con.ink)),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Ty.meta.copyWith(color: Con.ink2, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: Con.ink2,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// The six type roles. Nothing in this product is larger than 22.
class Ty {
  const Ty._();

  static const List<FontFeature> _figures = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  static const TextStyle count = TextStyle(
    fontSize: 22,
    height: 1,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.22,
    fontFeatures: _figures,
  );
  static const TextStyle title = TextStyle(
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.17,
    fontFeatures: _figures,
  );
  static const TextStyle body = TextStyle(
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w400,
    fontFeatures: _figures,
  );
  static const TextStyle label = TextStyle(
    fontSize: 14,
    height: 18 / 14,
    fontWeight: FontWeight.w500,
    fontFeatures: _figures,
  );
  static const TextStyle meta = TextStyle(
    fontSize: 12,
    height: 14 / 12,
    fontWeight: FontWeight.w500,
    fontFeatures: _figures,
  );
  static const TextStyle caps = TextStyle(
    fontFamily: 'Inter',
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: .5,
    fontFeatures: _figures,
  );
}

/// A full-bleed 1px separator. Content is inset by the gutter; rules are not.
class Rule extends StatelessWidget {
  const Rule({super.key, this.strong = false});
  final bool strong;
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: strong ? Con.ruleStrong : Con.rule);
}

/// The same hairline, stood on its end: the seam between two panes. Same
/// token, same 1 px, same colour as every other rule in the app.
class VerticalRule extends StatelessWidget {
  const VerticalRule({super.key, this.strong = false});
  final bool strong;
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, color: strong ? Con.ruleStrong : Con.rule);
}

/// Uppercase readout text. Never below 10, never lighter than ink-3.
class Caps extends StatelessWidget {
  const Caps(this.text, {super.key, this.color = Con.ink2});
  final String text;
  final Color color;
  @override
  // Caps text is a state mark or a readout, never prose, so it is one line
  // and it gives way rather than wrapping under a large text size.
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.ellipsis,
    style: Ty.caps.copyWith(color: color),
  );
}

/// Content Doctor's supplied cross mark. The public name remains compatible
/// with existing screens that used the earlier project mark.
class TrialMark extends StatelessWidget {
  const TrialMark({super.key, this.size = 24, this.color, this.dotColor});
  final double size;

  /// Frame colour. Defaults to ink; pass a single colour with [dotColor] null
  /// for the monochrome variant.
  final Color? color;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _MarkPainter(
        frame: color ?? Con.ink,
        accent: dotColor ?? color ?? Con.signal,
      ),
      isComplex: false,
    ),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.frame, required this.accent});
  final Color frame, accent;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width / 28;
    final Paint paint = Paint()..color = accent;
    final Radius radius = Radius.circular(2.5 * s);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(10 * s, 0, 8 * s, 28 * s), radius),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 10 * s, 28 * s, 8 * s), radius),
      paint,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.frame != frame || old.accent != accent;
}

/// back5 and fwd5. Cupertino carries 10, 15, 30 and up but not 5, and the
/// transport seeks 5, so the glyph is drawn rather than mislabelled with a
/// stock icon that states the wrong interval. Geometry is the sprite's:
/// a three-quarter square-cornered ring inset 4 in a 20 box, open at the top
/// right, a 3px arrowhead at the opening, and the numeral centred.
class Seek5Glyph extends StatelessWidget {
  const Seek5Glyph({
    super.key,
    required this.forward,
    this.size = 20,
    this.color = Con.ink,
  });

  final bool forward;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _Seek5Painter(forward: forward, color: color),
      isComplex: false,
    ),
  );
}

class _Seek5Painter extends CustomPainter {
  const _Seek5Painter({required this.forward, required this.color});
  final bool forward;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width / 20;
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, 1.5 * s)
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter;

    // Ring, walked away from the opening so the arrowhead sits at the end of
    // the travel rather than the start of it.
    final Path ring = Path();
    if (forward) {
      ring
        ..moveTo(8 * s, 4 * s)
        ..lineTo(16 * s, 4 * s)
        ..lineTo(16 * s, 16 * s)
        ..lineTo(4 * s, 16 * s)
        ..lineTo(4 * s, 8 * s);
    } else {
      ring
        ..moveTo(12 * s, 4 * s)
        ..lineTo(4 * s, 4 * s)
        ..lineTo(4 * s, 16 * s)
        ..lineTo(16 * s, 16 * s)
        ..lineTo(16 * s, 8 * s);
    }
    canvas.drawPath(ring, stroke);

    // 3px arrowhead at the opening, pointing the way the seek goes.
    final double tipX = forward ? 8 * s : 12 * s;
    final double dir = forward ? -1 : 1;
    final Path head = Path()
      ..moveTo(tipX, 4 * s)
      ..lineTo(tipX + 3 * s * dir, 1.5 * s)
      ..lineTo(tipX + 3 * s * dir, 6.5 * s)
      ..close();
    canvas.drawPath(
      head,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );

    final TextPainter numeral = TextPainter(
      text: TextSpan(
        text: '5',
        style: TextStyle(
          color: color,
          fontSize: 8 * s,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    numeral.paint(
      canvas,
      Offset(10 * s - numeral.width / 2, 11 * s - numeral.height / 2),
    );
  }

  @override
  bool shouldRepaint(_Seek5Painter old) =>
      old.forward != forward || old.color != color;
}

/// Button roles. There is at most one [signalFilled] on any screen at rest.
enum ConButtonKind { signalOutline, ironOutline, ghost, redOutline, signalFill }

/// A 36-tall rectangle at radius 4 with a 1.5px border and a 44-tall hit area.
/// Padding is transparent inset, never a taller control.
class ConButton extends StatelessWidget {
  const ConButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = ConButtonKind.ironOutline,
    this.expand = false,
    this.height = 36,
    this.leading,
    this.semanticsLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final ConButtonKind kind;
  final bool expand;
  final double height;
  final IconData? leading;
  final String? semanticsLabel;

  Color get _border => switch (kind) {
    ConButtonKind.signalOutline => Con.signal,
    ConButtonKind.ironOutline => Con.hold,
    ConButtonKind.redOutline => Con.fail,
    ConButtonKind.ghost => const Color(0x00000000),
    ConButtonKind.signalFill => Con.signal,
  };

  Color get _text => switch (kind) {
    ConButtonKind.signalOutline => Con.signalBright,
    ConButtonKind.ironOutline => Con.holdBright,
    ConButtonKind.redOutline => Con.failBright,
    ConButtonKind.ghost => Con.ink2,
    ConButtonKind.signalFill => Con.onSignal,
  };

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final Color textColor = enabled ? _text : Con.ink3;
    final Widget face = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: kind == ConButtonKind.signalFill && enabled
            ? Con.signal
            : const Color(0x00000000),
        borderRadius: BorderRadius.circular(12),
        border: kind == ConButtonKind.ghost
            ? null
            : Border.all(
                color: enabled ? _border : Con.rule,
                width: kind == ConButtonKind.signalFill ? 0 : 1.5,
              ),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (leading != null) ...<Widget>[
            Icon(leading, size: 16, color: textColor),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Ty.label.copyWith(color: textColor),
            ),
          ),
        ],
      ),
    );

    final Widget tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onPressed!();
            }
          : null,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: math.max(0, (44 - height) / 2)),
        child: face,
      ),
    );

    final Widget semantic = Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel ?? label,
      child: CdPressFeedback(enabled: enabled, child: tappable),
    );
    return expand
        ? SizedBox(width: double.infinity, child: semantic)
        : semantic;
  }
}

/// A square icon control with a 44x44 hit area around a smaller visual.
class ConIconButton extends StatelessWidget {
  const ConIconButton({
    super.key,
    this.icon,
    this.glyph,
    required this.onPressed,
    required this.semanticLabel,
    this.color = Con.ink2,
    this.size = 20,
    this.bordered = false,
    this.marked = false,
  }) : assert(icon != null || glyph != null, 'one of icon or glyph');

  final IconData? icon;

  /// A drawn glyph, for the two marks Cupertino does not carry.
  final Widget? glyph;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final Color color;
  final double size;

  /// A 1px hairline box, used by the filter control.
  final bool bordered;

  /// The 6x6 signal square that says a filter or sort is not at its default.
  final bool marked;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    child: CdPressFeedback(
      enabled: onPressed != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onPressed!();
              },
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: bordered ? 35 : 32,
              height: bordered ? 36 : 32,
              decoration: bordered
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Con.rule),
                    )
                  : null,
              child: Stack(
                children: <Widget>[
                  Center(
                    child: glyph ?? Icon(icon, size: size, color: color),
                  ),
                  if (marked)
                    Positioned(
                      right: 3,
                      top: 3,
                      child: Container(width: 6, height: 6, color: Con.signal),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Two segments, hairline box, 2px signal rule flush along the selected
/// segment's own top edge.
class ConSegmented extends StatelessWidget {
  const ConSegmented({
    super.key,
    required this.labels,
    required this.counts,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final List<int> counts;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 36,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Con.rule),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: CdTabIndicator(
        index: index,
        count: labels.length,
        color: Con.signal,
        child: Row(
          children: <Widget>[
            for (int i = 0; i < labels.length; i++) ...<Widget>[
              if (i > 0) Container(width: 1, color: Con.rule),
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == index,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: i == index
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            onChanged(i);
                          },
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: ColoredBox(
                            color: i == index
                                ? Con.signal.withValues(alpha: .14)
                                : const Color(0x00000000),
                          ),
                        ),
                        // The count is the load-bearing half and never shrinks;
                        // the word gives way first at a large text size.
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Flexible(
                                  child: Text(
                                    labels[i],
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: Ty.label.copyWith(
                                      color: i == index ? Con.ink : Con.ink2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                CdAnimatedCount(
                                  value: counts[i],
                                  style: Ty.label.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: i == 0 ? Con.signalBright : Con.ink3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Five cells, 6x4 each. An unrated reel shows nothing at all.
class RatingMeter extends StatelessWidget {
  const RatingMeter({super.key, required this.rating});
  final int rating;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Rating $rating of 5',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < 5; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 2),
          Container(
            width: 6,
            height: 4,
            color: i < rating ? Con.signal : Con.rule,
          ),
        ],
      ],
    ),
  );
}

/// The bottom tab bar: five equal slots, a 24 icon over a caps label, and a
/// 2px signal rule flush along the selected slot's top edge.
class ConTabBar extends StatelessWidget {
  const ConTabBar({
    super.key,
    required this.index,
    required this.onChanged,
    required this.labels,
    required this.icons,
    this.badgeOnFirst = false,
    this.inert = false,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final List<String> labels;
  final List<Widget> icons;
  final bool badgeOnFirst;
  final bool inert;

  @override
  Widget build(BuildContext context) {
    final double inset = MediaQuery.viewPaddingOf(context).bottom;
    return Opacity(
      opacity: inert ? 0.4 : 1,
      child: IgnorePointer(
        ignoring: inert,
        child: Container(
          color: Con.ground,
          padding: EdgeInsets.only(bottom: inset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Rule(),
              SizedBox(
                height:
                    56 +
                    (MediaQuery.textScalerOf(context).scale(10) - 10).clamp(
                          0,
                          20,
                        ) *
                        2,
                child: CdTabIndicator(
                  index: index,
                  count: labels.length,
                  color: Con.signal,
                  child: Row(
                    children: <Widget>[
                      for (int i = 0; i < labels.length; i++)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: i == index,
                            label: labels[i],
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                if (i != index) {
                                  HapticFeedback.selectionClick();
                                  onChanged(i);
                                }
                              },
                              child: Stack(
                                children: <Widget>[
                                  Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Stack(
                                          clipBehavior: Clip.none,
                                          children: <Widget>[
                                            IconTheme(
                                              data: IconThemeData(
                                                size: 24,
                                                color: i == index
                                                    ? Con.signalBright
                                                    : Con.ink3,
                                              ),
                                              child: AnimatedScale(
                                                scale:
                                                    i == index &&
                                                        !CdMotion.reduced(
                                                          context,
                                                        )
                                                    ? 1.16
                                                    : 1,
                                                duration: CdMotion.duration(
                                                  context,
                                                  CdMotion.hero,
                                                ),
                                                curve: CdMotion.spring,
                                                child:
                                                    TweenAnimationBuilder<
                                                      double
                                                    >(
                                                      tween: Tween(
                                                        end: i == index
                                                            ? -2
                                                            : 0,
                                                      ),
                                                      duration:
                                                          CdMotion.duration(
                                                            context,
                                                            CdMotion.hero,
                                                          ),
                                                      curve: CdMotion.spring,
                                                      builder:
                                                          (
                                                            context,
                                                            value,
                                                            child,
                                                          ) =>
                                                              Transform.translate(
                                                                offset: Offset(
                                                                  0,
                                                                  value,
                                                                ),
                                                                child: child,
                                                              ),
                                                      child: icons[i],
                                                    ),
                                              ),
                                            ),
                                            if (i == 0)
                                              Positioned(
                                                right: -2,
                                                top: -2,
                                                child: CdChangePulse(
                                                  value: badgeOnFirst,
                                                  child: Opacity(
                                                    opacity: badgeOnFirst
                                                        ? 1
                                                        : 0,
                                                    child: Container(
                                                      width: 6,
                                                      height: 6,
                                                      color: Con.signal,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 2,
                                          ),
                                          child: Text(
                                            labels[i].toUpperCase(),
                                            textAlign: TextAlign.center,
                                            style: Ty.label.copyWith(
                                              fontSize: 10,
                                              letterSpacing: .2,
                                              color: i == index
                                                  ? Con.signalBright
                                                  : Con.ink3,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
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

/// Empty state: the mark, a title, a body line, then at most two buttons.
class ConEmpty extends StatelessWidget {
  const ConEmpty({
    super.key,
    required this.title,
    required this.body,
    this.actions = const <Widget>[],
  });
  final String title, body;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  colors: [Con.surface3, Con.surface1],
                ),
                border: Border.all(color: Con.ruleStrong),
                boxShadow: [
                  BoxShadow(
                    color: Con.signal.withValues(alpha: .10),
                    blurRadius: 32,
                  ),
                ],
              ),
              child: Icon(
                title.toLowerCase().contains('message')
                    ? CupertinoIcons.chat_bubble_2
                    : title.toLowerCase().contains('queue')
                    ? CupertinoIcons.square_stack
                    : CupertinoIcons.tray,
                size: 44,
                color: Con.ink2,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Ty.title.copyWith(color: Con.ink),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Ty.body.copyWith(color: Con.ink2),
            ),
            if (actions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              ...actions,
            ],
          ],
        ),
      ),
    ),
  );
}

/// One skeleton row at the exact reel-row geometry. No shimmer, no spinner.
class ConSkeletonRow extends StatelessWidget {
  const ConSkeletonRow({super.key});
  @override
  Widget build(BuildContext context) => CdLoadingShimmer(
    child: SizedBox(
      height: 128,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, top: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(width: 60, height: 104, color: Con.surface2),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(width: 64, height: 4, color: Con.surface2),
                const SizedBox(height: 14),
                Container(width: 200, height: 4, color: Con.surface2),
                const SizedBox(height: 14),
                Container(width: 120, height: 4, color: Con.surface2),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Tier 1. Page-wide failure, directly under the sticky block, pushing the
/// list down. Full bleed, a 3px left bar in the state hue, the server text
/// verbatim on its own line.
class ConBanner extends StatelessWidget {
  const ConBanner({
    super.key,
    required this.headline,
    required this.detail,
    this.tone = Con.fail,
    this.actionLabel,
    this.onAction,
  });
  final String headline, detail;
  final Color tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    color: Con.surface1,
    child: Column(
      children: <Widget>[
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(width: 3, color: tone),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 12, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        CupertinoIcons.exclamationmark_triangle,
                        size: 20,
                        color: tone,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              headline,
                              style: Ty.label.copyWith(color: Con.ink),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              detail,
                              style: Ty.meta.copyWith(
                                color: Con.ink2,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (actionLabel != null) ...<Widget>[
                        const SizedBox(width: 12),
                        ConButton(
                          label: actionLabel!,
                          height: 32,
                          kind: tone == Con.wait
                              ? ConButtonKind.ironOutline
                              : ConButtonKind.signalOutline,
                          onPressed: onAction,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const Rule(),
      ],
    ),
  );
}

/// The inline status channel. It replaces the self-erasing toast: reversible
/// work carries its own Undo, irreversible work never appears here until the
/// server has confirmed it.
class ConStatusStrip extends StatelessWidget {
  const ConStatusStrip({super.key, required this.message, this.onUndo});
  final String message;
  final VoidCallback? onUndo;
  @override
  Widget build(BuildContext context) => CdEnter(
    key: ValueKey(message),
    child: Container(
      constraints: const BoxConstraints(minHeight: 36),
      decoration: const BoxDecoration(
        color: Con.surface1,
        border: Border(
          top: BorderSide(color: Con.rule),
          bottom: BorderSide(color: Con.rule),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: <Widget>[
          if (message == 'Approved') ...[
            TweenAnimationBuilder<double>(
              tween: Tween(begin: .7, end: 1),
              duration: CdMotion.duration(
                context,
                const Duration(milliseconds: 320),
              ),
              curve: CdMotion.spring,
              builder: (context, value, child) =>
                  Transform.scale(scale: value, child: child),
              child: const Icon(
                CupertinoIcons.check_mark_circled_solid,
                size: 20,
                color: Con.signalBright,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(message, style: Ty.label.copyWith(color: Con.ink)),
          ),
          if (onUndo != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onUndo,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  'Undo',
                  style: Ty.label.copyWith(color: Con.holdBright),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Sheet chrome: flat scrim, square corners, a 1px rule-strong top edge and a
/// 44-tall caps header.
class ConSheet extends StatelessWidget {
  const ConSheet({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final double availableHeight = media.size.height - media.viewInsets.bottom;
    final double maxHeight = availableHeight * 0.82;
    return AnimatedPadding(
      duration: CdMotion.duration(context, CdMotion.std),
      curve: CdMotion.both,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Con.surface1,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          border: Border(top: BorderSide(color: Con.ruleStrong)),
        ),
        // A sheet is bottom-centred by showConSheet. Without a width it
        // stretches to the glass, so on an iPad Pro the title sat 1366 pt
        // away from its close button. Inert below 560 pt.
        constraints: BoxConstraints(
          maxHeight: maxHeight,
          maxWidth: SandLayout.sheet,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: Ty.title.copyWith(fontSize: 17, color: Con.ink),
                      ),
                    ),
                    ConIconButton(
                      icon: CupertinoIcons.xmark,
                      semanticLabel: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Rule(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < children.length; i++)
                        CdEnter(
                          delay: Duration(milliseconds: (i.clamp(0, 6)) * 40),
                          duration: CdMotion.std,
                          distance: 8,
                          child: children[i],
                        ),
                    ],
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

/// A hairline-separated sheet row.
class ConSheetRow extends StatelessWidget {
  const ConSheetRow({
    super.key,
    required this.label,
    this.detail,
    this.selected = false,
    this.onTap,
    this.height = 44,
    this.labelColor = Con.ink,
    this.trailing,
    this.leadingBar,
  });

  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback? onTap;
  final double height;
  final Color labelColor;
  final Widget? trailing;
  final Color? leadingBar;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    selected: selected,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: selected ? Con.signal.withValues(alpha: .1) : Con.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Con.signal.withValues(alpha: .45) : Con.rule,
          ),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                if (leadingBar != null)
                  Container(width: 3, height: height, color: leadingBar),
                SizedBox(width: leadingBar == null ? 16 : 13),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        label,
                        style: (height >= 56 ? Ty.title : Ty.body).copyWith(
                          color: labelColor,
                        ),
                      ),
                      if (detail != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          detail!,
                          style: Ty.meta.copyWith(color: Con.ink2, height: 1.3),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
                if (selected && trailing == null)
                  const Icon(
                    CupertinoIcons.check_mark,
                    size: 20,
                    color: Con.signal,
                  ),
                if (!selected && trailing == null && onTap != null)
                  const Icon(
                    CupertinoIcons.chevron_forward,
                    size: 16,
                    color: Con.ink3,
                  ),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Present a sheet with the product's scrim and no blur.
/// Caps a single-column page at [SandLayout.readable] and centres it in
/// whatever space is left over.
///
/// Build 52 wrapped the whole app in this. It no longer does: a list of cards
/// becomes a grid at iPad width and a detail screen becomes two panes, because
/// a phone-width column with 331 pt of dark ground down each side is what Zion
/// rejected. What is left here is the narrow, deliberate use — a block of body
/// prose, a tutorial page, a confirmation — where more width is worse rather
/// than better. Inert at or below the cap, so every iPhone width and every
/// Split View pane is untouched.
class ConColumn extends StatelessWidget {
  const ConColumn({
    super.key,
    required this.child,
    this.maxWidth = SandLayout.readable,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// A block of body prose, stopped at [SandLayout.readable] and aligned to the
/// leading edge of whatever it sits in.
///
/// The one place a cap is still the right answer at iPad width: a 1334 pt
/// line of body text is a worse line of body text. It returns [child]
/// unwrapped below the breakpoint, so on a phone this widget is not in the
/// tree at all.
class ConProse extends StatelessWidget {
  const ConProse({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      SandLayout.isWide(MediaQuery.sizeOf(context).width)
      ? Align(
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: SandLayout.readable),
            child: child,
          ),
        )
      : child;
}

/// Lays [cards] out as rows of [columns] cards, for a sliver list or a
/// [Column] that already exists.
///
/// At `columns <= 1` it returns **the same list it was given**, so the phone
/// builds the identical widget tree it built before this function existed —
/// that is the mechanism by which the iPhone is unaffected, rather than a
/// claim about it.
///
/// Cells are [CrossAxisAlignment.start], so a card keeps its own height
/// instead of being stretched to match the tallest card beside it: a card in
/// a grid is the card that shipped, at a different width.
List<Widget> conCardRows(List<Widget> cards, int columns) {
  if (columns <= 1) return cards;
  final List<Widget> rows = <Widget>[];
  for (int i = 0; i < cards.length; i += columns) {
    rows.add(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int c = 0; c < columns; c++)
            Expanded(
              child: i + c < cards.length
                  ? cards[i + c]
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
  return rows;
}

/// A page that is one scrolling column on a phone and two side-by-side panes
/// on an iPad.
///
/// The editor, the generator and the flyer composer are all the same shape:
/// what you are working on, and the controls that change it, one after the
/// other down a single column. On a phone that is one list and stays one list
/// — [primary] then [secondary], in that order, in a single [ListView], which
/// is exactly what shipped. At [SandLayout.readable] and above the same two
/// lists become two panes, left and right, so the thing and its controls are
/// on screen together instead of one being scrolled away to reach the other.
///
/// The children are the same widgets in both modes. Nothing about a control
/// changes shape; only the box it is laid out in does.
class ConPanes extends StatelessWidget {
  const ConPanes({
    super.key,
    required this.primary,
    required this.secondary,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 32),
    this.primaryFlex = 1,
    this.secondaryFlex = 1,
    this.keyboardDismiss = false,
  });

  /// The left pane, and the top of the phone's single column.
  final List<Widget> primary;

  /// The right pane, and the bottom of the phone's single column.
  final List<Widget> secondary;

  final EdgeInsets padding;
  final int primaryFlex;
  final int secondaryFlex;
  final bool keyboardDismiss;

  ScrollViewKeyboardDismissBehavior get _dismiss => keyboardDismiss
      ? ScrollViewKeyboardDismissBehavior.onDrag
      : ScrollViewKeyboardDismissBehavior.manual;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints box) {
      if (!SandLayout.isWide(box.maxWidth)) {
        return ListView(
          padding: padding,
          keyboardDismissBehavior: _dismiss,
          children: <Widget>[...primary, ...secondary],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            flex: primaryFlex,
            child: ListView(
              key: const ValueKey<String>('pane-primary'),
              padding: padding,
              keyboardDismissBehavior: _dismiss,
              children: primary,
            ),
          ),
          const VerticalRule(),
          Expanded(
            flex: secondaryFlex,
            child: ListView(
              key: const ValueKey<String>('pane-secondary'),
              padding: padding,
              keyboardDismissBehavior: _dismiss,
              children: secondary,
            ),
          ),
        ],
      );
    },
  );
}

Future<T?> showConSheet<T>(BuildContext context, WidgetBuilder builder) =>
    showGeneralDialog<T>(
      context: context,
      barrierColor: Con.scrim,
      barrierDismissible: true,
      barrierLabel: 'Close',
      transitionDuration: CdMotion.duration(context, CdMotion.hero),
      // showGeneralDialog puts its page straight on the Overlay, and nothing
      // on that route is a Material. Without one the sheet's text inherits
      // MaterialApp's fallback DefaultTextStyle -- monospace, with a double
      // #FFFF00 underline -- instead of the app's Inter. A transparent
      // Material is the whole fix: it sets the Theme's text style and paints,
      // clips and sizes nothing. See test/sheet_styling_test.dart.
      pageBuilder: (context, animation, secondary) => Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          type: MaterialType.transparency,
          child: builder(context),
        ),
      ),
      transitionBuilder: (context, animation, secondary, child) =>
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: CdMotion.both)),
            child: child,
          ),
    );

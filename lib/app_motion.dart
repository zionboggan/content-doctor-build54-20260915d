import 'package:flutter/widgets.dart';
import 'app_theme.dart';

/// The motion values in Claude's Content Doctor handoff, shared by all screens.
abstract final class CdMotion {
  static const micro = SandMotion.micro;
  static const std = SandMotion.base;
  static const screen = SandMotion.screen;
  static const hero = SandMotion.hero;
  static const stagger = SandMotion.stagger;
  static const out = SandMotion.easeOut;
  static const into = SandMotion.easeIn;
  static const both = SandMotion.easeInOut;
  static const spring = SandMotion.spring;
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);
  static Duration duration(BuildContext context, Duration value) =>
      reduced(context) ? Duration.zero : value;
}

/// Enters once per mounted content identity, never on each refresh or keystroke.
class CdEnter extends StatefulWidget {
  const CdEnter({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = CdMotion.screen,
    this.distance = 12,
  });
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double distance;
  @override
  State<CdEnter> createState() => _CdEnterState();
}

class _CdEnterState extends State<CdEnter> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration + widget.delay,
  );
  bool _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (CdMotion.reduced(context)) {
      _controller.value = 1;
      _started = true;
    } else if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int total = (widget.duration + widget.delay).inMicroseconds;
    final double delay = total == 0 ? 0 : widget.delay.inMicroseconds / total;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final double progress = CdMotion.reduced(context) || total == 0
            ? 1
            : Interval(
                delay,
                1,
                curve: CdMotion.out,
              ).transform(_controller.value);
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, widget.distance * (1 - progress)),
            child: child,
          ),
        );
      },
    );
  }
}

/// Rolls only digits that actually changed. Accessibility exposes the current
/// whole count immediately, never outgoing glyphs or intermediate values.
class CdAnimatedCount extends StatelessWidget {
  const CdAnimatedCount({
    super.key,
    required this.value,
    this.style,
    this.semanticLabel,
  });
  final int value;
  final TextStyle? style;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) {
    final characters = '$value'.split('');
    return Semantics(
      container: true,
      label: semanticLabel ?? '$value',
      excludeSemantics: true,
      child: CdMotion.reduced(context)
          ? Text('$value', style: style, maxLines: 1, softWrap: false)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < characters.length; i++)
                  AnimatedSwitcher(
                    key: ValueKey(characters.length - i),
                    duration: CdMotion.duration(context, CdMotion.hero),
                    switchInCurve: CdMotion.out,
                    switchOutCurve: CdMotion.into,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, .3),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Text(
                      characters[i],
                      key: ValueKey(characters[i]),
                      maxLines: 1,
                      softWrap: false,
                      style: (style ?? const TextStyle()).copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// A brief acknowledgment of changed real data. The displayed value never
/// counts through invented intermediate values or becomes a second semantic node.
class CdChangePulse extends StatefulWidget {
  const CdChangePulse({super.key, required this.value, required this.child});
  final Object? value;
  final Widget child;
  @override
  State<CdChangePulse> createState() => _CdChangePulseState();
}

class _CdChangePulseState extends State<CdChangePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );
  @override
  void didUpdateWidget(CdChangePulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !CdMotion.reduced(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (CdMotion.reduced(context)) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final t = _controller.value;
      final bump = t < .4
          ? CdMotion.out.transform(t / .4)
          : 1 - CdMotion.out.transform((t - .4) / .6);
      return Transform.scale(
        scale: CdMotion.reduced(context) ? 1 : 1 + .12 * bump,
        child: child,
      );
    },
  );
}

/// Change [rejection] only after a real refused action. Initial errors do not
/// shake, and rebuilding or polling the same error cannot replay it.
class CdRejectShake extends StatefulWidget {
  const CdRejectShake({
    super.key,
    required this.rejection,
    required this.child,
  });
  final Object? rejection;
  final Widget child;
  @override
  State<CdRejectShake> createState() => _CdRejectShakeState();
}

class _CdRejectShakeState extends State<CdRejectShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: CdMotion.hero,
    value: 1,
  );
  static const points = <double>[0, -2, 4, -6, 6, -6, 6, -6, 4, -2, 0];
  @override
  void didUpdateWidget(CdRejectShake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rejection != null &&
        oldWidget.rejection != widget.rejection &&
        !CdMotion.reduced(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (CdMotion.reduced(context)) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final position = _controller.value * 10;
      final index = position.floor().clamp(0, 9);
      final dx =
          points[index] +
          (points[index + 1] - points[index]) * (position - index);
      return Transform.translate(
        offset: Offset(CdMotion.reduced(context) ? 0 : dx, 0),
        child: child,
      );
    },
  );
}

/// Visual press feedback without replacing a control's semantics or gesture.
class CdPressFeedback extends StatefulWidget {
  const CdPressFeedback({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<CdPressFeedback> createState() => _CdPressFeedbackState();
}

class _CdPressFeedbackState extends State<CdPressFeedback> {
  bool _pressed = false;
  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: widget.enabled ? (_) => _set(true) : null,
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(
      scale: _pressed && widget.enabled && !CdMotion.reduced(context) ? .97 : 1,
      duration: CdMotion.duration(
        context,
        _pressed ? CdMotion.micro : CdMotion.std,
      ),
      curve: _pressed ? CdMotion.out : CdMotion.spring,
      child: widget.child,
    ),
  );
}

/// One continuous indicator rather than separate bars flashing on selection.
class CdTabIndicator extends StatelessWidget {
  const CdTabIndicator({
    super.key,
    required this.index,
    required this.count,
    required this.color,
    required this.child,
  });
  final int index, count;
  final Color color;
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Stack(
      children: [
        child,
        if (count > 0 && index >= 0 && index < count)
          AnimatedPositioned(
            duration: CdMotion.duration(context, CdMotion.screen),
            curve: CdMotion.both,
            top: 0,
            left: box.maxWidth * index / count,
            width: box.maxWidth / count,
            height: 2,
            child: IgnorePointer(child: ColoredBox(color: color)),
          ),
      ],
    ),
  );
}

/// Quiet, finite loading shimmer. No continuing decoration after loading.
class CdLoadingShimmer extends StatefulWidget {
  const CdLoadingShimmer({super.key, required this.child});
  final Widget child;
  @override
  State<CdLoadingShimmer> createState() => _CdLoadingShimmerState();
}

class _CdLoadingShimmerState extends State<CdLoadingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SandMotion.skeleton,
  );
  bool _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (CdMotion.reduced(context)) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_started) {
      _started = true;
      _controller.repeat(count: 2);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      if (CdMotion.reduced(context) || !_controller.isAnimating) return child!;
      return ShaderMask(
        blendMode: BlendMode.modulate,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment(-3 + 6 * _controller.value, 0),
          end: Alignment(-1 + 6 * _controller.value, 0),
          colors: const [
            Color(0xFFB0B0B0),
            Color(0xFFFFFFFF),
            Color(0xFFB0B0B0),
          ],
          stops: const [0, .5, 1],
        ).createShader(bounds),
        child: child,
      );
    },
  );
}

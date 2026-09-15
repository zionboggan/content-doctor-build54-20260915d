// Motion that belongs to real Crew queue state.
//
// A Crew reply is a receipt from the durable queue, not a simulated typing
// signal. These helpers only run when that record is actually inserted or a
// person explicitly expands a receipt.

import 'package:flutter/widgets.dart';

import 'app_motion.dart';

abstract final class CrewMotion {
  /// The handoff's 320ms spring is reserved for a new, real Bot receipt.
  static const Duration reply = Duration(milliseconds: 320);
}

/// Reveals a newly materialised queue record without reserving space for a
/// pretend response. The stable [key] supplied by the caller makes this run
/// once per receipt, rather than again on every polling rebuild.
class CrewReceiptReveal extends StatefulWidget {
  const CrewReceiptReveal({super.key, required this.child});

  final Widget child;

  @override
  State<CrewReceiptReveal> createState() => _CrewReceiptRevealState();
}

class _CrewReceiptRevealState extends State<CrewReceiptReveal> {
  bool _visible = false;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    if (CdMotion.reduced(context)) {
      _visible = true;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Duration duration = CdMotion.duration(context, CrewMotion.reply);
    return AnimatedOpacity(
      duration: duration,
      curve: CdMotion.out,
      opacity: _visible ? 1 : 0,
      child: AnimatedSlide(
        duration: duration,
        curve: CdMotion.spring,
        offset: _visible ? Offset.zero : const Offset(0, .05),
        child: AnimatedScale(
          duration: duration,
          curve: CdMotion.spring,
          scale: _visible ? 1 : .96,
          alignment: Alignment.bottomLeft,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Smoothly opens receipt metadata requested by the person reading it. It
/// remains an instant state change when the platform requests reduced motion.
class CrewDetailsReveal extends StatefulWidget {
  const CrewDetailsReveal({super.key, required this.open, required this.child});

  final bool open;
  final Widget child;

  @override
  State<CrewDetailsReveal> createState() => _CrewDetailsRevealState();
}

class _CrewDetailsRevealState extends State<CrewDetailsReveal> {
  bool _visible = false;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    if (CdMotion.reduced(context)) {
      _visible = widget.open;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = widget.open);
    });
  }

  @override
  void didUpdateWidget(CrewDetailsReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open != widget.open) _visible = widget.open;
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedAlign(
      duration: CdMotion.duration(context, CdMotion.hero),
      curve: CdMotion.both,
      alignment: Alignment.topLeft,
      heightFactor: _visible ? 1 : 0,
      child: AnimatedOpacity(
        duration: CdMotion.duration(context, CdMotion.std),
        curve: CdMotion.out,
        opacity: _visible ? 1 : 0,
        child: widget.child,
      ),
    ),
  );
}

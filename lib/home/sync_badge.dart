import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'sync_summary.dart';

/// The top of Home (redesign spec §6): "All sent", or "N not sent yet" with
/// a slowly blinking dot. Nothing until every source was read.
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key, required this.summary});

  final SyncSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s.hidden) return const SizedBox.shrink();
    final sent = s.allSent;
    final fg = sent ? WmColors.green : WmColors.brown;
    final dot = Container(width: 7, height: 7, decoration: BoxDecoration(color: fg, shape: BoxShape.circle));
    return Container(
      key: Key(sent ? 'sync-all-sent' : 'sync-not-sent'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: sent ? WmColors.greenTint : WmColors.brownTint, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (sent) dot else _Blink(child: dot),
        const SizedBox(width: 6),
        Text(sent ? 'All sent' : '${s.waiting} not sent yet',
            maxLines: 1, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: fg)),
      ]),
    );
  }
}

/// 1 → 0.3 → 1 every 1.4 s. Still when the phone asks for no animations
/// (and in tests that set it), so a waiting badge never holds a test open.
class _Blink extends StatefulWidget {
  const _Blink({required this.child});

  final Widget child;

  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  late final Animation<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(tween: Tween<double>(begin: 1, end: 0.3), weight: 1),
    TweenSequenceItem(tween: Tween<double>(begin: 0.3, end: 1), weight: 1),
  ]).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _opacity, child: widget.child);
}

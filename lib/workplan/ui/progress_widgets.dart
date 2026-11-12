import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../domain/wp_progress.dart';

Color nextToneColor(NextTone t) => switch (t) {
      NextTone.danger => WmColors.danger,
      NextTone.brown => WmColors.brown,
      NextTone.green => WmColors.green,
      NextTone.normal => WmColors.textSecondary,
    };

/// The card's 4-part bar (Phase 2 spec §4.6).
class TaskProgressBar extends StatelessWidget {
  const TaskProgressBar({super.key, required this.progress});

  final WpProgress progress;

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              key: Key('bar-$i-${progress.reached[i] ? 'on' : 'off'}'),
              height: 4,
              decoration: BoxDecoration(
                color: progress.reached[i] ? WmColors.green : WmColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ]);
}

/// The sheet's step tracker (Phase 2 spec §7). The current step's ring is red
/// or brown when the Next line is, otherwise green.
class StepTracker extends StatelessWidget {
  const StepTracker({super.key, required this.progress});

  final WpProgress progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final ring = switch (p.tone) {
      NextTone.danger => WmColors.danger,
      NextTone.brown => WmColors.brown,
      _ => WmColors.green,
    };
    return Container(
      key: const Key('step-tracker'),
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: WmColors.border), borderRadius: BorderRadius.circular(16)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: _Step(
              index: i,
              reached: p.reached[i],
              current: p.current == i,
              ring: ring,
              leftOn: i > 0 && p.reached[i],
              rightOn: i < 3 && p.reached[i + 1],
              extra: i == 2 && p.leaderChecked ? 'Checked by the leader' : null,
            ),
          ),
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.index,
    required this.reached,
    required this.current,
    required this.ring,
    required this.leftOn,
    required this.rightOn,
    this.extra,
  });

  final int index;
  final bool reached;
  final bool current;
  final Color ring;
  final bool leftOn;
  final bool rightOn;
  final String? extra;

  @override
  Widget build(BuildContext context) {
    Color line(bool on, bool exists) => !exists ? Colors.transparent : (on ? WmColors.green : WmColors.border);
    final state = reached ? 'done' : (current ? 'current' : 'todo');
    final extra = this.extra;
    return Column(key: Key('step-$index-$state'), children: [
      SizedBox(
        height: 28,
        child: Stack(alignment: Alignment.center, children: [
          Row(children: [
            Expanded(child: Container(height: 2, color: line(leftOn, index > 0))),
            Expanded(child: Container(height: 2, color: line(rightOn, index < 3))),
          ]),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: reached ? WmColors.green : Colors.white,
              border: Border.all(color: reached ? WmColors.green : (current ? ring : WmColors.border), width: 2),
            ),
            alignment: Alignment.center,
            child: reached
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : Text('${index + 1}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: current ? ring : WmColors.textDisabled)),
          ),
        ]),
      ),
      const SizedBox(height: 6),
      Text(
        wpStepLabels[index],
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          height: 1.2,
          fontWeight: current ? FontWeight.w800 : FontWeight.w600,
          color: reached || current ? WmColors.text : WmColors.textDisabled,
        ),
      ),
      if (extra != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(extra,
              key: const Key('leader-checked'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, height: 1.2, color: WmColors.green, fontWeight: FontWeight.w700)),
        ),
    ]);
  }
}

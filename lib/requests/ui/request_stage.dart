import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../data/requests_api.dart';
import '../domain/request_status.dart';

/// How far a request has come: the 3-part bar (Saved · Sent · Received) and
/// the status line on its card and in its sheet (redesign Phase 3 spec §5).
class RequestStage {
  const RequestStage({required this.segments, required this.icon, required this.line, required this.color});

  /// The three segments' colours, Saved · Sent · Received.
  final List<Color> segments;
  final IconData icon;
  final String line;
  final Color color;
}

const requestStageLabels = ['Saved', 'Sent', 'Received'];

RequestStage stageOf(SyncState s) => switch (s) {
      SyncState.draft => const RequestStage(
          segments: [WmColors.textMuted, WmColors.border, WmColors.border],
          icon: Icons.edit_note,
          line: 'Not sent yet · finish and send',
          color: WmColors.textSecondary,
        ),
      SyncState.pending => const RequestStage(
          segments: [WmColors.green, WmColors.brown, WmColors.border],
          icon: Icons.cloud_off,
          line: 'Saved on this phone · sends when there is signal',
          color: WmColors.brown,
        ),
      SyncState.received => const RequestStage(
          segments: [WmColors.green, WmColors.green, WmColors.green],
          icon: Icons.check_circle,
          line: 'Received by the office',
          color: WmColors.green,
        ),
      SyncState.failed || SyncState.needsResolution => const RequestStage(
          segments: [WmColors.green, WmColors.danger, WmColors.border],
          icon: Icons.report,
          line: 'Needs attention · open it to see why',
          color: WmColors.danger,
        ),
      SyncState.cancelled => const RequestStage(
          segments: [WmColors.textDisabled, WmColors.textDisabled, WmColors.textDisabled],
          icon: Icons.block,
          line: 'Cancelled',
          color: WmColors.textMuted,
        ),
    };

/// The worker's own request that needs them: its card gets a red border. A
/// leader only reads a team member's request, so theirs stays grey.
bool needsMe(RequestEntry e) =>
    (e.state == SyncState.failed || e.state == SyncState.needsResolution) && (e.remote?.mine ?? true);

/// Three equal segments, height 4, gap 4. Never animated.
class RequestStageBar extends StatelessWidget {
  const RequestStageBar(this.stage, {super.key});

  final RequestStage stage;

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              key: Key('stage-seg-$i'),
              height: 4,
              decoration: BoxDecoration(color: stage.segments[i], borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ],
      ]);
}

/// The status line: icon + words in the state's colour.
class RequestStageLine extends StatelessWidget {
  const RequestStageLine(this.stage, {super.key, this.size = 13, this.iconSize = 17});

  final RequestStage stage;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(stage.icon, size: iconSize, color: stage.color)),
        const SizedBox(width: 6),
        Flexible(child: Text(stage.line, style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: stage.color))),
      ]);
}

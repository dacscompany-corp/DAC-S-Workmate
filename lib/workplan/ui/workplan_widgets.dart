import 'package:flutter/material.dart';

import '../../attendance/ui/status_pill.dart';
import '../../requests/domain/request_status.dart' show calendarDay;
import '../../ui/theme.dart';
import '../domain/wp_rules.dart';
import '../domain/wp_task.dart';
import 'workplan_copy.dart';

/// "Wed 14 Oct – Fri 16 Oct", "From Wed 14 Oct", "Until Fri 16 Oct", or
/// "No date yet". Calendar dates, read as they are.
String plannedLabel(WpTask t) {
  final s = t.plannedStart, e = t.plannedEnd;
  if (s != null && e != null) return s == e ? calendarDay(s) : '${calendarDay(s)} – ${calendarDay(e)}';
  if (s != null) return 'From ${calendarDay(s)}';
  if (e != null) return 'Until ${calendarDay(e)}';
  return 'No date yet';
}

/// A white card, the app's one card shape.
class WpBox extends StatelessWidget {
  const WpBox({super.key, required this.children, this.color = Colors.white, this.border = WmColors.border});

  final List<Widget> children;
  final Color color;
  final Color border;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

/// The task's state as the worker should read it now — what needs them
/// first, then what is still on the phone, then the server's state.
class TaskPill extends StatelessWidget {
  const TaskPill(this.entry, {super.key});
  final WpEntry entry;

  static const _greyFg = Color(0xFF5F5F5B);

  @override
  Widget build(BuildContext context) {
    final e = entry;
    if (e.failedOps.isNotEmpty) return const StatusPill('Not accepted', background: WmColors.dangerTint, foreground: WmColors.danger);
    if (e.toRead) {
      return StatusPill(e.task.changedSinceRead ? 'Changed' : 'New', background: WmColors.dangerTint, foreground: WmColors.danger);
    }
    if (e.toCheck) return const StatusPill('To check', background: WmColors.dangerTint, foreground: WmColors.danger);
    if (e.pendingOps.isNotEmpty) return const StatusPill.brown('Pending sync');
    if (e.blocked) return const StatusPill.brown('Waiting');
    final status = e.effectiveStatus;
    return switch (status) {
      WpStatus.completed => StatusPill.green(statusLabel(status)),
      WpStatus.notStarted => StatusPill(statusLabel(status), background: WmColors.inert, foreground: _greyFg),
      _ => StatusPill.green(statusLabel(status, sentBack: e.task.sentBack)),
    };
  }
}

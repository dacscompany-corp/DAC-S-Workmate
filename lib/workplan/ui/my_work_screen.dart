import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart';
import '../../attendance/ui/formats.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../domain/wp_rules.dart';
import '../workplan_services.dart';
import 'my_work_controller.dart';
import 'notes_screen.dart';
import 'proposals_screen.dart';
import 'task_screen.dart';
import 'workplan_copy.dart';
import 'workplan_widgets.dart';

/// The My Work tab (spec §12): the worker's tasks by Today / Upcoming /
/// Waiting, what needs them highlighted, shared meeting notes, and — for a
/// team leader — their own proposals.
class MyWorkScreen extends StatelessWidget {
  const MyWorkScreen({
    super.key,
    required this.controller,
    required this.services,
    required this.isLeader,
    this.onMakeRequest,
  });

  final MyWorkController controller;
  final WorkPlanServices services;

  /// The profile role is teamLeader: show My proposals. (Which teams they
  /// currently lead, the server decides.)
  final bool isLeader;

  /// Opens Requests (a materials problem's shortcut); null hides it.
  final VoidCallback? onMakeRequest;

  Future<void> _open(BuildContext context, String taskId) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TaskScreen(controller: controller, services: services, taskId: taskId, onMakeRequest: onMakeRequest),
    ));
    await controller.refresh();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          final view = c.view;
          final failure = c.failure;
          final updates = c.updates;
          final sections = [
            for (final g in WpGroup.values)
              if (c.group(g) case final rows when rows.isNotEmpty) (g, rows),
          ];
          return RefreshIndicator(
            onRefresh: c.refresh,
            child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
              const Text('My Work', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Your tasks from the office. Read each one, then report as you work.', style: TextStyle(color: WmColors.textMuted)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  key: const Key('open-notes'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotesScreen(controller: c))),
                  icon: const Icon(Icons.forum_outlined),
                  label: Text('Meeting notes (${view.notes.length})'),
                ),
                if (isLeader)
                  OutlinedButton.icon(
                    key: const Key('open-proposals'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProposalsScreen(controller: c))),
                    icon: const Icon(Icons.lightbulb_outline),
                    label: const Text('My proposals'),
                  ),
              ]),
              const SizedBox(height: 12),
              if (failure != null) ...[
                if (view.fetchedAt != null)
                  Text(
                    'No signal: showing what this phone saved on ${dayMonth(view.fetchedAt!)}, ${clockTime(view.fetchedAt!)}. Pull down to try again.',
                    style: const TextStyle(fontSize: 12.5, color: WmColors.brown),
                  )
                else
                  FailureNotice(
                    english: wpFailureCopy(failure).english,
                    tagalog: wpFailureCopy(failure).tagalog,
                    actions: [noticeAction(retryLabel, c.refresh)],
                  ),
                const SizedBox(height: 12),
              ],
              for (final op in visibleFailures(view.otherFailed))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FailureNotice(
                    leadEnglish: '${opLabel(op)}: ${notAcceptedLead.english}',
                    leadTagalog: notAcceptedLead.tagalog,
                    english: opFailureCopy(op).english,
                    tagalog: opFailureCopy(op).tagalog,
                    actions: [noticeAction(dismissLabel, () => c.dismissFailed(op))],
                  ),
                ),
              if (updates.pending > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '${updates.pending} action${updates.pending == 1 ? '' : 's'} saved on this phone, waiting for signal.',
                    style: const TextStyle(color: WmColors.brown, fontWeight: FontWeight.w600),
                  ),
                ),
              if (c.loading && view.entries.isEmpty) const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator())),
              if (!c.loading && view.entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Text('No tasks for you right now.', textAlign: TextAlign.center, style: TextStyle(color: WmColors.textMuted)),
                ),
              for (final (g, rows) in sections) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text('${groupLabel(g).toUpperCase()} · ${rows.length}', style: monoLabel),
                ),
                for (final e in rows) _TaskCard(key: Key('task-${e.task.id}'), entry: e, today: c.today, onTap: () => _open(context, e.task.id)),
              ],
            ]),
          );
        },
      );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({super.key, required this.entry, required this.today, required this.onTap});

  final WpEntry entry;
  final String today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = entry.task;
    final late = isLate(entry, today);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: (entry.toRead || entry.toCheck) ? WmColors.danger : WmColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              TaskPill(entry),
            ]),
            const SizedBox(height: 4),
            Text(t.where, style: const TextStyle(color: WmColors.textMuted, fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              '${plannedLabel(t)} · ${roleLabel(t.myRole)}${late ? ' · Late' : ''}',
              style: TextStyle(fontSize: 13, color: late ? WmColors.danger : WmColors.textSecondary, fontWeight: late ? FontWeight.w700 : FontWeight.w400),
            ),
          ]),
        ),
      ),
    );
  }
}

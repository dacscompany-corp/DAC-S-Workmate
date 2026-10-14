import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart';
import '../../attendance/ui/formats.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../data/workplan_api.dart';
import '../domain/wp_op.dart';
import '../domain/wp_rules.dart';
import '../domain/wp_task.dart';
import '../workplan_services.dart';
import 'my_work_controller.dart';
import 'report_forms.dart';
import 'workplan_copy.dart';
import 'workplan_widgets.dart';

/// One task (spec §12): the instructions, what changed, "I've read this",
/// and what this worker may do now — start, report progress, report a
/// problem, report done, or (a leader) check the work. Reads its entry from
/// the shared controller by [taskId], so it follows every refresh.
class TaskScreen extends StatelessWidget {
  const TaskScreen({super.key, required this.controller, required this.services, required this.taskId, this.onMakeRequest});

  final MyWorkController controller;
  final WorkPlanServices services;
  final String taskId;
  final VoidCallback? onMakeRequest;

  WorkPlanApi get _api => services.api;

  Future<void> _progress(BuildContext context, WpTask t) async {
    final r = await Navigator.of(context).push<NoteReport>(MaterialPageRoute(
      builder: (_) => NoteFormScreen(
        services: services,
        title: 'Report progress',
        label: 'What was done today?',
        submitLabel: 'Send progress',
        required: true,
        allowPhoto: true,
      ),
    ));
    if (r == null) return;
    await controller.act((a) => a.reportProgress(t, r.note, photo: r.photo));
  }

  Future<void> _problem(BuildContext context, WpTask t) async {
    final r = await Navigator.of(context).push<ProblemReport>(MaterialPageRoute(
      builder: (_) => ProblemFormScreen(services: services, task: t, onMakeRequest: onMakeRequest),
    ));
    if (r == null) return;
    await controller.act((a) => a.reportProblem(t, kind: r.kind, description: r.description, requestId: r.requestId, photo: r.photo));
  }

  Future<void> _done(BuildContext context, WpTask t) async {
    final r = await Navigator.of(context).push<NoteReport>(MaterialPageRoute(
      builder: (_) => NoteFormScreen(
        services: services,
        title: 'Report done',
        label: 'Anything the office should know? (optional)',
        submitLabel: 'Report done',
        explain: 'The office checks the work before it counts as completed.',
      ),
    ));
    if (r == null) return;
    await controller.act((a) => a.reportDone(t, r.note));
  }

  Future<void> _check(BuildContext context, WpTask t) async {
    final r = await Navigator.of(context).push<NoteReport>(MaterialPageRoute(
      builder: (_) => NoteFormScreen(
        services: services,
        title: 'Check this work',
        label: 'Your note for the office (optional)',
        submitLabel: 'Mark as checked',
        explain: 'Your check is recorded. The office still gives the final approval.',
      ),
    ));
    if (r == null) return;
    await controller.act((a) => a.checkWork(t, r.note));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final e = controller.entry(taskId);
          return Scaffold(
            appBar: AppBar(title: const Text('Task')),
            body: SafeArea(
              child: e == null
                  ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('This task is no longer on your list.')))
                  : RefreshIndicator(
                      onRefresh: controller.refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        children: _body(context, e),
                      ),
                    ),
            ),
          );
        },
      );

  List<Widget> _body(BuildContext context, WpEntry e) {
    final t = e.task;
    final a = actionsFor(e);
    final change = t.latestChange;
    return [
      Row(children: [
        Expanded(child: Text(t.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        TaskPill(e),
      ]),
      const SizedBox(height: 4),
      Text(t.where, style: const TextStyle(color: WmColors.textMuted)),
      Text(
        [plannedLabel(t), roleLabel(t.myRole), if (t.teamName != null) 'Team ${t.teamName}', 'Version ${t.version}'].join(' · '),
        style: const TextStyle(color: WmColors.textMuted, fontSize: 13),
      ),
      const SizedBox(height: 12),
      if (e.toRead && t.changedSinceRead)
        WpBox(color: WmColors.dangerTint, border: WmColors.dangerBorder, children: [
          const Text('The office changed this task. Read it again.', style: TextStyle(fontWeight: FontWeight.w800, color: WmColors.danger)),
          if (change != null && change.isNotEmpty) ...[const SizedBox(height: 4), Text(change, style: const TextStyle(color: WmColors.danger))],
        ]),
      if (t.sentBack && t.status == WpStatus.inProgress)
        const WpBox(color: WmColors.brownTint, border: WmColors.brownTint, children: [
          Text('The office sent the work back. See the history for why.', style: TextStyle(fontWeight: FontWeight.w700, color: WmColors.brown)),
        ]),
      for (final op in e.shownFailures)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FailureNotice(
            leadEnglish: '${opLabel(op)}: ${notAcceptedLead.english}',
            leadTagalog: notAcceptedLead.tagalog,
            english: opFailureCopy(op).english,
            tagalog: opFailureCopy(op).tagalog,
            actions: [noticeAction(dismissLabel, () => controller.dismissFailed(op))],
          ),
        ),
      for (final op in e.shownPending)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('${opLabel(op)} · Pending sync', style: const TextStyle(color: WmColors.brown, fontWeight: FontWeight.w700)),
        ),
      WpBox(children: [
        const Text('Instructions', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(t.instructions.isEmpty ? 'No extra instructions.' : t.instructions, style: const TextStyle(fontSize: 15.5, height: 1.35)),
      ]),
      if (a.acknowledge) ...[
        FilledButton.icon(
          key: const Key('ack'),
          onPressed: () => controller.acknowledge(t),
          icon: const Icon(Icons.done_all),
          label: const Text("I'VE READ THIS"),
        ),
        const SizedBox(height: 12),
      ],
      ..._actions(context, e, a),
      if (t.blockers.isNotEmpty || t.waitingFor.isNotEmpty)
        WpBox(children: [
          const Text('Waiting for', style: TextStyle(fontWeight: FontWeight.w800)),
          for (final b in t.blockers) ...[
            const SizedBox(height: 6),
            Text('${problemKindLabel(b.kind)}: ${b.description}', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('Reported by ${b.reportedBy}, ${dayMonth(b.reportedAt)}${b.requestId != null ? ' · linked to a request' : ''}',
                style: const TextStyle(color: WmColors.textMuted, fontSize: 13)),
          ],
          for (final w in t.waitingFor) ...[
            const SizedBox(height: 6),
            Text('Earlier task: ${w.title}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 6),
          const Text('Only the office clears these, after checking.', style: TextStyle(color: WmColors.textMuted, fontSize: 12.5)),
        ]),
      WpBox(children: [
        const Text('People', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('Responsible: ${t.responsible?.name ?? 'not chosen yet'}'),
        if (t.helpers.isNotEmpty) Text('Helpers: ${t.helpers.map((h) => h.name).join(', ')}'),
      ]),
      if (t.photos.isNotEmpty)
        WpBox(children: [
          const Text('Photos', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final p in t.photos) _TaskPhoto(key: ValueKey(p.path), api: _api, path: p.path)]),
        ]),
      if (t.history.isNotEmpty)
        WpBox(children: [
          const Text('History', style: TextStyle(fontWeight: FontWeight.w800)),
          for (final h in t.history.reversed) ...[
            const SizedBox(height: 6),
            Text('${dayMonth(h.at)}, ${clockTime(h.at)} · ${h.by}', style: const TextStyle(color: WmColors.textMuted, fontSize: 12.5)),
            Text(_eventText(h)),
          ],
        ]),
    ];
  }

  List<Widget> _actions(BuildContext context, WpEntry e, WpActions a) {
    final t = e.task;
    Widget lock(WpLock l) => Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(lockText(l), style: const TextStyle(color: WmColors.brown, fontSize: 13)),
        );
    return [
      if (a.start) ...[
        FilledButton(
          key: const Key('start'),
          onPressed: a.startLock == null && !e.pending(WpOpKind.start) ? () => controller.startWork(t) : null,
          child: const Text('START WORK'),
        ),
        if (a.startLock != null) lock(a.startLock!) else const SizedBox(height: 8),
      ],
      if (a.done) ...[
        FilledButton(
          key: const Key('done'),
          onPressed: a.doneLock == null ? () => _done(context, t) : null,
          child: const Text('REPORT DONE'),
        ),
        if (a.doneLock != null) lock(a.doneLock!) else const SizedBox(height: 8),
      ],
      if (a.check) ...[
        FilledButton(key: const Key('check'), onPressed: () => _check(context, t), child: const Text('CHECK THIS WORK')),
        const SizedBox(height: 8),
      ],
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (a.progress)
          OutlinedButton.icon(
            key: const Key('progress'),
            onPressed: () => _progress(context, t),
            icon: const Icon(Icons.edit_note),
            label: const Text('Report progress'),
          ),
        if (a.problem)
          OutlinedButton.icon(
            key: const Key('problem'),
            onPressed: () => _problem(context, t),
            style: OutlinedButton.styleFrom(foregroundColor: WmColors.danger),
            icon: const Icon(Icons.report_outlined),
            label: const Text('Report a problem'),
          ),
      ]),
      const SizedBox(height: 12),
    ];
  }
}

/// A history line in plain words. The office's note follows when there is one.
String _eventText(WpEvent h) {
  final what = switch (h.kind) {
    'drafted' => 'Created by the office',
    'published' => 'Sent to the team',
    'revised' => 'Changed by the office',
    'edited' => 'Corrected by the office',
    'started' => 'Work started',
    'progress' => 'Progress',
    'blocker_reported' => 'Problem reported',
    'blocker_cleared' => 'Problem cleared by the office',
    'reported_done' => 'Reported done',
    'leader_checked' => 'Checked by the leader',
    'approved' => 'Approved by the office',
    'sent_back' => 'Sent back by the office',
    'reopened' => 'Reopened by the office',
    'photo_attached' => 'Photo added',
    _ => h.kind.replaceAll('_', ' '),
  };
  return h.note.isEmpty ? what : '$what — ${h.note}';
}

/// A private photo through a short-lived link; a grey box when it cannot load.
/// The link is asked for once per photo, not on every rebuild.
class _TaskPhoto extends StatefulWidget {
  const _TaskPhoto({super.key, required this.api, required this.path});
  final WorkPlanApi api;
  final String path;

  @override
  State<_TaskPhoto> createState() => _TaskPhotoState();
}

class _TaskPhotoState extends State<_TaskPhoto> {
  late Future<String?> _url = widget.api.photoUrl(widget.path);

  @override
  void didUpdateWidget(_TaskPhoto old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _url = widget.api.photoUrl(widget.path);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: _url,
        builder: (context, snap) {
          final url = snap.data;
          final box = Container(width: 72, height: 72, color: WmColors.inert);
          if (url == null) return box;
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(url, width: 72, height: 72, fit: BoxFit.cover, errorBuilder: (_, _, _) => box),
          );
        },
      );
}

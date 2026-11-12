import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart';
import '../../attendance/ui/formats.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../../ui/wm_sheet.dart';
import '../data/workplan_api.dart';
import '../domain/wp_op.dart';
import '../domain/wp_progress.dart';
import '../domain/wp_rules.dart';
import '../domain/wp_task.dart';
import '../workplan_services.dart';
import 'my_work_controller.dart';
import 'progress_widgets.dart';
import 'report_forms.dart';
import 'workplan_copy.dart';
import 'workplan_widgets.dart';

/// Which report form the task sheet shows (Phase 2 spec §8).
enum TaskForm { progress, problem, done, check }

/// One task as a tall swipe-down sheet (Phase 2 spec §7): everything the old
/// task page showed, the step tracker, and the one main action at the bottom.
/// A report form replaces the body in place; from a form, the back arrow,
/// Back, a drag down or a tap outside return to the task (PopScope), never
/// close the sheet in one move. Reads its entry from the shared controller.
class TaskSheet extends StatefulWidget {
  const TaskSheet({super.key, required this.controller, required this.services, required this.taskId, this.onMakeRequest, this.initialForm});

  final MyWorkController controller;
  final WorkPlanServices services;
  final String taskId;

  /// Opens Requests (a materials problem's shortcut); null hides it.
  final VoidCallback? onMakeRequest;

  /// Open straight on this form (a swipe button).
  final TaskForm? initialForm;

  @override
  State<TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<TaskSheet> {
  late TaskForm? _form = widget.initialForm;

  /// What was typed in each form, kept while this sheet is open (spec §8).
  final _drafts = <TaskForm, ReportDraft>{};

  ReportDraft _draft(TaskForm f) => _drafts.putIfAbsent(f, ReportDraft.new);

  @override
  void dispose() {
    // Closing the sheet clears every draft: an unsent photo is not owed to anyone.
    for (final d in _drafts.values) {
      final p = d.photo;
      if (p != null) widget.services.api.discardPhoto(p);
    }
    super.dispose();
  }

  MyWorkController get _c => widget.controller;

  void _show(TaskForm? f) => setState(() => _form = f);

  Future<void> _sendNote(TaskForm f, WpTask t, NoteReport r) async {
    _drafts.remove(f); // the photo now travels with the report
    _show(null);
    await _c.act((a) => switch (f) {
          TaskForm.progress => a.reportProgress(t, r.note, photo: r.photo),
          TaskForm.done => a.reportDone(t, r.note),
          TaskForm.check => a.checkWork(t, r.note),
          TaskForm.problem => throw StateError('a problem has its own form'),
        });
  }

  Future<void> _sendProblem(WpTask t, ProblemReport r) async {
    _drafts.remove(TaskForm.problem);
    _show(null);
    await _c.act((a) => a.reportProblem(t, kind: r.kind, description: r.description, requestId: r.requestId, photo: r.photo));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final e = _c.entry(widget.taskId);
          // A task that left the list shows no form, so Back closes the sheet.
          final f = e == null ? null : _form;
          return PopScope(
            canPop: f == null,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && _form != null) _show(null);
            },
            child: e == null
                ? const WmSheetFrame(title: 'Task', children: [
                    Padding(
                      key: Key('task-gone'),
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('This task is no longer on your list.', textAlign: TextAlign.center),
                    ),
                  ])
                : f != null
                    ? _formFor(f, e.task)
                    : WmSheetFrame(title: e.task.title, tall: true, footer: _footer(e), children: _body(e)),
          );
        },
      );

  Widget _formFor(TaskForm f, WpTask t) => switch (f) {
        TaskForm.progress => NoteForm(
            key: const ValueKey('form-progress'),
            services: widget.services,
            taskTitle: t.title,
            draft: _draft(f),
            title: 'Report progress',
            label: 'What was done today?',
            submitLabel: 'Send progress',
            required: true,
            allowPhoto: true,
            onLeave: () => _show(null),
            onSubmit: (r) => _sendNote(f, t, r),
          ),
        TaskForm.done => NoteForm(
            key: const ValueKey('form-done'),
            services: widget.services,
            taskTitle: t.title,
            draft: _draft(f),
            title: 'Report done',
            label: 'Anything the office should know? (optional)',
            submitLabel: 'Report done',
            explain: 'The office checks the work before it counts as completed.',
            onLeave: () => _show(null),
            onSubmit: (r) => _sendNote(f, t, r),
          ),
        TaskForm.check => NoteForm(
            key: const ValueKey('form-check'),
            services: widget.services,
            taskTitle: t.title,
            draft: _draft(f),
            title: 'Check this work',
            label: 'Your note for the office (optional)',
            submitLabel: 'Mark as checked',
            explain: 'Your check is recorded. The office still gives the final approval.',
            onLeave: () => _show(null),
            onSubmit: (r) => _sendNote(f, t, r),
          ),
        TaskForm.problem => ProblemForm(
            key: const ValueKey('form-problem'),
            services: widget.services,
            task: t,
            draft: _draft(f),
            onMakeRequest: widget.onMakeRequest,
            onLeave: () => _show(null),
            onSubmit: (r) => _sendProblem(t, r),
          ),
      };

  List<Widget> _body(WpEntry e) {
    final t = e.task;
    final change = t.latestChange;
    return [
      Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        TaskPill(e),
        Text(
          [plannedLabel(t), roleLabel(t.myRole), if (t.teamName != null) 'Team ${t.teamName}', 'Version ${t.version}'].join(' · '),
          style: const TextStyle(color: WmColors.textMuted, fontSize: 13),
        ),
      ]),
      const SizedBox(height: 6),
      Text(t.where, style: const TextStyle(fontSize: 14, color: WmColors.textSecondary)),
      const SizedBox(height: 14),
      StepTracker(progress: progressOf(e)),
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
            actions: [noticeAction(dismissLabel, () => _c.dismissFailed(op))],
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
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in t.photos) _TaskPhoto(key: ValueKey(p.path), api: widget.services.api, path: p.path),
          ]),
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

  /// One main action, the reason it is locked or what happens next, then the
  /// two reports this person may make (Phase 2 spec §7).
  Widget? _footer(WpEntry e) {
    final t = e.task;
    final a = actionsFor(e);
    final s = e.effectiveStatus;
    WmSheetButton? main;
    String? note;
    var warn = false;
    if (a.acknowledge) {
      main = WmSheetButton(key: const Key('ack'), label: "I'VE READ THIS", icon: Icons.done_all, onPressed: () => _c.acknowledge(t));
      if (a.start && a.startLock == WpLock.mustRead) {
        note = lockText(WpLock.mustRead);
        warn = true;
      }
    } else if (a.start) {
      final lock = a.startLock;
      main = WmSheetButton(
        key: const Key('start'),
        label: 'START WORK',
        icon: Icons.play_arrow,
        onPressed: lock == null && !e.pending(WpOpKind.start) ? () => _c.startWork(t) : null,
      );
      if (lock != null) {
        note = lockText(lock);
        warn = true;
      }
    } else if (a.done) {
      final lock = a.doneLock;
      main = WmSheetButton(key: const Key('done'), label: 'REPORT DONE', icon: Icons.task_alt, onPressed: lock == null ? () => _show(TaskForm.done) : null);
      if (lock != null) {
        note = lockText(lock);
        warn = true;
      }
    } else if (a.check) {
      main = WmSheetButton(key: const Key('check'), label: 'CHECK THIS WORK', icon: Icons.fact_check, onPressed: () => _show(TaskForm.check));
    }
    if (note == null && (s == WpStatus.reportedDone || s == WpStatus.leaderChecked)) {
      note = 'The office checks the work before it counts as completed.';
    }
    if (note == null && s == WpStatus.completed) note = 'Completed.';
    final second = <Widget>[
      if (a.progress)
        _SecondButton(key: const Key('progress'), label: 'Report progress', icon: Icons.edit_note, danger: false, onTap: () => _show(TaskForm.progress)),
      if (a.problem)
        _SecondButton(key: const Key('problem'), label: 'Report a problem', icon: Icons.report_outlined, danger: true, onTap: () => _show(TaskForm.problem)),
    ];
    if (main == null && note == null && second.isEmpty) return null;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ?main,
      if (note != null) WmSheetNote(note, warning: warn),
      if (second.isNotEmpty)
        Padding(
          padding: EdgeInsets.only(top: main != null || note != null ? 10 : 0),
          child: Row(children: [
            for (var i = 0; i < second.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: second[i]),
            ],
          ]),
        ),
    ]);
  }
}

class _SecondButton extends StatelessWidget {
  const _SecondButton({super.key, required this.label, required this.icon, required this.danger, required this.onTap});

  final String label;
  final IconData icon;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: danger ? WmColors.danger : WmColors.green,
          backgroundColor: Colors.white,
          side: BorderSide(color: danger ? WmColors.dangerBorder : WmColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: 'Barlow', fontSize: 14.5, fontWeight: FontWeight.w800),
        ),
        icon: Icon(icon, size: 20),
        label: Text(label),
      );
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

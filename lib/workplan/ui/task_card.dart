import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../domain/wp_progress.dart';
import '../domain/wp_rules.dart';
import 'progress_widgets.dart';
import 'task_sheet.dart';
import 'workplan_copy.dart';
import 'workplan_widgets.dart';

/// The reports a swipe reveals for this person (Phase 2 spec §6).
List<TaskForm> swipeForms(WpEntry e) {
  final a = actionsFor(e);
  return [if (a.progress) TaskForm.progress, if (a.problem) TaskForm.problem];
}

bool canSwipe(WpEntry e) => swipeForms(e).isNotEmpty;

/// Let go past this (logical px to the left) and the buttons stay open.
const _snapOpen = 64.0;

/// One My Work card (spec §4.6 and §6): the task, its 4-part bar and Next
/// line. Swiping left reveals the reports this person may make; a button only
/// opens that form — nothing is ever sent from here. The screen decides which
/// card is open, one at a time.
class TaskCard extends StatefulWidget {
  const TaskCard({
    super.key,
    required this.entry,
    required this.today,
    required this.open,
    required this.onOpenChanged,
    required this.onTap,
    required this.onReport,
  });

  final WpEntry entry;

  /// Manila's calendar date ("2026-10-14"), for "Late".
  final String today;

  /// This card's buttons are showing.
  final bool open;
  final ValueChanged<bool> onOpenChanged;
  final VoidCallback onTap;

  /// A revealed button was tapped: open the task on that form.
  final ValueChanged<TaskForm> onReport;

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  /// The finger's offset while dragging; null when not dragging.
  double? _drag;

  List<TaskForm> get _forms => swipeForms(widget.entry);
  double get _max => _forms.isEmpty ? 0 : 6.0 + _forms.length * 76;
  double get _offset => _drag ?? (widget.open ? -_max : 0);

  void _update(DragUpdateDetails d) => setState(() => _drag = (_offset + d.delta.dx).clamp(-_max, 0).toDouble());

  void _end(DragEndDetails d) {
    final drag = _drag;
    if (drag == null) return;
    setState(() => _drag = null);
    final open = drag < -_snapOpen;
    if (open != widget.open) widget.onOpenChanged(open);
  }

  @override
  void didUpdateWidget(TaskCard old) {
    super.didUpdateWidget(old);
    // The task can no longer be swiped (e.g. approved mid-drag): its drag
    // handlers are gone, so the drag can never end — drop it.
    if (_drag != null && swipeForms(widget.entry).isEmpty) _drag = null;
  }

  void _tap() {
    if (widget.open) {
      widget.onOpenChanged(false);
      return;
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final t = e.task;
    final p = progressOf(e);
    final late = isLate(e, widget.today);
    final forms = _forms;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(children: [
          if (forms.isNotEmpty)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var i = 0; i < forms.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      _SwipeButton(
                        form: forms[i],
                        taskId: t.id,
                        onTap: () {
                          widget.onOpenChanged(false);
                          widget.onReport(forms[i]);
                        },
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          AnimatedContainer(
            duration: _drag == null ? const Duration(milliseconds: 220) : Duration.zero,
            curve: const Cubic(0.2, 0.8, 0.2, 1),
            transform: Matrix4.translationValues(_offset, 0, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: forms.isEmpty ? null : _update,
              onHorizontalDragEnd: forms.isEmpty ? null : _end,
              child: Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: (e.toRead || e.toCheck) ? WmColors.danger : WmColors.border),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _tap,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.25))),
                        const SizedBox(width: 8),
                        TaskPill(e),
                      ]),
                      const SizedBox(height: 4),
                      Text(t.where, style: const TextStyle(color: WmColors.textMuted, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(
                        '${plannedLabel(t)} · ${roleLabel(t.myRole)}${late ? ' · Late' : ''}',
                        style: TextStyle(
                          fontSize: 13,
                          color: late ? WmColors.danger : WmColors.textSecondary,
                          fontWeight: late ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TaskProgressBar(progress: p),
                      const SizedBox(height: 7),
                      Text(p.next, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: nextToneColor(p.tone))),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SwipeButton extends StatelessWidget {
  const _SwipeButton({required this.form, required this.taskId, required this.onTap});

  final TaskForm form;
  final String taskId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = form == TaskForm.progress;
    return SizedBox(
      width: 70,
      child: Material(
        key: Key(progress ? 'swipe-progress-$taskId' : 'swipe-problem-$taskId'),
        color: progress ? WmColors.greenTint : WmColors.dangerTint,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(progress ? Icons.edit_note : Icons.report_outlined, size: 22, color: progress ? WmColors.green : WmColors.danger),
            const SizedBox(height: 4),
            Text(progress ? 'Progress' : 'Problem',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: progress ? WmColors.green : WmColors.danger)),
          ]),
        ),
      ),
    );
  }
}

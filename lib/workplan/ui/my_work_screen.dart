import 'dart:async';

import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart';
import '../../attendance/ui/formats.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../domain/wp_rules.dart';
import '../workplan_services.dart';
import 'my_work_controller.dart';
import 'notes_sheet.dart';
import 'proposals_screen.dart';
import 'task_card.dart';
import 'task_openers.dart';
import 'task_sheet.dart';
import 'workplan_copy.dart';

/// The My Work tab (spec §12; redesign Phase 2): chips with counts, cards with
/// a 4-step bar and a Next line, a swipe-left shortcut to the reports, shared
/// meeting notes and — for a team leader — their own proposals.
class MyWorkScreen extends StatefulWidget {
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

  @override
  State<MyWorkScreen> createState() => _MyWorkScreenState();
}

const _chipLabels = {WpGroup.today: 'Today', WpGroup.upcoming: 'Upcoming', WpGroup.waiting: 'Waiting', WpGroup.done: 'Done'};

class _MyWorkScreenState extends State<MyWorkScreen> {
  WpGroup _chip = WpGroup.today;
  String? _openId;
  late bool _hintSeen = widget.services.hints?.swipeSeen ?? false;

  Future<void> _open(String taskId, {TaskForm? form}) =>
      openTask(context, widget.controller, widget.services, taskId, onMakeRequest: widget.onMakeRequest, form: form);

  void _openChanged(String id, bool open) {
    final first = open && !_hintSeen;
    setState(() {
      _openId = open ? id : (_openId == id ? null : _openId);
      if (open) _hintSeen = true;
    });
    if (first) unawaited(widget.services.hints?.markSwipeSeen() ?? Future<void>.value());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          final view = c.view;
          final failure = c.failure;
          final updates = c.updates;
          final rows = c.group(_chip);
          return RefreshIndicator(
            onRefresh: c.refresh,
            child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(20, 16, 20, 28), children: [
              const Text('My Work', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              const Text('Your tasks from the office. Read each one, then report as you work.',
                  style: TextStyle(fontSize: 14, color: WmColors.textMuted)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _PillButton(
                  key: const Key('open-notes'),
                  icon: Icons.forum_outlined,
                  label: 'Meeting notes (${view.notes.length})',
                  onTap: () => showNotesSheet(context, c),
                ),
                if (widget.isLeader)
                  _PillButton(
                    key: const Key('open-proposals'),
                    icon: Icons.lightbulb_outline,
                    label: 'My proposals',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProposalsScreen(controller: c))),
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
              if (view.entries.isNotEmpty) ...[
                const SizedBox(height: 4),
                SizedBox(
                  height: 38,
                  child: LayoutBuilder(
                    builder: (context, box) => OverflowBox(
                      maxWidth: box.maxWidth + 40,
                      minWidth: box.maxWidth + 40,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(children: [
                    for (final g in WpGroup.values) ...[
                      if (g != WpGroup.values.first) const SizedBox(width: 8),
                      _Chip(
                        key: Key('chip-${g.name}'),
                        label: _chipLabels[g]!,
                        count: c.group(g).length,
                        selected: g == _chip,
                        onTap: () => setState(() {
                          _chip = g;
                          _openId = null;
                        }),
                      ),
                    ],
                        ]),
                      ),
                    ),
                  ),
                ),
                if (!_hintSeen && rows.any(canSwipe))
                  const Padding(
                    key: Key('swipe-hint'),
                    padding: EdgeInsets.only(top: 12),
                    child: Row(children: [
                      Icon(Icons.swipe_left, size: 18, color: WmColors.textMuted),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text('Swipe a task left to report progress or a problem.',
                            style: TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
                      ),
                    ]),
                  ),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 32),
                    child: Text('No tasks here right now.', textAlign: TextAlign.center, style: TextStyle(color: WmColors.textMuted)),
                  ),
                for (final e in rows)
                  TaskCard(
                    key: Key('task-${e.task.id}'),
                    entry: e,
                    today: c.today,
                    open: _openId == e.task.id,
                    onOpenChanged: (o) => _openChanged(e.task.id, o),
                    onTap: () {
                      setState(() => _openId = null);
                      _open(e.task.id);
                    },
                    onReport: (f) => _open(e.task.id, form: f),
                  ),
              ],
            ]),
          );
        },
      );
}

class _PillButton extends StatelessWidget {
  const _PillButton({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: const StadiumBorder(side: BorderSide(color: WmColors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 20, color: WmColors.green),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: WmColors.green)),
            ]),
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.label, required this.count, required this.selected, required this.onTap});

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? WmColors.text : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: selected ? WmColors.text : WmColors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 38,
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: selected ? Colors.white : WmColors.textSecondary)),
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? const Color(0x33FFFFFF) : WmColors.inert,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text('$count',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, height: 1, color: selected ? Colors.white : WmColors.textSecondary)),
              ),
            ]),
          ),
        ),
      );
}

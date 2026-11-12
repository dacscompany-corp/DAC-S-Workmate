import 'dart:async';

import 'package:flutter/material.dart';

import '../../attendance/ui/formats.dart';
import '../../requests/domain/request_status.dart' show calendarDay;
import '../../ui/theme.dart';
import '../../ui/wm_sheet.dart';
import '../domain/wp_failure.dart';
import 'my_work_controller.dart';
import 'workplan_copy.dart';
import 'workplan_widgets.dart';

/// Shared meeting notes (spec §6) as a swipe-down sheet (redesign Phase 1):
/// the latest published version of each meeting this worker was chosen to
/// receive. Read-only; reading another team's plan gives no access to their
/// tasks. Opening it asks for a fresh copy (the sheet has no pull-down).
Future<void> showNotesSheet(BuildContext context, MyWorkController controller) {
  unawaited(controller.refresh());
  return showWmSheet<void>(context, builder: (_) => NotesSheet(controller: controller));
}

class NotesSheet extends StatelessWidget {
  const NotesSheet({super.key, required this.controller});

  final MyWorkController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final notes = controller.view.notes;
          final failure = controller.failure;
          final saved = controller.view.fetchedAt;
          return WmSheetFrame(title: 'Meeting notes', children: [
            if (failure != null && saved != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('No signal: showing what this phone saved on ${dayMonth(saved)}, ${clockTime(saved)}.',
                    style: const TextStyle(fontSize: 12.5, color: WmColors.brown)),
              ),
            if (notes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  failure != null && saved == null ? _unread(failure) : 'No meeting notes for you yet.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: WmColors.textMuted),
                ),
              ),
            for (final n in notes)
              WpBox(key: Key('note-${n.meetingId}'), children: [
                Text(n.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(
                  'Meeting ${calendarDay(n.heldOn)} · version ${n.version} · sent ${dayMonth(n.publishedAt)}, ${clockTime(n.publishedAt)}',
                  style: const TextStyle(color: WmColors.textMuted, fontSize: 13),
                ),
                if (n.changeNote.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('What changed: ${n.changeNote}', style: const TextStyle(color: WmColors.brown, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 8),
                Text(n.sharedNotes.isEmpty ? 'No notes in this version.' : n.sharedNotes, style: const TextStyle(fontSize: 15, height: 1.35)),
              ]),
          ]);
        },
      );
}

/// Nothing could be read: say why — never "no notes" (Phase 2 spec §9).
String _unread(WpFailure f) =>
    f == WpFailure.noConnection ? 'No signal right now. Open this again when there is signal.' : wpFailureCopy(f).english;

import 'package:flutter/material.dart';

import '../../attendance/ui/formats.dart';
import '../../requests/domain/request_status.dart' show calendarDay;
import '../../ui/theme.dart';
import 'my_work_controller.dart';
import 'workplan_widgets.dart';

/// Shared meeting notes (spec §6): the latest published version of each
/// meeting this worker was chosen to receive. Read-only; reading another
/// team's plan gives no access to their tasks.
class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key, required this.controller});

  final MyWorkController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Meeting notes')),
        body: SafeArea(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final notes = controller.view.notes;
              return RefreshIndicator(
                onRefresh: controller.refresh,
                child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
                  if (notes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 32),
                      child: Text('No meeting notes for you yet.', textAlign: TextAlign.center, style: TextStyle(color: WmColors.textMuted)),
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
                ]),
              );
            },
          ),
        ),
      );
}

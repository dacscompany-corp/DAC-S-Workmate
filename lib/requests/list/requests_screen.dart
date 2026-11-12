import 'package:flutter/material.dart';

import '../../attendance/domain/event_id.dart';
import '../../attendance/ui/attendance_copy.dart';
import '../../attendance/ui/formats.dart';
import '../../history/data/history_api.dart';
import '../../history/domain/history_models.dart';
import '../../history/ui/find_previous_screen.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../../ui/wm_chips.dart';
import '../data/requests_api.dart';
import '../domain/request_draft.dart';
import '../domain/request_status.dart';
import '../requests_services.dart';
import '../ui/request_stage.dart';
import '../ui/requests_copy.dart';
import '../ui/sync_chip.dart';
import 'request_openers.dart';
import 'requests_controller.dart';

/// The Requests tab (spec §5): create, edit and track requests. A leader also
/// sees the requests of the teams they currently lead, read-only.
class RequestsScreen extends StatelessWidget {
  const RequestsScreen({super.key, required this.controller, required this.services});

  final RequestsController controller;
  final RequestsServices services;

  /// Request Again from the tab (spec 1b §4.3 "standalone"): a new draft
  /// holding the picked item, opened on that item for quantity and date;
  /// the worker then chooses the project, work and team. Never sends.
  Future<void> _findPrevious(BuildContext context, HistoryApi history) async {
    // The filter lists; a slow signal must not hold the screen back.
    RequestReferences? refs;
    try {
      refs = await services.api.references().timeout(const Duration(seconds: 3));
    } catch (_) {}
    if (!context.mounted) return;
    final pick = await Navigator.of(context).push<HistoryPick>(MaterialPageRoute(
      builder: (_) => FindPreviousScreen(
        history: history,
        projects: historyProjects(refs?.destinations ?? const []),
        categories: historyCategories(refs?.catalog ?? const []),
      ),
    ));
    if (pick == null || !context.mounted) return;
    final line = DraftLine.fromHistory(newEventId(), pick);
    final draft = services.api.newDraft().copyWith(lines: [line]);
    try {
      await services.api.saveDraft(draft);
    } catch (_) {
      // Compose saves again on the first change.
    }
    if (context.mounted) await composeRequest(context, controller, services, draft, editLine: line.id);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          final rows = c.rows;
          final failure = c.failure;
          final view = c.view;
          return RefreshIndicator(
            onRefresh: c.refresh,
            child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(20, 16, 20, 28), children: [
              Row(children: [
                const Expanded(child: Text('Requests', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
                FilledButton.icon(
                  key: const Key('new-request'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => newRequest(context, controller, services),
                  icon: const Icon(Icons.add),
                  label: const Text('New request'),
                ),
              ]),
              const SizedBox(height: 2),
              const Text('Materials and tools for your projects.', style: TextStyle(fontSize: 14, color: WmColors.textMuted)),
              if (services.history case final history?) ...[
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: _FindPreviousButton(onPressed: () => _findPrevious(context, history))),
              ],
              const SizedBox(height: 12),
              if (failure != null) ...[
                if (view != null && view.fetchedAt != null)
                  Text(
                    'No signal: showing what this phone saved on ${dayMonth(view.fetchedAt!)}, ${clockTime(view.fetchedAt!)}. Pull down to try again.',
                    style: const TextStyle(fontSize: 12.5, color: WmColors.brown),
                  )
                else
                  FailureNotice(
                    english: requestFailureCopy(failure).english,
                    tagalog: requestFailureCopy(failure).tagalog,
                    actions: [noticeAction(retryLabel, c.refresh)],
                  ),
                const SizedBox(height: 12),
              ],
              WmChipRow(children: [
                for (final (f, label) in const [
                  (RequestFilter.all, 'All'),
                  (RequestFilter.drafts, 'Drafts'),
                  (RequestFilter.pending, 'Pending sync'),
                  (RequestFilter.attention, 'Needs attention'),
                ])
                  WmCountChip(key: Key('filter-${f.name}'), label: label, count: c.count(f), selected: c.filter == f, onTap: () => c.setFilter(f)),
              ]),
              const SizedBox(height: 12),
              if (c.loading && rows.isEmpty) const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator())),
              if (!c.loading && rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Text('Nothing here yet. Tap New request to ask for materials or tools.',
                      textAlign: TextAlign.center, style: TextStyle(color: WmColors.textMuted)),
                ),
              for (final e in rows) _EntryCard(key: Key('entry-${e.key}'), entry: e, onTap: () => openRequestEntry(context, controller, services, e)),
            ]),
          );
        },
      );
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({super.key, required this.entry, required this.onTap});
  final RequestEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = entry.remote;
    final d = entry.draft;
    final title = r?.title ?? d!.destination?.label ?? 'New request';
    final lines = r?.lines.length ?? d!.lines.length;
    final urgent = r != null ? r.lines.any((l) => l.urgent && !l.cancelled) : d!.lines.any((l) => l.urgent);
    final when = r?.receivedAt ?? d!.createdAt;
    final who = r != null && !r.mine ? 'From ${r.requesterName} · ' : '';
    final delivery = r == null ? null : nextDelivery([r], DateTime.now());
    final stage = stageOf(entry.state);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      // A white Material under the InkWell, so the tap ripple shows.
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: needsMe(entry) ? WmColors.danger : WmColors.border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.25))),
                const SizedBox(width: 8),
                SyncChip(entry.state),
              ]),
              const SizedBox(height: 4),
              Text('$who$lines item${lines == 1 ? '' : 's'} · ${dayMonth(when)}', style: const TextStyle(color: WmColors.textMuted, fontSize: 13)),
              const SizedBox(height: 12),
              RequestStageBar(stage),
              const SizedBox(height: 8),
              RequestStageLine(stage),
              if (urgent || delivery != null) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (urgent) const UrgentTag(),
                  if (delivery != null) Text('Next delivery ${calendarDay(delivery)}', style: const TextStyle(fontSize: 13, color: WmColors.green)),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Shows a spinner while the search flow is starting and ignores taps until
/// it ends, so a second tap cannot stack another search screen.
class _FindPreviousButton extends StatefulWidget {
  const _FindPreviousButton({required this.onPressed});

  final Future<void> Function() onPressed;

  @override
  State<_FindPreviousButton> createState() => _FindPreviousButtonState();
}

class _FindPreviousButtonState extends State<_FindPreviousButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => WmPillButton(
        key: const Key('find-previous'),
        icon: Icons.history,
        label: 'Find previous item',
        busy: _busy,
        onTap: _run,
      );
}

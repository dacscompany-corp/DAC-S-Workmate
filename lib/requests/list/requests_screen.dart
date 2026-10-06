import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart';
import '../../attendance/ui/formats.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../compose/compose_screen.dart';
import '../data/requests_api.dart';
import '../detail/request_detail_screen.dart';
import '../domain/request_draft.dart';
import '../domain/request_status.dart';
import '../requests_services.dart';
import '../ui/requests_copy.dart';
import '../ui/sync_chip.dart';
import 'requests_controller.dart';

/// The Requests tab (spec §5): create, edit and track requests. A leader also
/// sees the requests of the teams they currently lead, read-only.
class RequestsScreen extends StatelessWidget {
  const RequestsScreen({super.key, required this.controller, required this.services});

  final RequestsController controller;
  final RequestsServices services;

  Future<void> _compose(BuildContext context, RequestDraft draft) async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ComposeScreen(draft: draft, services: services)));
    await controller.refresh();
  }

  /// The draft is stored on its first change (ComposeController saves every
  /// change), so backing straight out leaves nothing behind.
  Future<void> _newRequest(BuildContext context) => _compose(context, services.api.newDraft());

  Future<void> _open(BuildContext context, RequestEntry e) async {
    if (e.state == SyncState.draft) return _compose(context, e.draft!);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (detailContext) => RequestDetailScreen(
        controller: controller,
        api: services.api,
        entryKey: e.key,
        onEditDraft: (draftId) async {
          final back = await controller.returnToDrafts(draftId);
          // Only a draft that is editable again: a queued one ignores every save.
          final e = controller.entry(draftId);
          final draft = e?.draft;
          if (!back || e?.state != SyncState.draft || draft == null || !detailContext.mounted || !context.mounted) return;
          Navigator.of(detailContext).pop();
          await _compose(context, draft);
        },
      ),
    ));
    await controller.refresh();
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
            child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
              Row(children: [
                const Expanded(child: Text('Requests', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
                FilledButton.icon(
                  key: const Key('new-request'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => _newRequest(context),
                  icon: const Icon(Icons.add),
                  label: const Text('New request'),
                ),
              ]),
              const SizedBox(height: 4),
              const Text('Materials and tools for your projects.', style: TextStyle(color: WmColors.textMuted)),
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
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final (f, label) in const [
                    (RequestFilter.all, 'All'),
                    (RequestFilter.drafts, 'Drafts'),
                    (RequestFilter.pending, 'Pending sync'),
                    (RequestFilter.attention, 'Needs attention'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(key: Key('filter-${f.name}'), label: Text(label), selected: c.filter == f, onSelected: (_) => c.setFilter(f)),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              if (c.loading && rows.isEmpty) const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator())),
              if (!c.loading && rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Text('Nothing here yet. Tap New request to ask for materials or tools.',
                      textAlign: TextAlign.center, style: TextStyle(color: WmColors.textMuted)),
                ),
              for (final e in rows) _EntryCard(key: Key('entry-${e.key}'), entry: e, onTap: () => _open(context, e)),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: WmColors.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              SyncChip(entry.state),
            ]),
            const SizedBox(height: 4),
            Text('$who$lines item${lines == 1 ? '' : 's'} · ${dayMonth(when)}', style: const TextStyle(color: WmColors.textMuted, fontSize: 13)),
            if (urgent || delivery != null) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                if (urgent) const UrgentTag(),
                if (delivery != null) Text('Next delivery ${calendarDay(delivery)}', style: const TextStyle(fontSize: 13, color: WmColors.green)),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

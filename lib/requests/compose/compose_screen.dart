import 'dart:async';

import 'package:flutter/material.dart';

import '../../attendance/domain/event_id.dart';
import '../../attendance/ui/attendance_copy.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../domain/quantity.dart';
import '../domain/request_draft.dart';
import '../domain/request_failure.dart';
import '../domain/request_models.dart';
import '../requests_services.dart';
import '../ui/requests_copy.dart';
import '../ui/sync_chip.dart';
import 'compose_controller.dart';
import 'item_editor_screen.dart';

/// New request (spec §4A): project → Main Contract or one Additional Works
/// job → one team for the whole request (or just me) → items. Pops true when
/// the request was queued.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, required this.draft, required this.services, this.now = DateTime.now});

  final RequestDraft draft;
  final RequestsServices services;
  final DateTime Function() now;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  late final ComposeController _c = ComposeController(api: widget.services.api, draft: widget.draft)..load();
  late final _note = TextEditingController(text: widget.draft.note);

  @override
  void dispose() {
    _c.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _chooseDestination() async {
    final refs = _c.refs;
    if (refs == null) return;
    final picked = await showModalBottomSheet<Destination>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 12), children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('Which project and work?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            for (final d in refs.destinations)
              ListTile(
                key: Key('dest-${d.workId}'),
                title: Text(d.projectName, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(d.workName),
                leading: Icon(d.isMain ? Icons.home_work_outlined : Icons.add_box_outlined),
                selected: d == _c.draft.destination,
                onTap: () => Navigator.of(context).pop(d),
              ),
          ]),
        ),
      ),
    );
    if (picked != null) await _c.setDestination(picked);
  }

  Future<void> _editLine(DraftLine line, {required bool isNew}) async {
    final refs = _c.refs;
    final result = await Navigator.of(context).push<ItemEdit>(MaterialPageRoute(
      builder: (_) => ItemEditorScreen(
        line: line,
        isNew: isNew,
        catalog: refs?.catalog ?? const [],
        team: _c.team,
        iLead: _c.iLead,
        draftId: _c.draft.id,
        services: widget.services,
        now: widget.now,
      ),
    ));
    // Backed out: the editor already deleted the photos it took.
    if (result == null) return;
    if (result.remove) {
      await _c.removeLine(line.id);
    } else {
      await _c.putLine(result.line!);
    }
  }

  /// Saved as typed. A failed save is quiet: the words stay in the field and
  /// in the draft being sent, and the next change saves them again.
  Future<void> _saveNote(String text) => _c.setNote(text).catchError((Object _) {});

  Future<void> _send() async {
    // Only a note that changed: Send on an untouched New request must not
    // store an empty draft.
    if (_note.text != _c.draft.note) await _saveNote(_note.text);
    if (await _c.send() && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _discard() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this draft?'),
        content: const Text('Its items and photos are removed from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (yes != true) return;
    await _c.discard();
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final d = _c.draft;
          final refs = _c.refs;
          final lineIssues = {for (final i in _c.issues) if (i.line != null) i.line!};
          return Scaffold(
              appBar: AppBar(
                title: const Text('New request'),
                actions: [
                  IconButton(key: const Key('draft-delete'), tooltip: 'Delete draft', icon: const Icon(Icons.delete_outline), onPressed: _discard),
                ],
              ),
              body: SafeArea(
                child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
                  if (_c.loading) const LinearProgressIndicator(),
                  if (refs == null && _c.refsFailure != null) ...[
                    FailureNotice(
                      english: requestFailureCopy(_c.refsFailure!).english,
                      tagalog: requestFailureCopy(_c.refsFailure!).tagalog,
                      actions: [noticeAction(retryLabel, _c.load)],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (refs != null && refs.fromCache) ...[
                    const _Note('No signal: using the lists saved on this phone. They are checked again when the request is sent.'),
                    const SizedBox(height: 12),
                  ],
                  const Text('PROJECT AND WORK', style: monoLabel),
                  const SizedBox(height: 6),
                  if (refs != null && refs.destinations.isEmpty && d.destination == null)
                    FailureNotice(english: noDestinationsCopy.english, tagalog: noDestinationsCopy.tagalog)
                  else
                    _Choice(
                      key: const Key('choose-destination'),
                      title: d.destination?.projectName ?? 'Choose the project',
                      subtitle: d.destination?.workName ?? 'Main Contract or an Additional Works job',
                      error: _c.issues.contains(const DraftIssue(DraftIssueKind.noDestination))
                          ? draftIssueText(DraftIssueKind.noDestination)
                          : null,
                      onTap: refs == null ? null : _chooseDestination,
                    ),
                  if (_c.destinationClosed) ...[
                    const SizedBox(height: 8),
                    FailureNotice(
                      english: requestFailureCopy(RequestFailure.destinationClosed).english,
                      tagalog: requestFailureCopy(RequestFailure.destinationClosed).tagalog,
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Text('TEAM', style: monoLabel),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    ChoiceChip(
                      key: const Key('team-none'),
                      label: const Text('Just me'),
                      selected: d.teamId == null,
                      onSelected: (_) => _c.setTeam(null),
                    ),
                    for (final t in refs?.teams ?? const <MyTeam>[])
                      ChoiceChip(
                        key: Key('team-${t.id}'),
                        label: Text(t.iLead ? '${t.name} (you lead)' : t.name),
                        selected: d.teamId == t.id,
                        onSelected: (_) => _c.setTeam(t),
                      ),
                  ]),
                  const SizedBox(height: 18),
                  Text('ITEMS (${d.lines.length})', style: monoLabel),
                  const SizedBox(height: 6),
                  for (var i = 0; i < d.lines.length; i++)
                    _LineCard(
                      key: Key('line-$i'),
                      line: d.lines[i],
                      hasIssue: lineIssues.contains(i),
                      onTap: () => _editLine(d.lines[i], isNew: false),
                    ),
                  if (_c.issues.contains(const DraftIssue(DraftIssueKind.noLines)))
                    Text(draftIssueText(DraftIssueKind.noLines), style: const TextStyle(color: WmColors.danger)),
                  if (_c.issues.contains(const DraftIssue(DraftIssueKind.tooManyLines)))
                    Text(draftIssueText(DraftIssueKind.tooManyLines), style: const TextStyle(color: WmColors.danger)),
                  OutlinedButton.icon(
                    key: const Key('add-item'),
                    onPressed: refs == null ? null : () => _editLine(DraftLine(id: newEventId()), isNew: true),
                    icon: const Icon(Icons.add),
                    label: const Text('Add item'),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    key: const Key('request-note'),
                    controller: _note,
                    maxLines: 2,
                    onChanged: (text) => unawaited(_saveNote(text)),
                    decoration: const InputDecoration(labelText: 'Note for the office (optional)'),
                  ),
                  const SizedBox(height: 18),
                  if (_c.sendFailure != null) ...[
                    FailureNotice(english: requestFailureCopy(_c.sendFailure!).english, tagalog: requestFailureCopy(_c.sendFailure!).tagalog),
                    const SizedBox(height: 12),
                  ],
                  FilledButton(
                    key: const Key('send-request'),
                    onPressed: _c.sending ? null : _send,
                    child: const Text('SEND REQUEST'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No signal? It is saved on this phone and sent as soon as there is signal.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: WmColors.textMuted),
                  ),
                ]),
              ),
            );
        },
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: WmColors.brownTint, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: const TextStyle(fontSize: 13, color: WmColors.brownDeep)),
      );
}

class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.title, required this.subtitle, required this.onTap, this.error});
  final String title;
  final String subtitle;
  final String? error;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: error == null ? WmColors.border : WmColors.danger),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(subtitle, style: const TextStyle(color: WmColors.textMuted)),
                if (error != null) Text(error!, style: const TextStyle(color: WmColors.danger, fontSize: 12.5)),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      );
}

class _LineCard extends StatelessWidget {
  const _LineCard({super.key, required this.line, required this.hasIssue, required this.onTap});
  final DraftLine line;
  final bool hasIssue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final qty = parseQuantity(line.quantity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: hasIssue ? WmColors.danger : WmColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(line.description.isEmpty ? 'Unnamed item' : line.description,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              Text(qty == null ? '—' : '${formatQuantity(qty)} ${line.unit}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            Text(
              [
                line.kind.label,
                if (line.spec.isNotEmpty) line.spec,
                if (!line.fromCatalog) 'Not in the list',
                if (line.memberName != null) 'For ${line.memberName}',
                if (line.photos.isNotEmpty) '${line.photos.length} photo${line.photos.length == 1 ? '' : 's'}',
              ].join(' · '),
              style: const TextStyle(color: WmColors.textMuted, fontSize: 13),
            ),
            if (line.urgent) ...[const SizedBox(height: 6), UrgentTag(neededBy: line.neededBy)],
            if (hasIssue) const Text('Check this item.', style: TextStyle(color: WmColors.danger, fontSize: 12.5)),
          ]),
        ),
      ),
    );
  }
}

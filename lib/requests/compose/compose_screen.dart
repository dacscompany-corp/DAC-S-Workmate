import 'dart:async';

import 'package:flutter/material.dart';

import '../../attendance/domain/event_id.dart';
import '../../attendance/ui/attendance_copy.dart';
import '../../history/data/history_api.dart';
import '../../history/domain/history_models.dart';
import '../../history/ui/find_previous_screen.dart';
import '../../history/ui/history_thumb.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../../ui/wm_chips.dart';
import '../../ui/wm_sheet.dart';
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
  const ComposeScreen({super.key, required this.draft, required this.services, this.editLineOnOpen, this.now = DateTime.now, this.resumed = false});

  final RequestDraft draft;
  final RequestsServices services;

  /// Opens this line's editor once the lists load: Request Again from the
  /// Requests tab lands on the quantity (spec 1b §4.3 "standalone").
  final String? editLineOnOpen;
  final DateTime Function() now;

  /// Reopened from its draft card: titled "Draft request" (spec §12).
  final bool resumed;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  late final ComposeController _c = ComposeController(api: widget.services.api, draft: widget.draft);
  late final _note = TextEditingController(text: widget.draft.note);
  late final _quickName = TextEditingController();
  late final _quickQty = TextEditingController();
  bool _pickingProject = false;

  @override
  void initState() {
    super.initState();
    unawaited(_c.load().then((_) => _openLineOnLoad()));
  }

  void _openLineOnLoad() {
    final id = widget.editLineOnOpen;
    if (id == null || !mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return; // the worker already opened something
    final line = _c.draft.lines.where((l) => l.id == id).firstOrNull;
    if (line != null) unawaited(_editLine(line, isNew: false));
  }

  @override
  void dispose() {
    _c.dispose();
    _note.dispose();
    _quickName.dispose();
    _quickQty.dispose();
    super.dispose();
  }

  Future<bool> _editLine(DraftLine line, {required bool isNew, String search = ''}) async {
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
        destinations: refs?.destinations ?? const [],
        now: widget.now,
        initialSearch: search,
      ),
    ));
    // Backed out: the editor already deleted the photos it took.
    if (result == null) return false;
    if (result.remove) {
      await _c.removeLine(line.id);
      return false;
    }
    await _c.putLine(result.line!);
    return true;
  }

  /// The quick-add row: + opens Add item with the typed name in its search
  /// and the quantity filled in; a saved item clears the two boxes.
  Future<void> _quickAdd() async {
    final line = DraftLine(id: newEventId(), quantity: _quickQty.text.trim());
    if (await _editLine(line, isNew: true, search: _quickName.text.trim()) && mounted) {
      _quickName.clear();
      _quickQty.clear();
    }
  }

  /// Find previous item from New request: the picked item opens in Add item
  /// as a new item of this draft.
  Future<void> _findPrevious(HistoryApi history) async {
    final refs = _c.refs;
    final pick = await Navigator.of(context).push<HistoryPick>(MaterialPageRoute(
      builder: (_) => FindPreviousScreen(
        history: history,
        now: widget.now,
        projects: historyProjects(refs?.destinations ?? const []),
        categories: historyCategories(refs?.catalog ?? const []),
      ),
    ));
    if (pick == null || !mounted) return;
    await _editLine(DraftLine.fromHistory(newEventId(), pick), isNew: true);
  }

  /// Saved as typed. A failed save is quiet: the words stay in the field and
  /// in the draft being sent, and the next change saves them again.
  Future<void> _saveNote(String text) => _c.setNote(text).catchError((Object _) {});

  Future<void> _send() async {
    if (_quickName.text.trim().isNotEmpty || _quickQty.text.trim().isNotEmpty) {
      await _quickAdd(); // the typed item is saved (or the worker backs out) before anything is sent
      return;
    }
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
          final hasItems = d.lines.isNotEmpty;
          final dests = refs?.destinations ?? [?d.destination];
          final history = widget.services.history;
          return WmSheetFrame(
            title: widget.resumed ? 'Draft request' : 'New request',
            tall: true,
            footer: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_c.sendFailure != null) ...[
                FailureNotice(english: requestFailureCopy(_c.sendFailure!).english, tagalog: requestFailureCopy(_c.sendFailure!).tagalog),
                const SizedBox(height: 12),
              ],
              WmSheetButton(
                key: const Key('send-request'),
                label: 'SEND REQUEST',
                icon: Icons.send,
                onPressed: _c.sending || !hasItems ? null : _send,
              ),
              WmSheetNote(hasItems ? 'Saved on this phone as you type. It is sent as soon as there is signal.' : 'Add at least one item.'),
            ]),
            children: [
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
              const SizedBox(height: 8),
              if (refs != null && refs.destinations.isEmpty && d.destination == null)
                FailureNotice(english: noDestinationsCopy.english, tagalog: noDestinationsCopy.tagalog)
              else
                for (final dest in dests)
                  if (d.destination == null || _pickingProject || dest == d.destination)
                    _DestCard(
                      key: Key('dest-${dest.workId}'),
                      dest: dest,
                      selected: dest == d.destination,
                      onTap: refs == null
                          ? null
                          : () {
                              unawaited(_c.setDestination(dest));
                              setState(() => _pickingProject = false);
                            },
                    ),
              if (d.destination != null && !_pickingProject && !(refs != null && refs.destinations.isEmpty))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('dest-change'),
                    onPressed: refs == null ? null : () => setState(() => _pickingProject = true),
                    child: const Text('Change'),
                  ),
                ),
              if (_c.issues.contains(const DraftIssue(DraftIssueKind.noDestination)))
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 4),
                  child: Text(draftIssueText(DraftIssueKind.noDestination), style: const TextStyle(color: WmColors.danger)),
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
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: [
                WmChoiceChip(
                  key: const Key('team-none'),
                  label: 'Just me',
                  selected: d.teamId == null,
                  onTap: () => _c.setTeam(null),
                ),
                for (final t in refs?.teams ?? const <MyTeam>[])
                  WmChoiceChip(
                    key: Key('team-${t.id}'),
                    label: t.iLead ? '${t.name} (you lead)' : t.name,
                    selected: d.teamId == t.id,
                    onTap: () => _c.setTeam(t),
                  ),
              ]),
              const SizedBox(height: 18),
              Text('ITEMS (${d.lines.length})', style: monoLabel),
              const SizedBox(height: 8),
              for (var i = 0; i < d.lines.length; i++)
                _LineCard(
                  key: Key('line-$i'),
                  line: d.lines[i],
                  history: widget.services.history,
                  hasIssue: lineIssues.contains(i),
                  onTap: () => _editLine(d.lines[i], isNew: false),
                ),
              if (_c.issues.contains(const DraftIssue(DraftIssueKind.noLines)))
                Text(draftIssueText(DraftIssueKind.noLines), style: const TextStyle(color: WmColors.danger)),
              if (_c.issues.contains(const DraftIssue(DraftIssueKind.tooManyLines)))
                Text(draftIssueText(DraftIssueKind.tooManyLines), style: const TextStyle(color: WmColors.danger)),
              _QuickAdd(name: _quickName, qty: _quickQty, onAdd: refs == null ? null : _quickAdd),
              if (history != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: WmPillButton(
                    key: const Key('compose-find-previous'),
                    icon: Icons.history,
                    label: 'Find previous item',
                    onTap: refs == null ? null : () => _findPrevious(history),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const Text('NOTE (OPTIONAL)', style: monoLabel),
              const SizedBox(height: 8),
              TextField(
                key: const Key('request-note'),
                controller: _note,
                minLines: 2,
                maxLines: 4,
                onChanged: (text) => unawaited(_saveNote(text)),
                decoration: const InputDecoration(hintText: 'Anything the office should know'),
              ),
              if (widget.resumed || d.destination != null || d.teamId != null || hasItems || d.note.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('draft-delete'),
                    onPressed: _discard,
                    style: TextButton.styleFrom(foregroundColor: WmColors.danger),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete draft'),
                  ),
                ),
              ],
            ],
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

class _LineCard extends StatelessWidget {
  const _LineCard({super.key, required this.line, required this.history, required this.hasIssue, required this.onTap});
  final DraftLine line;

  /// Shows a Find Previous Item line's cover photo, for recognition only:
  /// it is not one of the request's photos (spec 1b §4.3).
  final HistoryApi? history;
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
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (history != null && line.refCoverPath != null) ...[
              HistoryThumb(key: const Key('line-cover'), history: history!, path: line.refCoverPath, size: 44),
              const SizedBox(width: 10),
            ],
            Expanded(
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
          ]),
        ),
      ),
    );
  }
}

/// One project and work, chosen in place (spec §12): green when chosen.
class _DestCard extends StatelessWidget {
  const _DestCard({super.key, required this.dest, required this.selected, required this.onTap});

  final Destination dest;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(
          button: true,
          enabled: onTap != null,
          selected: selected,
          child: Material(
            color: selected ? WmColors.greenTint : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: selected ? WmColors.green : WmColors.border, width: selected ? 1.5 : 1),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(children: [
                  Icon(dest.isMain ? Icons.home_work_outlined : Icons.add_box_outlined, size: 22, color: selected ? WmColors.green : WmColors.textMuted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(dest.projectName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      Text(dest.workName, style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
                    ]),
                  ),
                  if (selected) const Icon(Icons.check_circle, size: 22, color: WmColors.green),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// Item name · Qty · + (spec §12). + opens Add item filled in; nothing is
/// added to the request until Add item is saved.
class _QuickAdd extends StatelessWidget {
  const _QuickAdd({required this.name, required this.qty, required this.onAdd});

  final TextEditingController name;
  final TextEditingController qty;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              key: const Key('quick-name'),
              controller: name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'Item name'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 84,
            child: TextField(
              key: const Key('quick-qty'),
              controller: qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onAdd?.call(),
              decoration: const InputDecoration(hintText: 'Qty'),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            enabled: onAdd != null,
            label: 'Add item',
            child: SizedBox(
              width: 48,
              height: 48,
              child: Material(
                key: const Key('add-item'),
                color: onAdd == null ? WmColors.textDisabled : WmColors.green,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onAdd,
                  child: const Icon(Icons.add, color: Colors.white, size: 26),
                ),
              ),
            ),
          ),
        ]),
      );
}

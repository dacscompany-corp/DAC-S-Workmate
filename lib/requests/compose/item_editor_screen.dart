import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../domain/quantity.dart';
import '../domain/request_draft.dart';
import '../domain/request_models.dart';
import '../domain/request_status.dart';
import '../requests_services.dart';
import '../ui/requests_copy.dart';

/// Up to this many photos per item: enough to show the part, small enough
/// to send on a weak site connection.
const maxPhotosPerItem = 3;

/// The answer of the item editor: the edited line, or a request to remove it.
class ItemEdit {
  const ItemEdit.save(DraftLine this.line) : remove = false;
  const ItemEdit.remove()
      : line = null,
        remove = true;
  final DraftLine? line;
  final bool remove;
}

/// One item: pick it from the office's list, or describe it when it is
/// missing (spec §4A: the request still goes through; the office matches it).
class ItemEditorScreen extends StatefulWidget {
  const ItemEditorScreen({
    super.key,
    required this.line,
    required this.isNew,
    required this.catalog,
    required this.team,
    required this.iLead,
    required this.draftId,
    required this.services,
    this.now = DateTime.now,
  });

  final DraftLine line;
  final bool isNew;
  final List<CatalogItem> catalog;

  /// The request's team (null for an individual request).
  final MyTeam? team;
  final bool iLead;
  final String draftId;
  final RequestsServices services;
  final DateTime Function() now;

  @override
  State<ItemEditorScreen> createState() => _ItemEditorScreenState();
}

class _ItemEditorScreenState extends State<ItemEditorScreen> {
  late DraftLine _line = _withoutLostMember(widget.line);
  late final _search = TextEditingController();
  late final _description = TextEditingController(text: widget.line.description);
  late final _spec = TextEditingController(text: widget.line.spec);
  late final _unit = TextEditingController(text: widget.line.unit);
  late final _category = TextEditingController(text: widget.line.category);
  late final _quantity = TextEditingController(text: widget.line.quantity);
  late final _reason = TextEditingController(text: widget.line.urgentReason);
  late final _notes = TextEditingController(text: widget.line.notes);
  late bool _describing = !widget.line.fromCatalog && widget.line.description.isNotEmpty;
  bool _tried = false;
  bool _addingPhoto = false;

  /// Photos taken in THIS editing session: deleted unless the item is saved.
  final _added = <String>[];

  /// Photos of the saved item removed here: deleted only when it is saved.
  final _removed = <String>[];
  bool _saved = false;

  @override
  void dispose() {
    if (!_saved) {
      // Backed out or removed the item: nothing taken in this session is kept.
      for (final p in _added) {
        unawaited(widget.services.api.discardPhoto(p));
      }
    }
    for (final c in [_search, _description, _spec, _unit, _category, _quantity, _reason, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// A member no longer in the team the worker leads opens as "The team": the
  /// screen shows what is saved, and the server would refuse BAD_MEMBER.
  DraftLine _withoutLostMember(DraftLine l) {
    final team = widget.team;
    if (l.memberId == null || team == null || !widget.iLead || team.members.any((m) => m.id == l.memberId)) return l;
    return l.copyWith(memberId: null, memberName: null);
  }

  /// Asks first: removing an item deletes its photos for good.
  Future<void> _remove() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(removeItemTitle.english),
          Text(removeItemTitle.tagalog, style: const TextStyle(fontSize: 14, color: WmColors.textMuted)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(removeItemBody.english),
          Text(removeItemBody.tagalog, style: const TextStyle(color: WmColors.textMuted)),
        ]),
        actions: [
          TextButton(key: const Key('item-remove-keep'), onPressed: () => Navigator.of(context).pop(false), child: const Text(keepItemLabel)),
          TextButton(key: const Key('item-remove-confirm'), onPressed: () => Navigator.of(context).pop(true), child: const Text(removeItemLabel)),
        ],
      ),
    );
    if (yes == true && mounted) Navigator.of(context).pop(const ItemEdit.remove());
  }

  DraftLine get _current => _line.copyWith(
        description: _description.text,
        spec: _spec.text,
        unit: _unit.text,
        category: _category.text,
        quantity: _quantity.text,
        urgentReason: _reason.text,
        notes: _notes.text,
      );

  List<DraftIssueKind> get _problems {
    final l = _current;
    return [
      if (l.description.trim().isEmpty) DraftIssueKind.noDescription,
      if (l.unit.trim().isEmpty) DraftIssueKind.noUnit,
      if (parseQuantity(l.quantity) == null) DraftIssueKind.badQuantity,
      if (l.urgent && l.urgentReason.trim().isEmpty) DraftIssueKind.urgentNeedsReason,
      if (l.urgent && l.neededBy == null) DraftIssueKind.urgentNeedsDate,
    ];
  }

  void _pick(CatalogItem item) {
    final picked = DraftLine.fromCatalog(_line.id, item);
    setState(() {
      _line = _current.copyWith(
        kind: picked.kind,
        catalogItemId: picked.catalogItemId,
        description: picked.description,
        spec: picked.spec,
        unit: picked.unit,
        category: picked.category,
        // A tool's responsible person is named at issue, not here (spec §4A).
        memberId: picked.kind == ItemKind.tool ? null : _line.memberId,
        memberName: picked.kind == ItemKind.tool ? null : _line.memberName,
      );
      _description.text = picked.description;
      _spec.text = picked.spec;
      _unit.text = picked.unit;
      _category.text = picked.category;
      _describing = false;
    });
  }

  /// The picked item's words go with it: a different kind or a new search
  /// starts from empty fields, never from hidden ones.
  void _clearItemFields() {
    for (final c in [_description, _spec, _unit, _category]) {
      c.clear();
    }
    _line = _line.copyWith(description: '', spec: '', unit: '', category: '');
  }

  /// Back to the list to pick another item.
  void _unpick() => setState(() {
        _line = _current.copyWith(catalogItemId: null);
        _clearItemFields();
        _describing = false;
      });

  Future<void> _pickDate() async {
    final now = widget.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      initialDate: DateTime(now.year, now.month, now.day),
    );
    if (picked == null) return;
    final iso = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    setState(() => _line = _current.copyWith(neededBy: iso));
  }

  Future<void> _addPhoto() async {
    setState(() => _addingPhoto = true);
    try {
      final raw = await widget.services.takePhoto(context);
      if (raw == null) return;
      final kept = await widget.services.api.keepPhoto(widget.draftId, raw);
      if (!mounted) {
        await widget.services.api.discardPhoto(kept);
        return;
      }
      _added.add(kept);
      setState(() => _line = _current.copyWith(photos: [..._line.photos, kept]));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(photoNotKeptCopy.english, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(photoNotKeptCopy.tagalog),
          ]),
        ));
      }
    } finally {
      if (mounted) setState(() => _addingPhoto = false);
    }
  }

  void _removePhoto(String path) {
    if (_added.remove(path)) {
      unawaited(widget.services.api.discardPhoto(path));
    } else {
      _removed.add(path);
    }
    setState(() => _line = _current.copyWith(photos: _line.photos.where((p) => p != path).toList()));
  }

  void _save() {
    setState(() => _tried = true);
    if (_problems.isNotEmpty) return;
    for (final p in _removed) {
      unawaited(widget.services.api.discardPhoto(p));
    }
    _saved = true;
    Navigator.of(context).pop(ItemEdit.save(_current));
  }

  @override
  Widget build(BuildContext context) {
    final kind = _line.kind;
    final q = _search.text.trim().toLowerCase();
    final matches = widget.catalog
        .where((c) => c.kind == kind && (q.isEmpty || '${c.name} ${c.spec} ${c.category}'.toLowerCase().contains(q)))
        .take(30)
        .toList();
    final showMember = kind == ItemKind.material && widget.team != null && widget.iLead;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'Add item' : 'Edit item'),
        actions: [
          if (!widget.isNew)
            IconButton(
              key: const Key('item-remove'),
              tooltip: 'Remove item',
              icon: const Icon(Icons.delete_outline),
              onPressed: _remove,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
          SegmentedButton<ItemKind>(
            segments: [for (final k in ItemKind.values) ButtonSegment(value: k, label: Text(k.label))],
            selected: {kind},
            onSelectionChanged: (s) => setState(() {
              final wasPicked = _line.fromCatalog;
              _line = _current.copyWith(
                kind: s.first,
                catalogItemId: null,
                memberId: s.first == ItemKind.tool ? null : _line.memberId,
                memberName: s.first == ItemKind.tool ? null : _line.memberName,
              );
              if (wasPicked) _clearItemFields();
            }),
          ),
          const SizedBox(height: 16),
          if (_line.fromCatalog) ...[
            _Picked(line: _current, onChange: _unpick),
          ] else if (!_describing) ...[
            TextField(
              key: const Key('item-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Find it in the list', prefixIcon: Icon(Icons.search)),
            ),
            const SizedBox(height: 8),
            for (final c in matches)
              ListTile(
                key: Key('catalog-${c.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([if (c.spec.isNotEmpty) c.spec, c.unit, if (c.category.isNotEmpty) c.category].join(' · ')),
                onTap: () => _pick(c),
              ),
            if (matches.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nothing in the list matches.')),
            TextButton.icon(
              key: const Key('describe-item'),
              onPressed: () => setState(() {
                _describing = true;
                if (_description.text.isEmpty) _description.text = _search.text.trim();
              }),
              icon: const Icon(Icons.edit_note),
              label: const Text('Not in the list? Describe it'),
            ),
          ] else ...[
            const Text('Describe the item. The office will match it to the list.',
                style: TextStyle(color: WmColors.textMuted, fontSize: 13)),
            const SizedBox(height: 10),
            _field(_description, 'Item name', 'item-name', error: _error(DraftIssueKind.noDescription)),
            _field(_spec, 'Size / type (optional)', 'item-spec'),
            _field(_unit, 'Unit (pc, bag, m…)', 'item-unit', error: _error(DraftIssueKind.noUnit)),
            _field(_category, 'Trade (optional, e.g. plumbing)', 'item-category'),
            if (widget.catalog.isNotEmpty)
              TextButton(onPressed: () => setState(() => _describing = false), child: const Text('Pick from the list instead')),
          ],
          const SizedBox(height: 8),
          _field(_quantity, 'Quantity${_unit.text.trim().isEmpty ? '' : ' (${_unit.text.trim()})'}', 'item-quantity',
              keyboard: const TextInputType.numberWithOptions(decimal: true), error: _error(DraftIssueKind.badQuantity)),
          if (showMember)
            DropdownButtonFormField<String?>(
              key: const Key('item-member'),
              // Never a value missing from the items (a debug assert).
              initialValue: widget.team!.members.any((m) => m.id == _line.memberId) ? _line.memberId : null,
              decoration: const InputDecoration(labelText: 'For (optional)'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('The team')),
                for (final m in widget.team!.members) DropdownMenuItem<String?>(value: m.id, child: Text(m.name)),
              ],
              onChanged: (id) => setState(() => _line = _current.copyWith(
                    memberId: id,
                    memberName: widget.team!.members.where((m) => m.id == id).firstOrNull?.name,
                  )),
            ),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const Key('item-urgent'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Urgent', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Goes to the office at once, without waiting for the weekly batch.'),
            value: _line.urgent,
            onChanged: (v) => setState(() => _line = _current.copyWith(urgent: v)),
          ),
          if (_line.urgent) ...[
            _field(_reason, 'Why is it urgent?', 'item-reason', error: _error(DraftIssueKind.urgentNeedsReason)),
            ListTile(
              key: const Key('item-needed-by'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(_line.neededBy == null ? 'Needed by…' : 'Needed by ${calendarDay(_line.neededBy!)}'),
              subtitle: _error(DraftIssueKind.urgentNeedsDate) == null
                  ? null
                  : Text(_error(DraftIssueKind.urgentNeedsDate)!, style: const TextStyle(color: WmColors.danger)),
              onTap: _pickDate,
            ),
          ],
          _field(_notes, 'Notes (optional)', 'item-notes'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in _line.photos)
              Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(File(p), width: 84, height: 84, fit: BoxFit.cover, errorBuilder: (_, _, _) => _photoGap()),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: IconButton(
                    tooltip: 'Remove photo',
                    icon: const Icon(Icons.close, color: Colors.white),
                    style: IconButton.styleFrom(backgroundColor: Colors.black54),
                    onPressed: () => _removePhoto(p),
                  ),
                ),
              ]),
            if (_line.photos.length < maxPhotosPerItem)
              OutlinedButton.icon(
                key: const Key('item-add-photo'),
                onPressed: _addingPhoto ? null : _addPhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Add photo'),
              ),
          ]),
          const SizedBox(height: 20),
          FilledButton(key: const Key('item-save'), onPressed: _save, child: const Text('SAVE ITEM')),
        ]),
      ),
    );
  }

  String? _error(DraftIssueKind k) => _tried && _problems.contains(k) ? draftIssueText(k) : null;

  Widget _field(TextEditingController c, String label, String key, {TextInputType? keyboard, String? error}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          key: Key(key),
          controller: c,
          keyboardType: keyboard,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: label, errorText: error),
        ),
      );

  Widget _photoGap() => Container(width: 84, height: 84, color: WmColors.inert, child: const Icon(Icons.broken_image_outlined));
}

class _Picked extends StatelessWidget {
  const _Picked({required this.line, required this.onChange});
  final DraftLine line;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: WmColors.greenTint, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.inventory_2_outlined, color: WmColors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(line.description, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text([if (line.spec.isNotEmpty) line.spec, line.unit].join(' · '), style: const TextStyle(color: WmColors.textMuted)),
            ]),
          ),
          TextButton(key: const Key('item-change'), onPressed: onChange, child: const Text('Change')),
        ]),
      );
}

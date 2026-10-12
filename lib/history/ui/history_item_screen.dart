import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart';
import '../../attendance/ui/formats.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../data/history_api.dart';
import '../domain/history_failure.dart';
import '../domain/history_models.dart';
import 'history_copy.dart';
import 'history_thumb.dart';

/// One item: its approved photos and its dated history (spec 1b §4.3).
/// Pops a [HistoryPick] when the worker taps Request again. Never shows
/// who asked, request notes, prices or "in stock".
class HistoryItemScreen extends StatefulWidget {
  const HistoryItemScreen({super.key, required this.history, required this.itemId});

  final HistoryApi history;
  final String itemId;

  @override
  State<HistoryItemScreen> createState() => _HistoryItemScreenState();
}

class _HistoryItemScreenState extends State<HistoryItemScreen> {
  HistoryItemView? _view;
  HistoryFailure? _failure;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final v = await widget.history.item(widget.itemId);
      if (mounted) setState(() => _view = v);
    } catch (e) {
      if (mounted) setState(() => _failure = HistoryFailure.of(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _again(HistoryItem item, HistoryEntry entry) => Navigator.of(context).pop(HistoryPick.of(item, entry));

  @override
  Widget build(BuildContext context) {
    final v = _view;
    return Scaffold(
      appBar: AppBar(title: const Text('Item history')),
      body: SafeArea(
        child: _loading && v == null
            ? const Center(child: CircularProgressIndicator())
            : v == null
                ? ListView(padding: const EdgeInsets.all(20), children: [
                    FailureNotice(
                      key: const Key('history-item-failure'),
                      english: historyFailureCopy(_failure ?? HistoryFailure.unexpected).english,
                      tagalog: historyFailureCopy(_failure ?? HistoryFailure.unexpected).tagalog,
                      actions: [noticeAction(retryLabel, _load)],
                    ),
                  ])
                : _body(v),
      ),
    );
  }

  Widget _body(HistoryItemView v) {
    final item = v.item;
    final details = [if (item.spec.isNotEmpty) item.spec, item.unit, if (item.brand.isNotEmpty) item.brand, if (item.category.isNotEmpty) item.category];
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
      if (v.fromSaved)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(savedBanner('${dayMonth(v.savedAt!)}, ${clockTime(v.savedAt!)}'),
              key: const Key('history-item-saved'), style: const TextStyle(fontSize: 12.5, color: WmColors.brown)),
        ),
      SizedBox(
        height: 220,
        child: item.photos.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  HistoryThumb(history: widget.history, path: null, size: 96),
                  const SizedBox(height: 6),
                  const Text(noPhotoText, style: TextStyle(color: WmColors.textMuted)),
                ]),
              )
            : PageView(
                key: const Key('history-photos'),
                children: [
                  for (var i = 0; i < item.photos.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: LayoutBuilder(
                        builder: (context, box) => HistoryThumb(
                          key: Key('history-photo-$i'),
                          history: widget.history,
                          path: item.photos[i].path,
                          size: box.maxWidth,
                          height: 220,
                        ),
                      ),
                    ),
                ],
              ),
      ),
      if (item.photos.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('${item.photos.length} photos — swipe', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: WmColors.textMuted)),
        ),
      const SizedBox(height: 14),
      Text(item.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      Text(details.join(' · '), style: const TextStyle(color: WmColors.textMuted)),
      if (item.aliases.isNotEmpty) Text('Also called: ${item.aliases.join(', ')}', style: const TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
      const SizedBox(height: 14),
      if (!item.active)
        Container(
          key: const Key('history-not-listed'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: WmColors.brownTint, borderRadius: BorderRadius.circular(14)),
          child: const Text(notListedTitle, style: TextStyle(fontWeight: FontWeight.w700, color: WmColors.brownDeep)),
        )
      else if (item.entries.isNotEmpty)
        FilledButton.icon(
          key: const Key('history-request-again'),
          onPressed: () => _again(item, item.entries.first),
          icon: const Icon(Icons.replay),
          label: const Text(requestAgainLabel),
        ),
      const SizedBox(height: 18),
      const Text('History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      for (final e in item.entries) _EntryCard(entry: e, onAgain: item.active ? () => _again(item, e) : null),
    ]);
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.onAgain});
  final HistoryEntry entry;
  final VoidCallback? onAgain;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final cancelled = e.label != 'Requested' && e.entryKind == 'request_line';
    final qty = e.quantity == null ? null : '${_qty(e.quantity!)} ${e.unit ?? ''}'.trim();
    final words = [e.description, e.note].whereType<String>().where((s) => s.trim().isNotEmpty).join(' — ');
    return Container(
      key: Key('history-entry-${e.entryId}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: WmColors.border)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.label,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cancelled ? WmColors.textMuted : (e.entryKind == 'reference' ? WmColors.brown : WmColors.green))),
            Text(historyWhere(e.projectName, e.workName)),
            Text([historyDateLabel(e.date, e.datePrecision), ?qty].join(' · '), style: const TextStyle(color: WmColors.textMuted)),
            if (words.isNotEmpty) Text(words, style: const TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
          ]),
        ),
        if (onAgain != null)
          TextButton(key: Key('history-again-${e.entryId}'), onPressed: onAgain, child: const Text(requestAgainShort)),
      ]),
    );
  }

  static String _qty(double q) => q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toString();
}

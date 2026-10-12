import 'dart:async';

import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart';
import '../../attendance/ui/formats.dart';
import '../../requests/domain/request_models.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../data/history_api.dart';
import '../domain/history_failure.dart';
import '../domain/history_models.dart';
import 'history_copy.dart';
import 'history_item_screen.dart';
import 'history_thumb.dart';

/// The project filter: the worker's own projects, from the Requests list.
Map<String, String> historyProjects(List<Destination> destinations) => {for (final d in destinations) d.projectId: d.projectName};

/// The category filter: the catalogue's categories, sorted.
List<String> historyCategories(List<CatalogItem> catalog) =>
    {for (final c in catalog) if (c.category.trim().isNotEmpty) c.category.trim()}.toList()..sort();

/// The date filter, as finger-sized presets (spec 1b §4.3 "a date filter").
enum HistoryPeriod {
  any('Any time', null),
  month('Last 30 days', 30),
  quarter('Last 3 months', 91),
  year('Last 12 months', 365);

  const HistoryPeriod(this.label, this.days);
  final String label;
  final int? days;

  /// The local date [days] before [today], as yyyy-mm-dd — built from local
  /// parts, never toISOString (PH is UTC+8).
  String? fromKey(DateTime today) {
    final d = days;
    if (d == null) return null;
    final t = DateTime(today.year, today.month, today.day).subtract(Duration(days: d));
    return '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}

/// Find Previous Item: search what this worker's projects used before.
/// Pops a [HistoryPick] when the worker chooses Request again.
class FindPreviousScreen extends StatefulWidget {
  const FindPreviousScreen({
    super.key,
    required this.history,
    this.projects = const {},
    this.categories = const [],
    this.now = DateTime.now,
  });

  final HistoryApi history;

  /// Project id → name, for the project filter (the worker's own projects).
  final Map<String, String> projects;
  final List<String> categories;
  final DateTime Function() now;

  @override
  State<FindPreviousScreen> createState() => _FindPreviousScreenState();
}

class _FindPreviousScreenState extends State<FindPreviousScreen> {
  final _text = TextEditingController();
  Timer? _debounce;
  var _query = const HistoryQuery();
  var _period = HistoryPeriod.any;
  final _items = <HistoryCard>[];
  bool _hasMore = false;
  DateTime? _savedAt;
  HistoryFailure? _failure;
  bool _loading = true;
  bool _loadingMore = false;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    // Drop saved items the worker may no longer see; never blocks the search.
    unawaited(widget.history.refreshSaved().catchError((Object e) => debugPrint('History cleanup failed: $e')));
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final ask = ++_asked;
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final page = await widget.history.search(_query);
      if (!mounted || ask != _asked) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _hasMore = page.hasMore;
        _savedAt = page.savedAt;
      });
    } catch (e) {
      if (!mounted || ask != _asked) return;
      setState(() {
        _items.clear();
        _hasMore = false;
        _failure = HistoryFailure.of(e);
      });
    } finally {
      if (mounted && ask == _asked) setState(() => _loading = false);
    }
  }

  Future<void> _more() async {
    final ask = _asked;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.history.search(_query, offset: _items.length);
      if (!mounted || ask != _asked) return;
      setState(() {
        _items.addAll(page.items);
        _hasMore = page.hasMore;
      });
    } catch (e) {
      // Keep what is shown and say so; the button stays for another try.
      if (mounted && ask == _asked) {
        final copy = historyFailureCopy(HistoryFailure.of(e));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          key: const Key('history-more-failed'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(copy.english, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(copy.tagalog),
          ]),
        ));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _set(HistoryQuery q) {
    _query = q;
    _search();
  }

  void _typed(String s) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _set(_query.copyWith(text: s)));
  }

  void _setPeriod(HistoryPeriod p) {
    _period = p;
    _set(_query.copyWith(from: p.fromKey(widget.now())));
  }

  Future<void> _open(HistoryCard card) async {
    final pick = await Navigator.of(context).push<HistoryPick>(
      MaterialPageRoute(builder: (_) => HistoryItemScreen(history: widget.history, itemId: card.id)),
    );
    if (pick != null && mounted) Navigator.of(context).pop(pick);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(findPreviousTitle)),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          TextField(
            key: const Key('history-search'),
            controller: _text,
            onChanged: _typed,
            onSubmitted: (s) {
              _debounce?.cancel();
              _set(_query.copyWith(text: s));
            },
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Name, size, brand…'),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
              key: const Key('history-kind-all'),
              label: const Text('All'),
              selected: _query.kind == null,
              onSelected: (_) => _set(_query.copyWith(kind: null)),
            ),
            for (final k in ItemKind.values)
              ChoiceChip(
                key: Key('history-kind-${k.wire}'),
                label: Text(k.label),
                selected: _query.kind == k,
                onSelected: (_) => _set(_query.copyWith(kind: k)),
              ),
          ]),
          const SizedBox(height: 10),
          if (widget.projects.length > 1)
            DropdownButtonFormField<String?>(
              key: const Key('history-project'),
              initialValue: _query.projectId,
              decoration: const InputDecoration(labelText: 'Project'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All my projects')),
                for (final p in widget.projects.entries) DropdownMenuItem(value: p.key, child: Text(p.value)),
              ],
              onChanged: (id) => _set(_query.copyWith(projectId: id)),
            ),
          if (widget.categories.isNotEmpty) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              key: const Key('history-category'),
              initialValue: _query.category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All categories')),
                for (final c in widget.categories) DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (c) => _set(_query.copyWith(category: c)),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in HistoryPeriod.values)
              ChoiceChip(
                key: Key('history-period-${p.name}'),
                label: Text(p.label),
                selected: _period == p,
                onSelected: (_) => _setPeriod(p),
              ),
          ]),
          const SizedBox(height: 14),
          ..._results(),
        ]),
      ),
    );
  }

  List<Widget> _results() {
    if (_loading && _items.isEmpty) {
      return const [Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))];
    }
    final f = _failure;
    if (f != null) {
      final copy = historyFailureCopy(f);
      return [
        FailureNotice(
          key: const Key('history-failure'),
          english: copy.english,
          tagalog: copy.tagalog,
          actions: [noticeAction(retryLabel, _search)],
        ),
      ];
    }
    final saved = _savedAt;
    return [
      // A refined search is running over the old results: show it, and keep
      // Show more off until the new first page is in.
      if (_loading) const LinearProgressIndicator(key: Key('history-refreshing')),
      if (saved != null)
        Container(
          key: const Key('history-saved-banner'),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: WmColors.brownTint, borderRadius: BorderRadius.circular(12)),
          child: Text(savedBanner('${dayMonth(saved)}, ${clockTime(saved)}'),
              style: const TextStyle(fontSize: 12.5, color: WmColors.brownDeep)),
        ),
      if (_items.isEmpty)
        const Padding(
          key: Key('history-empty'),
          padding: EdgeInsets.all(24),
          child: Text(noMatchesText, textAlign: TextAlign.center, style: TextStyle(color: WmColors.textMuted)),
        ),
      for (final c in _items) _Card(card: c, history: widget.history, onTap: () => _open(c)),
      if (_hasMore)
        OutlinedButton(
          key: const Key('history-more'),
          onPressed: _loading || _loadingMore ? null : _more,
          child: Text(_loadingMore ? 'Loading…' : 'SHOW MORE'),
        ),
    ];
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.card, required this.history, required this.onTap});
  final HistoryCard card;
  final HistoryApi history;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = card;
    final sub = [if (c.spec.isNotEmpty) c.spec, c.unit, if (c.brand.isNotEmpty) c.brand].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: Key('history-card-${c.id}'),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: WmColors.border)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              HistoryThumb(history: history, path: c.coverPath),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(sub, style: const TextStyle(color: WmColors.textMuted)),
                  if (c.latest != null)
                    Text(c.latest!.summary, style: const TextStyle(fontSize: 12.5, color: WmColors.textSecondary)),
                  if (!c.active)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('No longer listed', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: WmColors.brown)),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

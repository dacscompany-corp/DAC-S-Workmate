import 'dart:async';

import 'package:flutter/material.dart';

import '../../auth/worker_profile.dart';
import '../../profile/account_services.dart';
import '../../profile/profile_screen.dart';
import '../../stock/data/stock_submitter.dart';
import '../../stock/ui/move_screen.dart';
import '../../stock/ui/stock_controller.dart';
import '../../stock/ui/stock_screen.dart';
import '../domain/pur_models.dart';
import '../domain/purchase_draft.dart';
import '../list/shopping_controller.dart';
import '../list/shopping_list_screen.dart';
import '../mine/my_purchases_controller.dart';
import '../mine/my_purchases_screen.dart';
import '../mine/purchase_detail_screen.dart';
import '../purchasing_services.dart';
import '../record/record_screen.dart';

enum _Tab { shopping, mine, stock, profile }

/// The signed-in app for a buyer (Q2): Shopping list · My purchases ·
/// Profile. No Time In, no worker Requests, no My Work. 2B-b: a Stock tab
/// while the server says stock is on (asked on open, resume and tab tap).
class BuyerShell extends StatefulWidget {
  const BuyerShell({
    super.key,
    required this.buyer,
    required this.versionName,
    required this.onSignOut,
    required this.account,
    this.purchasing,
  });

  final WorkerProfile buyer;
  final String versionName;
  final Future<void> Function() onSignOut;
  final AccountServices account;

  /// The buying screens; null (its database could not open) leaves Profile only.
  final PurchasingServices? purchasing;

  @override
  State<BuyerShell> createState() => _BuyerShellState();
}

class _BuyerShellState extends State<BuyerShell> with WidgetsBindingObserver {
  _Tab _tab = _Tab.shopping;
  ShoppingController? _shopping;
  MyPurchasesController? _mine;
  StockController? _stock;
  StockSubmitter? _submitter;

  bool get _stockOn => _stock?.enabled ?? false;

  /// A stock record whose answer was lost (R101): it must be resolved first.
  bool get _unresolved => _submitter?.blocked ?? false;

  /// The tab stays while one is unresolved, even if stock was switched off.
  bool get _stockTab => _stockOn || _unresolved;

  List<_Tab> get _tabs => [
        if (widget.purchasing != null) ...[_Tab.shopping, _Tab.mine],
        if (_stockTab) _Tab.stock,
        _Tab.profile,
      ];

  @override
  void initState() {
    super.initState();
    final p = widget.purchasing;
    if (p != null) {
      _shopping = ShoppingController(api: p.api)..refresh();
      _mine = MyPurchasesController(api: p.api)..refresh();
      final stock = p.stock;
      final store = p.stockStore;
      // Stock only with the phone's own store: never kept in memory alone (R104).
      if (stock != null && store != null) {
        // Listen after the first refresh starts: its first notice is synchronous.
        _stock = StockController(remote: stock)..refresh();
        _stock!.addListener(_stockChanged);
        // What is waiting on this phone for this account; checked (read
        // only), never sent by itself.
        final submitter = _submitter = StockSubmitter(remote: stock, store: store)
          ..addListener(_stockChanged);
        unawaited(submitter.load(widget.buyer.id).then((_) => submitter.checkAll()));
      }
      _keepChoices();
      p.changed?.addListener(_refresh);
    } else {
      _tab = _Tab.profile;
    }
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    widget.purchasing?.changed?.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    _shopping?.dispose();
    _mine?.dispose();
    _stock?.dispose();
    _submitter?.dispose();
    super.dispose();
  }

  /// Stock switched on or off (or this account's right to record changed):
  /// the tab and the shopping list's button follow; an open Stock tab closes.
  void _stockChanged() {
    if (!mounted) return;
    setState(() {
      if (_tab == _Tab.stock && !_stockTab) _tab = _Tab.shopping;
    });
  }

  /// A purchase was recorded in the background, or the app came back.
  void _refresh() {
    _shopping?.refresh();
    _mine?.refresh();
  }

  void _refreshStock() {
    _stock?.refresh();
    final s = _submitter;
    if (s != null && s.blocked) unawaited(s.checkAll());
  }

  /// Reads the projects, jobs and suppliers while there is signal, so Record
  /// purchase has them later with none (the read keeps a saved copy).
  void _keepChoices() {
    final p = widget.purchasing;
    if (p != null) unawaited(p.api.choices().then<void>((_) {}, onError: (Object _) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _refreshStock();
      _keepChoices();
    }
  }

  void _select(_Tab t) {
    setState(() => _tab = t);
    if (t == _Tab.shopping) _shopping?.refresh();
    if (t == _Tab.mine) _mine?.refresh();
    if (t == _Tab.stock || t == _Tab.shopping) _refreshStock();
  }

  /// Issue from stock (Q26): this line's item, from the warehouse to the
  /// line's job, filling this request line. Starts at what the warehouse
  /// holds or what is still to buy, whichever is less — when both are in the
  /// same unit; the server checks the real balance.
  Future<void> _issueFromStock(ShoppingEntry entry) async {
    final stock = _stock;
    final submitter = _submitter;
    final l = entry.line;
    if (stock == null || submitter == null) return;
    final sameUnit = l.inWarehouseUnit.trim().toLowerCase() == l.unit.trim().toLowerCase();
    final preset = MovePreset(
      itemId: l.catalogItemId,
      to: l.workId,
      requestLineId: l.lineId,
      quantity: sameUnit ? (l.inWarehouse < l.stillToBuy ? l.inWarehouse : l.stillToBuy) : null,
      fixed: true,
    );
    final done = await openMove(context, stock, submitter, preset);
    if (!mounted || !done) return;
    _refresh();
    _refreshStock();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(key: Key('stock-recorded'), content: Text('Recorded. · Naitala na.')));
  }

  /// Record purchase (Q7): picked lines, a saved draft, or blank (unplanned).
  Future<void> _record({List<DraftPurchaseLine>? lines, PurchaseDraft? draft}) async {
    final p = widget.purchasing;
    if (p == null) return;
    if (draft == null && lines != null && lines.isNotEmpty) {
      final earlier = draftWithSameItems(await p.api.drafts(), lines);
      if (!mounted) return;
      if (earlier != null) {
        final carryOn = await showDialog<bool>(context: context, builder: (_) => _SameItemsDialog(draft: earlier));
        if (!mounted || carryOn == null) return;
        if (carryOn) {
          draft = withPickedLines(earlier, lines);
          lines = null;
        }
      }
    }
    if (!mounted) return;
    final queued = await openRecord(context, p, lines: lines, draft: draft);
    if (!mounted) return;
    _refresh();
    if (queued) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        key: Key('queued-snack'),
        content: Text('Saved. It is sent when there is signal. · Nai-save. Ipapadala kapag may signal.'),
      ));
    }
  }

  Future<void> _open(MyPurchase purchase) async {
    final p = widget.purchasing;
    if (p == null) return;
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => PurchaseDetailScreen(purchaseId: purchase.id, services: p)));
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final profile =
        ProfileScreen(worker: widget.buyer, versionName: widget.versionName, onSignOut: widget.onSignOut, account: widget.account, buyer: true);
    final tabs = _tabs;
    if (tabs.length < 2) return Scaffold(body: SafeArea(child: profile));
    final body = switch (_tab) {
      _Tab.shopping => ShoppingListScreen(
          controller: _shopping!,
          onRecord: (lines) => _record(lines: lines),
          onIssueFromStock: _stockOn && _stock!.status.canRecord && !_unresolved ? _issueFromStock : null,
        ),
      _Tab.stock => StockScreen(controller: _stock!, submitter: _submitter!, onRecorded: _refresh),
      _Tab.mine => MyPurchasesScreen(controller: _mine!, onOpenDraft: (d) => _record(draft: d), onOpenPurchase: _open, services: widget.purchasing),
      _Tab.profile => profile,
    };
    return Scaffold(
      body: SafeArea(child: body),
      floatingActionButton: _tab == _Tab.profile || _tab == _Tab.stock
          ? null
          // Hidden while items are ticked: their own Record purchase button
          // sits where this one would.
          : ListenableBuilder(
              listenable: _shopping!,
              builder: (context, _) => _tab == _Tab.shopping && _shopping!.selected.isNotEmpty
                  ? const SizedBox.shrink()
                  : FloatingActionButton.extended(
                      key: const Key('record-unplanned'),
                      onPressed: () => _record(),
                      icon: const Icon(Icons.add),
                      label: const Text('Record purchase'),
                    ),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabs.indexOf(_tab),
        onDestinationSelected: (i) => _select(tabs[i]),
        destinations: [
          for (final t in tabs)
            switch (t) {
              _Tab.shopping => const NavigationDestination(icon: Icon(Icons.shopping_cart_outlined), label: 'Shopping list'),
              _Tab.mine => NavigationDestination(icon: _MineIcon(controller: _mine!), label: 'My purchases'),
              _Tab.stock => const NavigationDestination(key: Key('tab-stock'), icon: Icon(Icons.inventory_2_outlined), label: 'Stock'),
              _Tab.profile => const NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
            },
        ],
      ),
    );
  }
}

/// Ticked items already in an unsent draft: continue it (true) or start a
/// new purchase (false). Null (dismissed) opens nothing.
class _SameItemsDialog extends StatelessWidget {
  const _SameItemsDialog({required this.draft});
  final PurchaseDraft draft;

  @override
  Widget build(BuildContext context) {
    final n = draft.lines.length;
    final name = draft.supplierName.isEmpty ? 'Purchase on ${draft.purchaseDate}' : draft.supplierName;
    return AlertDialog(
      key: const Key('same-items-dialog'),
      title: const Text('You already started this purchase'),
      content: Text('$name · $n item${n == 1 ? '' : 's'} · not sent.\n\n'
          'Continue it, or start a new one?\n'
          'Nasimulan mo na ito. Ituloy, o gumawa ng bago?'),
      actions: [
        TextButton(key: const Key('same-items-new'), onPressed: () => Navigator.of(context).pop(false), child: const Text('Start a new one')),
        FilledButton(key: const Key('same-items-continue'), onPressed: () => Navigator.of(context).pop(true), child: const Text('Continue it')),
      ],
    );
  }
}

/// My purchases, with a red number for purchases that need attention (Q7).
class _MineIcon extends StatelessWidget {
  const _MineIcon({required this.controller});
  final MyPurchasesController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final n = controller.attention;
          return Badge(
            key: const Key('mine-badge'),
            isLabelVisible: n > 0,
            label: Text('$n'),
            child: const Icon(Icons.receipt_long_outlined),
          );
        },
      );
}

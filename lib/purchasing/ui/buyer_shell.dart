import 'dart:async';

import 'package:flutter/material.dart';

import '../../auth/worker_profile.dart';
import '../../profile/account_services.dart';
import '../../profile/profile_screen.dart';
import '../domain/pur_models.dart';
import '../domain/purchase_draft.dart';
import '../list/shopping_controller.dart';
import '../list/shopping_list_screen.dart';
import '../mine/my_purchases_controller.dart';
import '../mine/my_purchases_screen.dart';
import '../mine/purchase_detail_screen.dart';
import '../purchasing_services.dart';
import '../record/record_screen.dart';

enum _Tab { shopping, mine, profile }

/// The signed-in app for a buyer (Q2): Shopping list · My purchases ·
/// Profile. No Time In, no worker Requests, no My Work.
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

  List<_Tab> get _tabs => [if (widget.purchasing != null) ...[_Tab.shopping, _Tab.mine], _Tab.profile];

  @override
  void initState() {
    super.initState();
    final p = widget.purchasing;
    if (p != null) {
      _shopping = ShoppingController(api: p.api)..refresh();
      _mine = MyPurchasesController(api: p.api)..refresh();
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
    super.dispose();
  }

  /// A purchase was recorded in the background, or the app came back.
  void _refresh() {
    _shopping?.refresh();
    _mine?.refresh();
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
      _keepChoices();
    }
  }

  void _select(_Tab t) {
    setState(() => _tab = t);
    if (t == _Tab.shopping) _shopping?.refresh();
    if (t == _Tab.mine) _mine?.refresh();
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
      _Tab.shopping => ShoppingListScreen(controller: _shopping!, onRecord: (lines) => _record(lines: lines)),
      _Tab.mine => MyPurchasesScreen(controller: _mine!, onOpenDraft: (d) => _record(draft: d), onOpenPurchase: _open, services: widget.purchasing),
      _Tab.profile => profile,
    };
    return Scaffold(
      body: SafeArea(child: body),
      floatingActionButton: _tab == _Tab.profile
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

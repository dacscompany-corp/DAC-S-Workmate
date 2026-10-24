import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../attendance/ui/formats.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../data/purchasing_api.dart';
import '../domain/pay_models.dart';
import '../domain/pur_failure.dart';
import '../purchasing_services.dart';
import '../ui/pay_copy.dart';
import '../ui/pay_widgets.dart';
import '../ui/purchasing_copy.dart';
import 'report_return_screen.dart';

/// The "My cash" card at the top of My purchases (Q23: no new tab): petty
/// cash held (never below ₱0; the rest is the shortfall, Q16), a return
/// waiting for the owner, and what the company owes me. Tap for the detail.
class MyCashCard extends StatelessWidget {
  const MyCashCard({super.key, required this.view, required this.onOpen});
  final MyCashView view;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = view.cash;
    final f = view.figures;
    if (c == null || f == null || !c.holder) return const SizedBox.shrink();
    final waiting = c.pendingReturns + view.queuedReturns.fold<double>(0, (a, q) => a + q.amount);
    return Card(
      key: const Key('my-cash-card'),
      color: Colors.white,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: BilingualText(myCashLabel)),
              const Icon(Icons.chevron_right, color: WmColors.textMuted),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 18, runSpacing: 8, children: [
              _Figure(cashHeldLabel, peso(f.held), key: const Key('cash-held')),
              if (waiting > 0) _Figure(returnWaitingLabel, peso(waiting), key: const Key('cash-waiting')),
              if (c.owes > 0 || c.owesToReview > 0) _Figure(companyOwesMeLabel, peso(c.owes), key: const Key('cash-owes')),
            ]),
            if (f.shortfall > 0) ...[
              const SizedBox(height: 8),
              PayWarning(key: const Key('cash-shortfall'), text: shortfallCopy(peso(f.shortfall))),
            ],
            if (view.fromCache && view.fetchedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Saved copy from ${shortDate(view.fetchedAt!)} ${clockTime(view.fetchedAt!)}.',
                    style: const TextStyle(fontSize: 12, color: WmColors.brownDeep, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, {super.key});
  final Bilingual label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label.english, style: const TextStyle(fontSize: 12, color: WmColors.textSecondary)),
        Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      ]);
}

/// "My cash" in full (Q14, Q17, Q22, Q24 — the buyer's own, never another
/// buyer's): what was given and returned, "I did not receive this", repayments.
class MyCashScreen extends StatefulWidget {
  const MyCashScreen({super.key, required this.services});
  final PurchasingServices services;

  @override
  State<MyCashScreen> createState() => _MyCashScreenState();
}

class _MyCashScreenState extends State<MyCashScreen> {
  PurchasingApi get _api => widget.services.api;
  MyCashView? _view;
  Bilingual? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads started so far: an older one that finishes last changes nothing (F3).
  int _loads = 0;

  Future<void> _load() async {
    final mine = ++_loads;
    try {
      // F3 (rev 2): the saved cash at once, never a wait for the network.
      if (_view == null) {
        final saved = (await _api.savedPurchasesAndCash()).cash;
        if (mounted && mine == _loads && _view == null && saved.cash != null) setState(() => _view = saved);
      }
      final v = await _api.myCash();
      if (mounted && mine == _loads) setState(() => _view = v);
    } catch (e) {
      if (mounted && mine == _loads) setState(() => _notice = purFailureCopy(PurFailure.of(e)));
    }
  }

  /// An online action: its failure is shown, nothing changes.
  Future<void> _online(Future<void> Function() call) async {
    setState(() => _notice = null);
    try {
      await call();
    } catch (e) {
      final f = PurFailure.of(e);
      if (mounted) setState(() => _notice = f == PurFailure.noConnection ? needsSignal : purFailureCopy(f));
    }
    await _load();
  }

  Future<void> _report() async {
    final held = _view?.figures?.held;
    final queued = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ReportReturnScreen(services: widget.services, held: held)));
    if (queued == true) await _load();
  }

  /// Q14: "I did not receive this", with a note (the server asks for one).
  Future<void> _dispute(CashIssue i) async {
    final opId = _api.newLineKey(); // minted once per form: a resend answers once
    final note = await askRequiredNote(context,
        title: 'I did not receive this', message: 'The owner sees your note. Your balance does not change until they settle it.', action: 'Send');
    if (note == null) return;
    await _online(() => _api.dispute(i.id, note, opId: opId));
  }

  Future<void> _withdraw(CashReturn r) async {
    final opId = _api.newLineKey();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Take back this return?'),
        content: Text('${peso(r.amount)} handed over ${r.handedOn}. The owner has not confirmed it yet.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep')),
          TextButton(key: const Key('withdraw-yes'), onPressed: () => Navigator.of(context).pop(true), child: const Text('Take back')),
        ],
      ),
    );
    if (ok == true) await _online(() => _api.withdrawReturn(r.id, opId: opId));
  }

  @override
  Widget build(BuildContext context) {
    final v = _view;
    final c = v?.cash;
    final f = v?.figures;
    return Scaffold(
      appBar: AppBar(title: const BilingualText(myCashLabel, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(key: const Key('my-cash'), padding: const EdgeInsets.all(16), children: [
            if (_notice != null) ...[
              FailureNotice(english: _notice!.english, tagalog: _notice!.tagalog, actions: [noticeAction('Dismiss · Isara', () => setState(() => _notice = null))]),
              const SizedBox(height: 10),
            ],
            if (v == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (c == null || f == null)
              const BilingualText(Bilingual('Connect once to see your cash.', 'Kumonekta muna para makita ang pera mo.'))
            else if (!c.holder)
              const BilingualText(Bilingual('Petty cash is for staff buyers. This account pays as the company.',
                  'Ang petty cash ay para sa staff na bumibili. Bilang kompanya nagbabayad ang account na ito.'))
            else ...[
              const Text('Company money you hold for purchases, and what the company owes you for your own money. None of it changes a project\'s costs.',
                  style: TextStyle(fontSize: 13, color: WmColors.textMuted)),
              const SizedBox(height: 10),
              Wrap(spacing: 18, runSpacing: 10, children: [
                _Figure(cashHeldLabel, peso(f.held), key: const Key('detail-held')),
                _Figure(companyOwesMeLabel, peso(c.owes), key: const Key('detail-owes')),
              ]),
              if (f.shortfall > 0) ...[const SizedBox(height: 8), PayWarning(text: shortfallCopy(peso(f.shortfall)))],
              if (c.owesToReview > 0) ...[
                const SizedBox(height: 8),
                Text('${peso(c.owesToReview)} waiting for the owner\'s review', style: const TextStyle(fontWeight: FontWeight.w700)),
                const PayWarning(text: ownMoneyToReviewCopy),
              ],
              if (v.fromCache && v.fetchedAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Saved copy from ${shortDate(v.fetchedAt!)} ${clockTime(v.fetchedAt!)}.',
                      key: const Key('cash-saved-copy'), style: const TextStyle(color: WmColors.brownDeep, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 14),
              bilingualButton(reportReturnLabel, _report, filled: true, key: const Key('report-return')),
              if (v.queuedReturns.isNotEmpty) ...[
                const SizedBox(height: 18),
                const BilingualText(Bilingual('Not sent yet', 'Hindi pa naipapadala'), style: monoLabel),
                for (final q in v.queuedReturns) _QueuedReturn(q: q, onThrowAway: () async {
                  await _api.discardAction(q.opId);
                  await _load();
                }),
              ],
              const SizedBox(height: 18),
              const BilingualText(Bilingual('Petty cash you were given (90 days)', 'Petty cash na ibinigay sa iyo (90 araw)'), style: monoLabel),
              if (c.issues.isEmpty) const Text('Nothing here.'),
              for (final i in c.issues)
                ListTile(
                  key: Key('issue-${i.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text('${i.issuedOn} — ${peso(i.amount)} ${payMethodLabel(i.method)}',
                      style: TextStyle(decoration: i.voided ? TextDecoration.lineThrough : null)),
                  subtitle: Text([
                    if (i.note.isNotEmpty) i.note,
                    if (i.voided) 'voided: ${i.voidReason}',
                    if (i.flagged) 'You said not received — the owner is checking',
                    if (i.disputeClearedAt != null) 'Owner: ${i.disputeClearedNote}',
                  ].join(' · ')),
                  trailing: i.canDispute
                      ? TextButton(key: Key('dispute-${i.id}'), onPressed: () => _dispute(i), child: Text(notReceivedLabel.english))
                      : null,
                ),
              const SizedBox(height: 14),
              const BilingualText(Bilingual('Returns', 'Mga ibinalik'), style: monoLabel),
              if (c.returns.isEmpty) const Text('Nothing here.'),
              for (final r in c.returns)
                ListTile(
                  key: Key('return-${r.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: r.photoUrl.isEmpty ? null : _Thumb(url: r.photoUrl, services: widget.services),
                  title: Text('${r.handedOn} — ${peso(r.amount)}'),
                  subtitle: Text([
                    switch (r.status) {
                      'reported' => 'waiting for the owner',
                      'confirmed' => 'confirmed',
                      'rejected' => 'rejected',
                      'withdrawn' => 'taken back',
                      _ => r.status,
                    },
                    if (r.decisionNote.isNotEmpty) r.decisionNote,
                    if (r.voidedAt != null) 'voided by the owner',
                  ].join(' · ')),
                  trailing: r.waiting ? TextButton(key: Key('withdraw-${r.id}'), onPressed: () => _withdraw(r), child: const Text('Take back')) : null,
                ),
              const SizedBox(height: 14),
              const BilingualText(Bilingual('Repaid to you (90 days)', 'Ibinalik sa iyo (90 araw)'), style: monoLabel),
              if (c.repayments.isEmpty) const Text('Nothing here.'),
              for (final x in c.repayments)
                Text('${x.paidOn} — ${peso(x.amount)} ${payMethodLabel(x.method)}${x.voidedAt == null ? '' : ' (voided)'}'),
              const SizedBox(height: 40),
            ],
          ]),
        ),
      ),
    );
  }
}

class _QueuedReturn extends StatelessWidget {
  const _QueuedReturn({required this.q, required this.onThrowAway});
  final QueuedCashAction q;
  final VoidCallback onThrowAway;

  @override
  Widget build(BuildContext context) {
    final attention = q.state == QueuedState.needsAttention;
    final why = attention ? purFailureCopy(q.failure ?? PurFailure.unexpected) : null;
    return Card(
      key: Key('queued-return-${q.opId}'),
      color: attention ? WmColors.dangerTint : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Return ${peso(q.amount)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          BilingualText(attention ? attentionLabel : (q.state == QueuedState.sent ? sentLabel : waitingToSendPayLabel),
              style: TextStyle(fontWeight: FontWeight.w700, color: attention ? WmColors.danger : WmColors.brownDeep)),
          if (why != null) ...[
            Text(why.english, style: const TextStyle(color: WmColors.danger, fontWeight: FontWeight.w600)),
            Text(why.tagalog, style: const TextStyle(color: WmColors.danger, fontSize: 12.5)),
            TextButton(key: Key('throw-return-${q.opId}'), onPressed: onThrowAway, child: const Text('Throw away')),
          ],
        ]),
      ),
    );
  }
}

/// A return photo, downloaded as this buyer (never a signed link, R13/F2).
class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.services});
  final String url;
  final PurchasingServices services;

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: services.api.receipt(url),
        builder: (context, snap) {
          final bytes = snap.data;
          return SizedBox(
            width: 48,
            height: 48,
            child: bytes == null
                ? const Icon(Icons.image_outlined)
                : GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        backgroundColor: WmColors.viewerBackdrop,
                        appBar: AppBar(backgroundColor: WmColors.viewerBackdrop, foregroundColor: Colors.white),
                        body: InteractiveViewer(child: Center(child: Image.memory(bytes))),
                      ),
                    )),
                    child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.memory(bytes, fit: BoxFit.cover)),
                  ),
          );
        },
      );
}

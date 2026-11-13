import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../attendance/ui/formats.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../../ui/wm_page.dart';
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
    // The 6a card: white, 1-px border, radius 16, no shadow, a chevron.
    return Container(
      key: const Key('my-cash-card'),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: WmColors.border)),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(child: BilingualText(myCashLabel)),
                const Icon(Icons.chevron_right, size: 22, color: WmColors.textMuted),
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
      ),
    );
  }
}

/// An amount in the mono style, as on the My purchases cards.
const _mono = TextStyle(fontFamily: 'IBM Plex Mono', fontWeight: FontWeight.w700);

/// A sentence with one amount in it: the amount takes the mono font, the words keep theirs.
InlineSpan _withAmount(String before, String amount, String after) =>
    TextSpan(children: [TextSpan(text: before), TextSpan(text: amount, style: _mono), TextSpan(text: after)]);

/// A group's label: the English in capitals, then ` · Tagalog` (as on My purchases)
/// while both fit on one line. My cash's labels are long: one that does not fit puts
/// the Tagalog on a line of its own, without the dot (never a dot at the start of a line).
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.title);
  final Bilingual title;

  @override
  Widget build(BuildContext context) {
    final english = title.english.toUpperCase();
    final dotted = ' · ${title.tagalog}';
    final light = monoLabel.copyWith(fontWeight: FontWeight.w400, letterSpacing: 0);
    // Measured the way the two Texts below are laid out: the page's text style,
    // the reader's text size and bold-text setting.
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final bold = MediaQuery.boldTextOf(context);
    final direction = Directionality.of(context);
    double width(String text, TextStyle style) {
      var effective = base.merge(style);
      if (bold) effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
      final painter = TextPainter(text: TextSpan(text: text, style: effective), textDirection: direction, textScaler: scaler, maxLines: 1)..layout();
      final w = painter.width;
      painter.dispose();
      return w;
    }

    final oneLine = width(english, monoLabel) + width(dotted, light);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 2),
      child: LayoutBuilder(
        builder: (context, box) => oneLine <= box.maxWidth
            ? Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(english, style: monoLabel),
                Text(dotted, style: light),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(english, style: monoLabel),
                const SizedBox(height: 2),
                Text(title.tagalog, style: light),
              ]),
      ),
    );
  }
}

/// One row of My cash: a white bordered card (radius 16, no shadow) with the words on
/// the left and an optional action or picture beside them.
class _CashRow extends StatelessWidget {
  const _CashRow({super.key, required this.title, this.sub, this.leading, this.trailing});
  final InlineSpan title;
  final String? sub;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: WmColors.border)),
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            flex: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: WmColors.text)),
              if (sub != null && sub!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: const TextStyle(fontSize: 13, color: WmColors.textMuted))),
            ]),
          ),
          // The action may wrap its words when the line is tight; the card text keeps its share.
          if (trailing != null) ...[const SizedBox(width: 4), Flexible(flex: 2, child: trailing!)],
        ]),
      );
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, {super.key});
  final Bilingual label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label.english, style: const TextStyle(fontSize: 12, color: WmColors.textSecondary)),
        Text(value, style: _mono.copyWith(fontSize: 19, fontWeight: FontWeight.w800)),
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
    // Pull to refresh: the page's list sends its scroll notifications up to this.
    return RefreshIndicator(
      onRefresh: _load,
      child: WmPage(
        key: const Key('my-cash'),
        title: myCashLabel.english,
        children: [
          Text(myCashLabel.tagalog, style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
          const SizedBox(height: 10),
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
              Text.rich(_withAmount('', peso(c.owesToReview), ' waiting for the owner\'s review'), style: const TextStyle(fontWeight: FontWeight.w700)),
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
              const _GroupLabel(Bilingual('Not sent yet', 'Hindi pa naipapadala')),
              for (final q in v.queuedReturns) _QueuedReturn(q: q, onThrowAway: () async {
                await _api.discardAction(q.opId);
                await _load();
              }),
            ],
            const _GroupLabel(Bilingual('Petty cash you were given (90 days)', 'Petty cash na ibinigay sa iyo (90 araw)')),
            if (c.issues.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Nothing here.')),
            for (final i in c.issues)
              _CashRow(
                key: Key('issue-${i.id}'),
                title: TextSpan(
                  style: TextStyle(decoration: i.voided ? TextDecoration.lineThrough : null),
                  children: [TextSpan(text: '${i.issuedOn} — '), TextSpan(text: peso(i.amount), style: _mono), TextSpan(text: ' ${payMethodLabel(i.method)}')],
                ),
                sub: [
                  if (i.note.isNotEmpty) i.note,
                  if (i.voided) 'voided: ${i.voidReason}',
                  if (i.flagged) 'You said not received — the owner is checking',
                  if (i.disputeClearedAt != null) 'Owner: ${i.disputeClearedNote}',
                ].join(' · '),
                trailing: i.canDispute
                    ? TextButton(key: Key('dispute-${i.id}'), onPressed: () => _dispute(i), child: Text(notReceivedLabel.english))
                    : null,
              ),
            const _GroupLabel(Bilingual('Returns', 'Mga ibinalik')),
            if (c.returns.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Nothing here.')),
            for (final r in c.returns)
              _CashRow(
                key: Key('return-${r.id}'),
                leading: r.photoUrl.isEmpty ? null : _Thumb(url: r.photoUrl, services: widget.services),
                title: _withAmount('${r.handedOn} — ', peso(r.amount), ''),
                sub: [
                  switch (r.status) {
                    'reported' => 'waiting for the owner',
                    'confirmed' => 'confirmed',
                    'rejected' => 'rejected',
                    'withdrawn' => 'taken back',
                    _ => r.status,
                  },
                  if (r.decisionNote.isNotEmpty) r.decisionNote,
                  if (r.voidedAt != null) 'voided by the owner',
                ].join(' · '),
                trailing: r.waiting ? TextButton(key: Key('withdraw-${r.id}'), onPressed: () => _withdraw(r), child: const Text('Take back')) : null,
              ),
            const _GroupLabel(Bilingual('Repaid to you (90 days)', 'Ibinalik sa iyo (90 araw)')),
            if (c.repayments.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Nothing here.')),
            for (final x in c.repayments)
              _CashRow(title: _withAmount('${x.paidOn} — ', peso(x.amount), ' ${payMethodLabel(x.method)}${x.voidedAt == null ? '' : ' (voided)'}')),
            const SizedBox(height: 40),
          ],
        ],
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
    return Container(
      key: Key('queued-return-${q.opId}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: attention ? WmColors.dangerTint : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: attention ? WmColors.dangerBorder : WmColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(_withAmount('Return ', peso(q.amount), ''), style: const TextStyle(fontWeight: FontWeight.w800)),
        BilingualText(attention ? attentionLabel : (q.state == QueuedState.sent ? sentLabel : waitingToSendPayLabel),
            style: TextStyle(fontWeight: FontWeight.w700, color: attention ? WmColors.danger : WmColors.brownDeep)),
        if (why != null) ...[
          Text(why.english, style: const TextStyle(color: WmColors.danger, fontWeight: FontWeight.w600)),
          Text(why.tagalog, style: const TextStyle(color: WmColors.danger, fontSize: 12.5)),
          TextButton(key: Key('throw-return-${q.opId}'), onPressed: onThrowAway, child: const Text('Throw away')),
        ],
      ]),
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

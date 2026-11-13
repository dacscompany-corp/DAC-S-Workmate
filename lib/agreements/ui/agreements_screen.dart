import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../attendance/ui/formats.dart' show clockTime, shortDate;
import '../../ui/theme.dart';
import '../../ui/wm_sheet.dart';
import '../domain/my_agreement.dart';
import 'agreements_controller.dart';
import 'agreements_copy.dart';

/// Opens the My agreements sheet (Home's shortcut, Profile's row). It reads
/// again as it opens: a sheet has no pull-down.
Future<void> showAgreementsSheet(BuildContext context, AgreementsController controller) {
  controller.refresh();
  return showWmSheet<void>(context, builder: (_) => AgreementsSheet(controller: controller));
}

/// My agreements (Linked Labor), a sheet since Phase 5: the signed-in worker's
/// own linked agreements, read from the server each time. An agreement opens in
/// place (one at a time) with its works and payments. With no signal, or when
/// the server refuses, the amounts are gone and the sheet says why — never an
/// old balance.
class AgreementsSheet extends StatefulWidget {
  const AgreementsSheet({super.key, required this.controller});

  final AgreementsController controller;

  @override
  State<AgreementsSheet> createState() => _AgreementsSheetState();
}

class _AgreementsSheetState extends State<AgreementsSheet> {
  /// The agreement that is open. It stays while the server is asked again (the
  /// controller empties its list meanwhile) and closes once an answer no longer
  /// has it.
  String? _openId;

  /// The open agreement is no longer listed for this account.
  bool _gone = false;

  AgreementsController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_sync);
  }

  @override
  void dispose() {
    _c.removeListener(_sync);
    super.dispose();
  }

  /// Runs before the builder below rebuilds (added first), so it only sets fields.
  void _sync() {
    if (_c.loading) {
      _gone = false;
      return;
    }
    final id = _openId;
    if (id != null && _c.byId(id) == null) {
      _gone = _c.failure == null;
      _openId = null;
    }
  }

  void _toggle(String id) => setState(() {
        _gone = false;
        _openId = _openId == id ? null : id;
      });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final c = _c;
          final f = c.failure;
          return WmSheetFrame(
            key: const Key('agreements-sheet'),
            title: myAgreementsTitle.english,
            subtitle: myAgreementsTitle.tagalog,
            tall: true,
            children: [
              if (f != null) _Notice(text: agreementsFailureCopy(f), onRetry: c.refresh),
              if (f == null && c.loading && !c.loaded) const _Checking(),
              if (f == null && c.loaded && _gone) ...[_Plain(agreementGone), const SizedBox(height: 12)],
              if (f == null && c.loaded && c.agreements.isEmpty) _Plain(agreementsNone),
              for (final a in c.agreements) _agreementCard(a),
              if (c.agreements.isNotEmpty && c.fetchedAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Updated ${clockTime(c.fetchedAt!)}', style: const TextStyle(fontSize: 12, color: WmColors.textMuted)),
                ),
              const SizedBox(height: 8),
              _Plain(agreementsFootnote, muted: true),
            ],
          );
        },
      );

  /// The closed card is today's tile with an expand arrow; opened, it adds what
  /// the old agreement page showed: the works covered and the payments.
  Widget _agreementCard(MyAgreement a) {
    final open = _openId == a.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: WmColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          key: Key('agreement-${a.id}'),
          onTap: () => _toggle(a.id),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _Header(a: a)),
                Icon(open ? Icons.expand_less : Icons.expand_more, color: WmColors.textMuted),
              ]),
              const SizedBox(height: 10),
              _Money(a: a, compact: true),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (a.works.isNotEmpty) ...[
                const _Label('Works covered'),
                for (final (i, w) in a.works.indexed) Text('${i + 1}. $w', style: const TextStyle(fontSize: 14, height: 1.5)),
                const SizedBox(height: 16),
              ],
              const _Label('Payments'),
              if (a.payments.isEmpty)
                const Text('No payments recorded yet.', style: TextStyle(color: WmColors.textMuted))
              else
                for (final p in a.payments) _PaymentRow(p: p),
            ]),
          ),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.a});

  final MyAgreement a;

  @override
  Widget build(BuildContext context) {
    final pct = a.progressPct;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(a.project, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      if (a.mainProject != null)
        Text('Additional Works of ${a.mainProject}', style: const TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
      const SizedBox(height: 4),
      Text(a.scope.isEmpty ? 'Untitled job' : a.scope, style: const TextStyle(fontSize: 14.5, color: WmColors.textSecondary)),
      if (a.trade.isNotEmpty) Text(a.trade, style: const TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        if (a.daily) const _Chip('Daily basis', WmColors.brown, WmColors.brownTint),
        if (a.ended) _Chip(a.endedAt == null ? 'Ended' : 'Ended ${shortDate(a.endedAt!)}', WmColors.textMuted, WmColors.inert),
        if (a.projectCompleted) const _Chip('Project completed', WmColors.green, WmColors.greenTint),
      ]),
      const SizedBox(height: 6),
      Text(
        pct == null ? '${progressNone.english} · ${progressNone.tagalog}' : '${progressLabel.english}: ${progressText(pct)}',
        key: const Key('agreement-progress'),
        style: const TextStyle(fontSize: 13, color: WmColors.textSecondary),
      ),
    ]);
  }
}

/// Agreed / Paid so far / Balance — or, daily, Paid so far only. An
/// overpayment reads "Over by"; a paid-in-full agreement is not proof that
/// the work is done, so nothing here says "complete".
class _Money extends StatelessWidget {
  const _Money({required this.a, this.compact = false});

  final MyAgreement a;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String, Color)>[
      if (!a.daily) ('Agreed', agreementPeso(a.agreed ?? 0), WmColors.text),
      ('Paid so far', agreementPeso(a.paid), WmColors.text),
      if (!a.daily)
        a.overPaid
            ? ('Over by', agreementPeso(a.balance ?? 0), WmColors.danger)
            : ('Balance', agreementPeso(a.balance ?? 0), WmColors.green),
    ];
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(color: WmColors.field, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        for (final (label, value, color) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(child: Text(label, style: const TextStyle(color: WmColors.textMuted, fontWeight: FontWeight.w600))),
              Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
        if (a.daily)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('No agreed total — paid by the day.', style: TextStyle(fontSize: 12, color: WmColors.textMuted)),
          ),
      ]),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.p});

  final AgreementPayment p;

  @override
  Widget build(BuildContext context) {
    // Project Control saves the date with its time ("2026-11-09T13:07", Manila
    // wall-clock); older rows hold the day alone, a few nothing. The day is the
    // first ten characters either way. The time is never parsed: read as UTC it
    // would move a late-evening payment to the next day.
    final raw = (p.date ?? '').trim();
    final day = RegExp(r'^\d{4}-\d{2}-\d{2}').firstMatch(raw)?.group(0);
    final d = day == null ? null : DateTime.tryParse('${day}T00:00:00+08:00');
    final method = paymentMethodLabel(p.method);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Text([d == null ? (raw.isEmpty ? '—' : raw) : shortDate(d), if (method.isNotEmpty) method].join(' · '),
              style: const TextStyle(color: WmColors.textSecondary)),
        ),
        Text(agreementPeso(p.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color, this.tint);

  final String text;
  final Color color;
  final Color tint;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: WmColors.textMuted)),
      );
}

class _Plain extends StatelessWidget {
  const _Plain(this.text, {this.muted = false});

  final Bilingual text;
  final bool muted;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text.english, style: TextStyle(color: muted ? WmColors.textMuted : WmColors.textSecondary, fontSize: muted ? 12.5 : 14)),
        Text(text.tagalog, style: const TextStyle(color: WmColors.textMuted, fontSize: 11.5)),
      ]);
}

/// Asking the server; no figure is on screen meanwhile.
class _Checking extends StatelessWidget {
  const _Checking();

  @override
  Widget build(BuildContext context) => Padding(
        key: const Key('agreements-checking'),
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(agreementsChecking.english, style: const TextStyle(color: WmColors.textSecondary)),
          Text(agreementsChecking.tagalog, style: const TextStyle(fontSize: 11.5, color: WmColors.textMuted)),
        ]),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.onRetry});

  final Bilingual text;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('agreements-notice'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: WmColors.brownTint, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text.english, style: const TextStyle(fontWeight: FontWeight.w700, color: WmColors.brown)),
          Text(text.tagalog, style: const TextStyle(fontSize: 12, color: WmColors.brown)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: Text(agreementsRetry.english)),
        ]),
      );
}

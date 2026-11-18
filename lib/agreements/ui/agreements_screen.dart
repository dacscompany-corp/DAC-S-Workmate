import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../attendance/ui/formats.dart' show clockTime, shortDate;
import '../../ui/theme.dart';
import '../../ui/wm_build_art.dart';
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

/// My agreements (Linked Labor), redesign v2 ("1b revised", 18 Nov 2026): one
/// tab per agreement. The open tab shows Agreed, Paid so far and Balance (or
/// Over by) on a green card, the whole project's progress and the works
/// covered — never a payment (owner decision 17 Nov 2026). While the server is
/// asked, with no signal, or when the server refuses, no amount is on screen
/// and the sheet says why — never an old balance.
class AgreementsSheet extends StatefulWidget {
  const AgreementsSheet({super.key, required this.controller});

  final AgreementsController controller;

  @override
  State<AgreementsSheet> createState() => _AgreementsSheetState();
}

class _AgreementsSheetState extends State<AgreementsSheet> {
  /// The agreement whose tab is open. It stays while the server is asked again
  /// (the controller empties its list meanwhile); an answer that no longer has
  /// it leaves every tab closed and says so.
  String? _selId;

  /// The open agreement is no longer listed for this account.
  bool _gone = false;

  AgreementsController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_sync);
    _sync(); // the answer may be in before the sheet is built
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
    if (_c.failure != null) {
      _selId = null;
      _gone = false;
      return;
    }
    if (!_c.loaded) return;
    final id = _selId;
    if (id != null && _c.byId(id) == null) {
      _selId = null;
      _gone = true;
    } else if (id == null && !_gone && _c.agreements.isNotEmpty) {
      _selId = _c.agreements.first.id;
    }
  }

  void _select(String id) => setState(() {
        _gone = false;
        _selId = id;
      });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _c,
        builder: (context, _) => WmSheetFrame(
          key: const Key('agreements-sheet'),
          title: myAgreementsTitle.english,
          subtitle: myAgreementsTitle.tagalog,
          tall: true,
          body: _body(),
        ),
      );

  Widget _body() {
    final c = _c;
    final f = c.failure;
    if (f != null) {
      final (icon, ink, tint) = _failureLook(f);
      return _Centred(
        key: const Key('agreements-notice'),
        icon: icon,
        iconColor: ink,
        iconTint: tint,
        text: agreementsFailureCopy(f),
        detail: agreementsFailureDetail(f),
        onRetry: agreementsFailureRetries(f) ? c.refresh : null,
      );
    }
    if (c.loading) return const _Checking();
    if (!c.loaded) return const SizedBox.shrink();
    if (c.agreements.isEmpty) {
      return const _Centred(key: Key('agreements-none'), icon: Icons.description_outlined, text: agreementsNone);
    }
    final id = _selId;
    final open = _gone ? null : (id == null ? null : c.byId(id)) ?? c.agreements.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Tabs(agreements: c.agreements, labels: agreementTabLabels(c.agreements), openId: open?.id, onTap: _select),
      Expanded(
        child: open == null
            ? const _Centred(key: Key('agreement-gone'), icon: Icons.visibility_off_outlined, text: agreementGone)
            // Keyed by agreement: another tab starts at the top of its own list.
            : _AgreementView(key: Key('agreement-${open.id}'), a: open, fetchedAt: c.fetchedAt),
      ),
    ]);
  }
}

(IconData, Color, Color) _failureLook(AgreementsFailure f) => switch (f) {
      AgreementsFailure.noConnection => (Icons.signal_cellular_off, WmColors.brown, WmColors.brownTint),
      AgreementsFailure.appUpdateRequired => (Icons.system_update, WmColors.green, WmColors.greenTint),
      AgreementsFailure.notAllowed => (Icons.lock_outline, WmColors.textSecondary, WmColors.hairline),
      AgreementsFailure.sessionExpired => (Icons.login, WmColors.textSecondary, WmColors.hairline),
      AgreementsFailure.unexpected => (Icons.error_outline, WmColors.textSecondary, WmColors.hairline),
    };

// ---- Tabs ----

/// One pill per agreement, scrolling sideways; the open one is green. With
/// none open (the open one was removed), every pill is white.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.agreements, required this.labels, required this.openId, required this.onTap});

  final List<MyAgreement> agreements;
  final Map<String, String> labels;
  final String? openId;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        key: const Key('agreement-tabs'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: Row(children: [
          for (final (i, a) in agreements.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            _Tab(
              key: Key('agreement-tab-${a.id}'),
              label: labels[a.id] ?? a.project,
              active: a.id == openId,
              onTap: () => onTap(a.id),
            ),
          ],
        ]),
      );
}

class _Tab extends StatelessWidget {
  const _Tab({super.key, required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        button: true,
        selected: active,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: ShapeDecoration(
            color: active ? WmColors.green : Colors.white,
            shape: StadiumBorder(side: BorderSide(color: active ? WmColors.green : WmColors.border)),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    widthFactor: 1,
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800, color: active ? Colors.white : WmColors.text)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

// ---- One agreement ----

const _heroSoft = Color(0xFFCFE3D6);
const _heroFaint = Color(0xFFB9D3C2);
const _heroOver = Color(0xFFFF9C8F);
const _heroInner = Color(0xFF18573A);

class _AgreementView extends StatelessWidget {
  const _AgreementView({super.key, required this.a, required this.fetchedAt});

  final MyAgreement a;
  final DateTime? fetchedAt;

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          _Summary(a: a),
          if (a.overPaid) ...[const SizedBox(height: 12), const _OverPaidNote()],
          const SizedBox(height: 12),
          _ProgressCard(pct: a.progressPct),
          if (a.works.isNotEmpty) ...[const SizedBox(height: 12), _WorksCard(works: a.works)],
          const SizedBox(height: 12),
          _Footer(fetchedAt: fetchedAt),
        ],
      );
}

/// The green card: who and what, the state chips, then the money — the ring,
/// Balance (or Over by), Agreed and Paid so far; daily, Paid so far alone. A
/// paid-in-full agreement is not proof that the work is done, so nothing here
/// says "complete".
class _Summary extends StatelessWidget {
  const _Summary({required this.a});

  final MyAgreement a;

  @override
  Widget build(BuildContext context) {
    final chips = [
      if (a.daily) 'Daily basis',
      if (a.ended) a.endedAt == null ? 'Ended' : 'Ended ${shortDate(a.endedAt!)}',
      if (a.projectCompleted) 'Project completed',
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment(-0.36, -1),
          end: Alignment(0.36, 1),
          colors: [Color(0xFF1E6542), Color(0xFF14492E)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.project.isEmpty ? 'Agreement' : a.project,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.15)),
                if (a.mainProject != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Additional Works of ${a.mainProject}', style: const TextStyle(fontSize: 13.5, color: _heroSoft)),
                  ),
                const SizedBox(height: 4),
                Text(a.scope.isEmpty ? 'Untitled job' : a.scope, style: const TextStyle(fontSize: 15.5)),
                if (a.trade.isNotEmpty) Text(a.trade, style: const TextStyle(fontSize: 13, color: _heroFaint)),
              ]),
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (final (i, t) in chips.indexed) ...[if (i > 0) const SizedBox(height: 6), _HeroChip(t)],
                ]),
              ),
            ],
          ]),
          const SizedBox(height: 16),
          if (a.daily) _DailyPaid(a: a) else _FixedFigures(a: a),
        ]),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: const Color(0x29FFFFFF), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white)),
      );
}

class _FixedFigures extends StatelessWidget {
  const _FixedFigures({required this.a});

  final MyAgreement a;

  @override
  Widget build(BuildContext context) {
    final agreed = a.agreed ?? 0;
    final over = a.overPaid;
    final pct = agreementPaidPercent(a);
    // Under: the share paid, in white. Over: the agreed share in white, the rest in red.
    final fraction = over ? (a.paid > 0 && agreed > 0 ? agreed / a.paid : 0.0) : (agreed > 0 ? a.paid / agreed : 0.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        SizedBox(
          key: const Key('agreement-ring'),
          width: 104,
          height: 104,
          child: CustomPaint(
            painter: _PaidRingPainter(fraction: fraction, over: over),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(pct == null ? '—' : '$pct%', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1)),
                const Text('paid', style: TextStyle(fontSize: 12.5, color: _heroSoft)),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(over ? 'Over by' : 'Balance', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _heroSoft)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                agreementPeso(a.balance ?? 0),
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: over ? _heroOver : Colors.white,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ]),
        ),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _HeroTile(label: 'Agreed', value: agreementPeso(agreed))),
        const SizedBox(width: 8),
        Expanded(child: _HeroTile(label: 'Paid so far', value: agreementPeso(a.paid))),
      ]),
    ]);
  }
}

class _HeroTile extends StatelessWidget {
  const _HeroTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: const Color(0x1AFFFFFF), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: _heroSoft)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ]),
      );
}

class _DailyPaid extends StatelessWidget {
  const _DailyPaid({required this.a});

  final MyAgreement a;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Paid so far', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _heroSoft)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(agreementPeso(a.paid),
              style: const TextStyle(
                  fontSize: 36, fontWeight: FontWeight.w800, height: 1.1, fontFeatures: [FontFeature.tabularFigures()])),
        ),
        const SizedBox(height: 6),
        const Text(agreementDailyNote, style: TextStyle(fontSize: 14, color: _heroSoft)),
      ]);
}

/// The paid ring: a 12-px band from twelve o'clock, clockwise.
class _PaidRingPainter extends CustomPainter {
  const _PaidRingPainter({required this.fraction, required this.over});

  /// The white share of the band, 0..1.
  final double fraction;

  /// Paid over the agreed amount: the rest of the band is red, not faint.
  final bool over;

  @override
  void paint(Canvas canvas, Size size) {
    const band = 12.0;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - band / 2;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = band
      ..strokeCap = StrokeCap.butt;
    canvas.drawCircle(c, r, stroke..color = over ? _heroOver : const Color(0x2EFFFFFF));
    final f = fraction.clamp(0.0, 1.0);
    if (f > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * f, false, stroke..color = Colors.white);
    }
    canvas.drawCircle(c, r - band / 2, Paint()..color = _heroInner);
  }

  @override
  bool shouldRepaint(_PaidRingPainter old) => old.fraction != fraction || old.over != over;
}

class _OverPaidNote extends StatelessWidget {
  const _OverPaidNote();

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('agreement-over-note'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: const Color(0xFFFBECEA), borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, size: 20, color: Color(0xFF7A2219)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(agreementOverPaid.english, style: const TextStyle(fontSize: 14, height: 1.35, color: Color(0xFF7A2219))),
              const SizedBox(height: 2),
              Text(agreementOverPaid.tagalog, style: const TextStyle(fontSize: 13.5, height: 1.35, color: Color(0xFF8E3A30))),
            ]),
          ),
        ]),
      );
}

class _WhiteCard extends StatelessWidget {
  const _WhiteCard({super.key, required this.padding, required this.child});

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: WmColors.border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: child,
      );
}

/// The whole project's progress from its own BOQ — never the worker's own,
/// and never a stand-in 100%.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.pct});

  final double? pct;

  @override
  Widget build(BuildContext context) {
    final pct = this.pct;
    const style = TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700);
    return _WhiteCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: WmColors.hairline, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.construction, size: 22, color: WmColors.textSecondary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: pct == null
              ? Text('${progressNone.english} · ${progressNone.tagalog}', key: const Key('agreement-progress'), style: style)
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${progressLabel.english}: ${progressText(pct)}', key: const Key('agreement-progress'), style: style),
                  const SizedBox(height: 6),
                  Container(
                    height: 6,
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(color: const Color(0xFFEEEFE9), borderRadius: BorderRadius.circular(3)),
                    child: FractionallySizedBox(
                      widthFactor: (pct / 100).clamp(0.0, 1.0),
                      child: Container(
                          decoration: BoxDecoration(color: WmColors.green, borderRadius: BorderRadius.circular(3))),
                    ),
                  ),
                ]),
        ),
      ]),
    );
  }
}

class _WorksCard extends StatelessWidget {
  const _WorksCard({required this.works});

  final List<String> works;

  @override
  Widget build(BuildContext context) => _WhiteCard(
        key: const Key('agreement-works'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(agreementWorksLabel.toUpperCase(),
              style: monoLabel.copyWith(fontSize: 11.5, letterSpacing: 1, color: WmColors.textMuted)),
          for (final (i, w) in works.indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: WmColors.hairline))),
              child: Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: WmColors.hairline, borderRadius: BorderRadius.circular(8)),
                  child: Text('${i + 1}.',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: WmColors.textSecondary)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(w, style: const TextStyle(fontSize: 15))),
              ]),
            ),
        ]),
      );
}

class _Footer extends StatelessWidget {
  const _Footer({required this.fetchedAt});

  final DateTime? fetchedAt;

  @override
  Widget build(BuildContext context) {
    final at = fetchedAt;
    const muted = TextStyle(fontSize: 13, height: 1.4, color: WmColors.textMuted);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.schedule, size: 18, color: WmColors.textMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (at != null) Text('Updated ${clockTime(at)}', style: muted),
            Text(agreementsFootnote.english, style: muted),
            const SizedBox(height: 2),
            Text(agreementsFootnote.tagalog, style: muted.copyWith(fontSize: 12.5)),
          ]),
        ),
      ]),
    );
  }
}

// ---- States in the middle of the sheet ----

/// A state centred in the sheet (a little above the middle): an icon or the
/// loading drawing, a headline, an English second line, the Tagalog, and
/// "Try again" when that can help. It scrolls if the text is very large.
class _Centred extends StatelessWidget {
  const _Centred({
    super.key,
    this.icon,
    this.iconColor = WmColors.textSecondary,
    this.iconTint = WmColors.hairline,
    this.art,
    required this.text,
    this.detail,
    this.below,
    this.onRetry,
  });

  final IconData? icon;
  final Color iconColor;
  final Color iconTint;

  /// In place of the icon (the loading drawing).
  final Widget? art;
  final Bilingual text;
  final String? detail;

  /// Under the text (the loading bricks).
  final Widget? below;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final art = this.art;
    final detail = this.detail;
    final below = this.below;
    final onRetry = this.onRetry;
    final bottom = 16 + MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(36, 0, 36, bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: math.max(0, box.maxHeight - bottom)),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 96),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ?art,
                if (icon != null)
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(color: iconTint, shape: BoxShape.circle),
                    child: Icon(icon, size: 36, color: iconColor),
                  ),
                const SizedBox(height: 14),
                Text(text.english,
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.25)),
                if (detail != null) ...[
                  const SizedBox(height: 6),
                  Text(detail, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15.5, color: WmColors.textSecondary)),
                ],
                const SizedBox(height: 8),
                Text(text.tagalog,
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 14.5, height: 1.4, color: WmColors.textMuted)),
                if (below != null) ...[const SizedBox(height: 14), below],
                if (onRetry != null) ...[
                  const SizedBox(height: 22),
                  FilledButton(
                    key: const Key('agreements-retry'),
                    onPressed: onRetry,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 6),
                      backgroundColor: WmColors.green,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(agreementsRetry.english, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.1)),
                      Text(agreementsRetry.tagalog,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _heroSoft, height: 1.2)),
                    ]),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asking the server; no figure is on screen meanwhile. The house draws
/// itself, the worker hammers and the bricks pulse (the loading screen's own
/// drawings); with animations switched off on the phone, it all stands still.
class _Checking extends StatefulWidget {
  const _Checking();

  @override
  State<_Checking> createState() => _CheckingState();
}

class _CheckingState extends State<_Checking> with SingleTickerProviderStateMixin {
  /// 33.6 s holds whole cycles of the house (2 × 2.4 s), the bricks (1.4 s)
  /// and the hammer (0.8 s), so the loop has no seam.
  static const _loop = 33.6;

  late final AnimationController _clock =
      AnimationController(vsync: this, duration: Duration(milliseconds: (_loop * 1000).round()));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Centred(
        key: const Key('agreements-checking'),
        text: agreementsChecking,
        art: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedBuilder(animation: _clock, builder: (context, _) => _site(_seconds)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: WmColors.brownTint, borderRadius: BorderRadius.circular(6)),
            child: Text('SYNCING', style: monoLabel.copyWith(fontSize: 11.5, letterSpacing: 1.6, color: WmColors.brown)),
          ),
        ]),
        below: AnimatedBuilder(
          animation: _clock,
          builder: (context, _) => CustomPaint(
            size: const Size(152, 16),
            painter: BarsPainter(gap: 4, radius: 1.5, bars: [for (var i = 0; i < 12; i++) _brick(_seconds, i)]),
          ),
        ),
      );

  /// Null while standing still: the finished house, the worker at rest.
  double? get _seconds => _clock.isAnimating ? _clock.value * _loop : null;

  Widget _site(double? s) => SizedBox(
        width: 150,
        height: 96,
        child: Stack(children: [
          Positioned(
            left: 0,
            top: 0,
            width: 96,
            height: 96,
            child: CustomPaint(
              painter: HouseMarkPainter(progress: s == null ? null : _houseProgress(s), ink: WmColors.green, door: _brickOn),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            width: 42,
            height: 60,
            child: CustomPaint(
              painter: WorkerPainter(tick: (s ?? 0) * 20, pose: s == null ? WorkerPose.idle : WorkerPose.hammering, onLight: true),
            ),
          ),
        ]),
      );

  /// Draws over 55% of each 2.4 s, holds, then undraws the same way.
  static double _houseProgress(double s) {
    const half = 2.4;
    final cycle = s % (2 * half);
    final k = cycle < half ? cycle / half : 1 - (cycle - half) / half;
    return Curves.easeInOut.transform((k / .55).clamp(0.0, 1.0));
  }

  static const _brickOff = Color(0xFFE8DFCC);
  static const _brickOn = Color(0xFFA8865A);

  /// Each brick swells and darkens in turn, 0.09 s after the one before.
  static Bar _brick(double? s, int i) {
    final local = s == null ? -1.0 : s - i * .09;
    if (local < 0) return (height: 7.0, color: _brickOff);
    final t = (local % 1.4) / 1.4;
    final f = t < .3
        ? Curves.easeInOut.transform(t / .3)
        : t < .6
            ? 1 - Curves.easeInOut.transform((t - .3) / .3)
            : 0.0;
    return (height: 7 * (1 + .9 * f), color: Color.lerp(_brickOff, _brickOn, f)!);
  }
}

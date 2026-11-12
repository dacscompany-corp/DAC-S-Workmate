import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../domain/attendance_record.dart';
import '../domain/history.dart';
import '../domain/total_hours.dart';
import '../ui/attendance_failure_notice.dart';
import '../ui/formats.dart';
import 'day_sheet.dart';
import 'history_controller.dart';

/// A link for one attendance photo, or null (no photo yet / no signal).
typedef PhotoUrl = Future<String?> Function(String? path);

/// History: the worker's own days, week or month, with the gaps showing
/// (redesign Phase 4). A recorded day opens its sheet, where the photos are.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.controller, required this.photoUrl});
  final HistoryController controller;
  final PhotoUrl photoUrl;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          final failure = c.failure;
          return RefreshIndicator(
            onRefresh: c.refresh,
            child: ListView(
              // Without this a short list cannot be pulled, so refresh would do nothing.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                const Text('My attendance', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                const Text('Your recorded days', style: TextStyle(fontSize: 14, color: WmColors.textMuted)),
                const SizedBox(height: 14),
                _SpanSwitch(span: c.span, onChanged: c.setSpan),
                const SizedBox(height: 14),
                if (failure != null)
                  AttendanceFailureNotice(failure: failure, onRetry: c.refresh)
                else if (c.loading)
                  const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator()))
                else ...[
                  _SummaryCard(summary: c.summary, span: c.span),
                  const SizedBox(height: 12),
                  for (final day in c.days) ...[
                    _DayCard(day: day, photoUrl: photoUrl),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ),
          );
        },
      );
}

/// Week / Month as one switch: a grey track, the chosen half white.
class _SpanSwitch extends StatelessWidget {
  const _SpanSwitch({required this.span, required this.onChanged});
  final HistorySpan span;
  final ValueChanged<HistorySpan> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: WmColors.inert, borderRadius: BorderRadius.circular(999)),
        child: Row(children: [
          for (final (s, label) in const [(HistorySpan.week, 'Week'), (HistorySpan.month, 'Month')]) ...[
            if (s != HistorySpan.week) const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                key: Key('span-${s.name}'),
                button: true,
                selected: s == span,
                child: Material(
                  color: s == span ? Colors.white : Colors.transparent,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => onChanged(s),
                    child: SizedBox(
                      height: 38,
                      child: Center(
                        child: Text(label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: s == span ? FontWeight.w800 : FontWeight.w600,
                              color: s == span ? WmColors.text : WmColors.textMuted,
                            )),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ]),
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.span});
  final HistorySummary summary;
  final HistorySpan span;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: WmColors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(daysWorked(summary.daysWorked), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              Text(span == HistorySpan.week ? 'this week' : 'this month',
                  style: const TextStyle(fontSize: 13.5, color: WmColors.textMuted)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(formatMinutes(summary.totalMinutes),
                style: const TextStyle(fontFamily: 'IBM Plex Mono', fontSize: 22, fontWeight: FontWeight.w700)),
            const Text('total', style: TextStyle(fontSize: 13.5, color: WmColors.textMuted)),
          ]),
        ]),
      );
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.photoUrl});
  final HistoryDay day;
  final PhotoUrl photoUrl;

  @override
  Widget build(BuildContext context) {
    final heading = dayHeading(day.date);
    final record = day.record;
    if (record == null) {
      // A filled block, not an empty card: it reads as a gap in the list.
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(color: WmColors.vacant, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Expanded(child: Text(heading, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: WmColors.textMuted))),
          const Text('No record', style: TextStyle(fontSize: 14, color: WmColors.textDisabled)),
        ]),
      );
    }
    final open = record.status == AttendanceStatus.working;
    final pills = dayPills(record);
    final place = dayPlace(record);
    return Material(
      key: Key('day-${record.workDate}'),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        // The open day wears a green edge: it is the one still in play.
        side: BorderSide(color: open ? WmColors.greenBorder : WmColors.border, width: open ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showDaySheet(context, heading: heading, record: record, photoUrl: photoUrl),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(heading, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              for (final p in pills) ...[const SizedBox(width: 6), p],
            ]),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _Leg(label: 'Time In', icon: Icons.south_west, accent: WmColors.green, time: record.timeInAt)),
              const SizedBox(width: 8),
              Expanded(child: _Leg(label: 'Time Out', icon: Icons.north_east, accent: WmColors.brown, time: record.timeOutAt)),
            ]),
            if (place != null) ...[
              const SizedBox(height: 8),
              Text(place, style: const TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// One leg on a day card: its round icon, the label and the time.
class _Leg extends StatelessWidget {
  const _Leg({required this.label, required this.icon, required this.accent, required this.time});

  final String label;
  final IconData icon;
  final Color accent;
  final DateTime? time;

  @override
  Widget build(BuildContext context) {
    final t = time;
    return Row(children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: t != null ? accent.withValues(alpha: 0.12) : WmColors.canvas, shape: BoxShape.circle),
        child: Icon(icon, size: 16, color: t != null ? accent : WmColors.textFaint),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 12, color: t != null ? WmColors.textSecondary : WmColors.textDisabled)),
          Text(
            t != null ? clockTime(t) : 'not yet',
            style: t != null
                ? const TextStyle(fontFamily: 'IBM Plex Mono', fontSize: 14.5, fontWeight: FontWeight.w700)
                : const TextStyle(fontSize: 14, color: WmColors.textDisabled),
          ),
        ]),
      ),
    ]);
  }
}

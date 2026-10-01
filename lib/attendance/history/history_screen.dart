import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../domain/attendance_record.dart';
import '../domain/history.dart';
import '../domain/total_hours.dart';
import '../ui/attendance_failure_notice.dart';
import '../ui/formats.dart';
import '../ui/status_pill.dart';
import 'history_controller.dart';
import 'photo_viewer.dart';

/// A link for one attendance photo, or null (no photo yet / no signal).
typedef PhotoUrl = Future<String?> Function(String? path);

/// History: the worker's own days, week or month, with the gaps showing.
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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                const Text('My attendance', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
                const Text('Your recorded days', style: TextStyle(fontSize: 14, color: WmColors.textMuted)),
                const SizedBox(height: 14),
                Row(children: [
                  _SpanButton(label: 'Week', selected: c.span == HistorySpan.week, onTap: () => c.setSpan(HistorySpan.week)),
                  const SizedBox(width: 8),
                  _SpanButton(label: 'Month', selected: c.span == HistorySpan.month, onTap: () => c.setSpan(HistorySpan.month)),
                ]),
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
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
          );
        },
      );
}

class _SpanButton extends StatelessWidget {
  const _SpanButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? WmColors.text : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: selected ? WmColors.text : WmColors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            child: Text(label,
                style: TextStyle(fontWeight: FontWeight.w700, color: selected ? Colors.white : WmColors.textSecondary)),
          ),
        ),
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

/// A finished day shows its hours; an open one "Working"; one an admin
/// closed without a Time Out, "Not closed".
Widget? _dayPill(AttendanceRecord r) => switch (r.status) {
      AttendanceStatus.working => const StatusPill.green('Working'),
      AttendanceStatus.abandoned => const StatusPill.brown('Not closed'),
      _ when r.totalMinutes != null => StatusPill.green(formatMinutes(r.totalMinutes)),
      _ => null,
    };

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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: WmColors.vacant, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Expanded(child: Text(heading, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: WmColors.textMuted))),
          const Text('No record', style: TextStyle(fontSize: 14, color: WmColors.textDisabled)),
        ]),
      );
    }
    final open = record.status == AttendanceStatus.working;
    final timeOutAt = record.timeOutAt;
    final pill = _dayPill(record);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        // The open day wears a green edge: it is the one still in play.
        border: Border.all(color: open ? WmColors.greenBorder : WmColors.border, width: open ? 1.5 : 1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(heading, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          if (record.pending) ...[const StatusPill.brown('Not sent yet'), const SizedBox(width: 6)],
          ?pill,
        ]),
        const SizedBox(height: 11),
        _LegRow(
          label: 'Time In',
          icon: Icons.south_west,
          accent: WmColors.green,
          time: record.timeInAt,
          project: record.timeInProjectName,
          photoPath: record.timeInPhotoPath,
          heading: heading,
          photoUrl: photoUrl,
        ),
        const SizedBox(height: 8),
        _LegRow(
          label: 'Time Out',
          icon: Icons.north_east,
          accent: WmColors.brown,
          time: timeOutAt,
          // A leg that has not happened must not name a place.
          project: timeOutAt == null ? null : record.timeOutProjectName,
          photoPath: record.timeOutPhotoPath,
          heading: heading,
          photoUrl: photoUrl,
        ),
      ]),
    );
  }
}

class _LegRow extends StatelessWidget {
  const _LegRow({
    required this.label,
    required this.icon,
    required this.accent,
    required this.time,
    required this.project,
    required this.photoPath,
    required this.heading,
    required this.photoUrl,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final DateTime? time;
  final String? project;
  final String? photoPath;
  final String heading;
  final PhotoUrl photoUrl;

  @override
  Widget build(BuildContext context) {
    final t = time;
    final place = project;
    final path = photoPath;
    return Row(children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: t != null ? accent.withValues(alpha: 0.12) : WmColors.canvas, shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: t != null ? accent : WmColors.textFaint),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 13, color: t != null ? WmColors.textSecondary : WmColors.textDisabled)),
          Text(
            t != null ? clockTime(t) : 'not yet',
            style: t != null
                ? const TextStyle(fontFamily: 'IBM Plex Mono', fontSize: 15, fontWeight: FontWeight.w700)
                : const TextStyle(fontSize: 14, color: WmColors.textDisabled),
          ),
          if (place != null) Text(place, style: const TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
        ]),
      ),
      if (path != null)
        _Thumb(path: path, photoUrl: photoUrl, heading: heading, caption: t == null ? label : '$label · ${clockTime(t)}'),
    ]);
  }
}

/// A photo thumbnail, its link resolved once as the card is built — so a
/// month of history costs only the days the worker scrolls past.
class _Thumb extends StatefulWidget {
  const _Thumb({required this.path, required this.photoUrl, required this.heading, required this.caption});
  final String path;
  final PhotoUrl photoUrl;
  final String heading;
  final String caption;

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  late Future<String?> _url = widget.photoUrl(widget.path);

  @override
  void didUpdateWidget(covariant _Thumb old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _url = widget.photoUrl(widget.path);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: _url,
        builder: (context, snapshot) {
          final url = snapshot.data;
          final box = ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 52,
              height: 52,
              child: url == null
                  ? const ColoredBox(color: WmColors.canvas, child: Icon(Icons.photo_outlined, color: WmColors.textFaint))
                  : Image.network(url, fit: BoxFit.cover, cacheWidth: 160, errorBuilder: (_, _, _) => const ColoredBox(color: WmColors.canvas)),
            ),
          );
          if (url == null) return box;
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => PhotoViewer(image: NetworkImage(url), heading: widget.heading, caption: widget.caption),
            )),
            child: box,
          );
        },
      );
}

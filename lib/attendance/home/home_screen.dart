import 'dart:async';

import 'package:flutter/material.dart';

import '../../auth/worker_profile.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../../ui/worker_header.dart';
import '../domain/attendance_failure.dart';
import '../domain/attendance_record.dart';
import '../domain/history.dart';
import '../domain/work_date.dart';
import '../ui/attendance_copy.dart';
import '../ui/attendance_failure_notice.dart';
import '../ui/formats.dart';
import '../ui/status_pill.dart';
import 'home_controller.dart';

/// Home: today's record and the one thing to do next. Ported from DACS
/// Attendance's DashboardScreen (the weekly reward strip arrives in 0D).
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.worker,
    required this.controller,
    required this.onStartFlow,
    required this.onSeeHistory,
    required this.openSettings,
    this.exitNotice,
    this.onDismissExit,
  });

  final WorkerProfile worker;
  final HomeController controller;
  final void Function(TimeDirection direction) onStartFlow;
  final VoidCallback onSeeHistory;
  final void Function(SettingsRoute route) openSettings;

  /// Why the last flow recorded nothing (a declined camera), until dismissed.
  final Bilingual? exitNotice;
  final VoidCallback? onDismissExit;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The live "Hours so far". A minute is the smallest unit anyone reads.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (widget.controller.working) widget.controller.tick();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          final now = c.now();
          final failure = c.failure;
          final exit = widget.exitNotice;
          return RefreshIndicator(
            onRefresh: c.refresh,
            child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
              WorkerHeader(worker: widget.worker),
              const SizedBox(height: 18),
              Text(weekdayName(now).toUpperCase(),
                  style: const TextStyle(fontSize: 12.5, letterSpacing: 0.6, color: WmColors.textMuted, fontWeight: FontWeight.w600)),
              Text(longDate(now), style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              if (exit != null) ...[
                FailureNotice(
                  english: exit.english,
                  tagalog: exit.tagalog,
                  actions: [noticeAction(dismissLabel, widget.onDismissExit ?? () {})],
                ),
                const SizedBox(height: 12),
              ],
              for (final p in c.refused) ...[
                AttendanceFailureNotice(
                  failure: failureFromStored(p.lastError),
                  lead: refusedLead(TimeDirection.parse(p.direction), dayMonth(p.capturedAt)),
                  onDismiss: () => c.dismissRefused(p.eventId),
                ),
                const SizedBox(height: 12),
              ],
              if (failure != null) ...[
                AttendanceFailureNotice(failure: failure, onRetry: c.refresh, onOpenSettings: widget.openSettings),
                const SizedBox(height: 12),
              ],
              ..._today(c, failure),
              const SizedBox(height: 20),
              _WeekStrip(cells: c.week, onSeeAll: widget.onSeeHistory),
            ]),
          );
        },
      );

  List<Widget> _today(HomeController c, AttendanceFailure? failure) {
    if (c.loading) {
      return const [Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator()))];
    }
    final record = c.record;
    if (record == null) {
      return [
        // The BUTTON follows nextAction (still offered with no signal); the
        // CARD claims "not timed in" only once the day was actually read.
        if (c.nextAction != null) ...[
          _HeroAction(direction: TimeDirection.timeIn, onTap: () => widget.onStartFlow(TimeDirection.timeIn)),
          const SizedBox(height: 12),
        ],
        if (failure == null)
          const _NoticeCard(icon: Icons.schedule, title: 'You have not timed in yet', subtitle: 'Tap Time In when you arrive'),
      ];
    }
    return [
      _TimedInCard(controller: c, record: record),
      const SizedBox(height: 12),
      if (c.nextAction == TimeDirection.timeOut)
        _HeroAction(direction: TimeDirection.timeOut, onTap: () => widget.onStartFlow(TimeDirection.timeOut))
      // A closed day (or one we could not read): offering Time In could only fail.
      else if (failure == null)
        const _NoticeCard(
          icon: Icons.check,
          title: 'Day complete',
          subtitle: 'Thank you. See you tomorrow.',
          tint: WmColors.greenTint,
          iconColor: WmColors.green,
        ),
    ];
  }
}

class _HeroAction extends StatelessWidget {
  const _HeroAction({required this.direction, required this.onTap});
  final TimeDirection direction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final timeIn = direction == TimeDirection.timeIn;
    return Material(
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: timeIn ? const [WmColors.green, WmColors.greenDeep] : const [WmColors.brownLight, WmColors.brownDeep],
          ),
        ),
        child: InkWell(
          key: Key(timeIn ? 'hero-time-in' : 'hero-time-out'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (timeIn) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(999)),
                  child: Text('STEP 1 OF 4', style: monoLabel.copyWith(color: Colors.white, fontSize: 11)),
                ),
                const SizedBox(height: 14),
              ],
              Row(children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                  child: Icon(timeIn ? Icons.south_west : Icons.north_east, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(timeIn ? 'Time In' : 'Time Out',
                        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                    Text(timeIn ? 'Tap to start your day' : 'Tap when you are heading home',
                        style: const TextStyle(color: Colors.white70, fontSize: 14.5)),
                  ]),
                ),
              ]),
              if (timeIn) ...[
                const SizedBox(height: 14),
                Text('project · photo · check · submit', style: monoLabel.copyWith(color: Colors.white70, letterSpacing: 0.3)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.tint = WmColors.canvas,
    this.iconColor = WmColors.textMuted,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color tint;
  final Color iconColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: WmColors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(subtitle, style: const TextStyle(fontSize: 13.5, color: WmColors.textMuted)),
            ]),
          ),
        ]),
      );
}

class _TimedInCard extends StatelessWidget {
  const _TimedInCard({required this.controller, required this.record});
  final HomeController controller;
  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final timeIn = record.timeInAt;
    final minutes = c.minutes;
    final project = record.timeInProjectName;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: WmColors.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(timeIn != null ? 'Timed in at ${clockTime(timeIn)}' : 'Working',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              if (project != null) Text(project, style: const TextStyle(fontSize: 13.5, color: WmColors.textMuted)),
            ]),
          ),
          record.pending ? const StatusPill.brown('Not sent yet') : const StatusPill.green('Saved'),
        ]),
        const SizedBox(height: 14),
        Text(c.complete ? 'Total hours' : 'Hours so far', style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
        Text(c.hoursLabel, style: const TextStyle(fontFamily: 'IBM Plex Mono', fontSize: 30, fontWeight: FontWeight.w700)),
        if (c.working && timeIn != null)
          Text('Since ${clockTime(timeIn)}', style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            // An 8-hour day fills the bar.
            value: minutes == null ? 0 : (minutes / 480).clamp(0, 1).toDouble(),
            minHeight: 8,
            color: c.complete ? WmColors.brown : WmColors.green,
            backgroundColor: WmColors.hairline,
          ),
        ),
        if (record.pending) ...[
          const SizedBox(height: 10),
          // Reassurance, not a warning: the record is safe on the phone.
          const Text('Saved on this phone. It will send when there is signal.',
              style: TextStyle(fontSize: 13, color: WmColors.textMuted)),
        ],
      ]),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.cells, required this.onSeeAll});
  final List<WeekDayCell> cells;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('THIS WEEK', style: monoLabel),
          const Spacer(),
          TextButton(onPressed: onSeeAll, child: const Text('See all', style: TextStyle(fontWeight: FontWeight.w700))),
        ]),
        Row(children: [for (final cell in cells) Expanded(child: _WeekCell(cell: cell))]),
      ]);
}

class _WeekCell extends StatelessWidget {
  const _WeekCell({required this.cell});
  final WeekDayCell cell;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: cell.isToday ? WmColors.greenTint : Colors.white,
          border: Border.all(color: cell.isToday ? WmColors.green : WmColors.border, width: cell.isToday ? 1.5 : 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Text(
            cell.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: cell.isToday ? FontWeight.w800 : FontWeight.w600,
              color: cell.isToday
                  ? WmColors.green
                  : cell.future
                      ? WmColors.textDisabled
                      : WmColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            key: Key('week-dot-${isoDate(cell.date)}-${cell.worked ? 'worked' : 'empty'}'),
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: cell.worked ? WmColors.green : WmColors.border),
          ),
        ]),
      );
}

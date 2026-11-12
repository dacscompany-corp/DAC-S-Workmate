import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../../ui/wm_sheet.dart';
import '../domain/attendance_record.dart';
import '../domain/total_hours.dart';
import '../ui/formats.dart';
import '../ui/status_pill.dart';
import 'history_screen.dart' show PhotoUrl;
import 'photo_viewer.dart';

/// The pills of one recorded day: "Not sent yet" while it is still on the
/// phone, then its hours when finished, "Working" while open, or "Not closed"
/// when an admin closed it without a Time Out.
List<Widget> dayPills(AttendanceRecord r) => [
      if (r.pending) const StatusPill.brown('Not sent yet'),
      ...switch (r.status) {
        AttendanceStatus.working => const [StatusPill.green('Working')],
        AttendanceStatus.abandoned => const [StatusPill.brown('Not closed')],
        _ when r.totalMinutes != null => [StatusPill.green(formatMinutes(r.totalMinutes))],
        _ => const <Widget>[],
      },
    ];

/// Where the Time Out happened; a leg that has not happened names no place.
String? timeOutPlace(AttendanceRecord r) => r.timeOutAt == null ? null : r.timeOutProjectName;

/// One line for the day's place: the project, or both when they differ.
String? dayPlace(AttendanceRecord r) {
  final inP = r.timeInProjectName;
  final outP = timeOutPlace(r);
  if (inP == null && outP == null) return null;
  if (outP == null || outP == inP) return inP;
  if (inP == null) return 'Out: $outP';
  return 'In: $inP · Out: $outP';
}

/// Opens one recorded day (redesign Phase 4 spec §4).
Future<void> showDaySheet(BuildContext context, {required String heading, required AttendanceRecord record, required PhotoUrl photoUrl}) =>
    showWmSheet<void>(context, builder: (_) => DaySheet(heading: heading, record: record, photoUrl: photoUrl));

/// One day as a swipe-down sheet: its pills, then Time In and Time Out side by
/// side, each with its photo large. The photo links are asked for here, when
/// the day is opened — never for the whole list.
class DaySheet extends StatelessWidget {
  const DaySheet({super.key, required this.heading, required this.record, required this.photoUrl});

  final String heading;
  final AttendanceRecord record;
  final PhotoUrl photoUrl;

  @override
  Widget build(BuildContext context) {
    final pills = dayPills(record);
    return WmSheetFrame(
      key: const Key('day-sheet'),
      title: heading,
      children: [
        if (pills.isNotEmpty) ...[Wrap(spacing: 6, runSpacing: 6, children: pills), const SizedBox(height: 12)],
        // Equal heights, even when one project name wraps or a leg has no place.
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: _PhotoCard(
              keyName: 'day-photo-in',
              label: 'Time In',
              time: record.timeInAt,
              place: record.timeInProjectName,
              path: record.timeInPhotoPath,
              heading: heading,
              photoUrl: photoUrl,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _PhotoCard(
              keyName: 'day-photo-out',
              label: 'Time Out',
              time: record.timeOutAt,
              place: timeOutPlace(record),
              path: record.timeOutPhotoPath,
              heading: heading,
              photoUrl: photoUrl,
            ),
          ),
        ])),
      ],
    );
  }
}

class _PhotoCard extends StatefulWidget {
  const _PhotoCard({
    required this.keyName,
    required this.label,
    required this.time,
    required this.place,
    required this.path,
    required this.heading,
    required this.photoUrl,
  });

  final String keyName;
  final String label;
  final DateTime? time;
  final String? place;
  final String? path;
  final String heading;
  final PhotoUrl photoUrl;

  @override
  State<_PhotoCard> createState() => _PhotoCardState();
}

class _PhotoCardState extends State<_PhotoCard> {
  /// Asked once, and only when there is a photo to ask for.
  late final Future<String?> _url = widget.path == null ? Future.value() : widget.photoUrl(widget.path);

  static const _gap = ColoredBox(
    color: WmColors.canvas,
    child: Center(child: Icon(Icons.photo_outlined, size: 32, color: WmColors.textFaint)),
  );

  @override
  Widget build(BuildContext context) {
    final t = widget.time;
    final place = widget.place;
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: WmColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 120,
          child: FutureBuilder<String?>(
            future: _url,
            builder: (context, snapshot) {
              final url = snapshot.data;
              if (url == null) return _gap;
              // The ink sits above the photo, so the tap shows; TalkBack hears what it opens.
              return Semantics(
                button: true,
                label: '${widget.label} photo, open full screen',
                excludeSemantics: true,
                child: Stack(fit: StackFit.expand, children: [
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    cacheWidth: 600,
                    loadingBuilder: (_, child, progress) => progress == null ? child : _gap,
                    errorBuilder: (_, _, _) => _gap,
                  ),
                  Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      key: Key(widget.keyName),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => PhotoViewer(
                          image: NetworkImage(url),
                          heading: widget.heading,
                          caption: t == null ? widget.label : '${widget.label} · ${clockTime(t)}',
                        ),
                      )),
                    ),
                  ),
                ]),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.label, style: TextStyle(fontSize: 12.5, color: t != null ? WmColors.textSecondary : WmColors.textDisabled)),
            Text(
              t != null ? clockTime(t) : 'not yet',
              style: t != null
                  ? const TextStyle(fontFamily: 'IBM Plex Mono', fontSize: 16, fontWeight: FontWeight.w700)
                  : const TextStyle(fontSize: 14, color: WmColors.textDisabled),
            ),
            if (place != null) Text(place, style: const TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
          ]),
        ),
      ]),
    );
  }
}

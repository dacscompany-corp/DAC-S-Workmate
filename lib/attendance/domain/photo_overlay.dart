import 'work_date.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Beyond this the caption stops fitting on one line across the photo.
const maxProjectChars = 32;

/// "1 Sep 2026 · 3:00 PM", Manila time — matching the work_date the record
/// files under.
String photoOverlayStamp(DateTime capturedAt) {
  final t = manilaFields(capturedAt);
  final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final amPm = t.hour < 12 ? 'AM' : 'PM';
  return '${t.day} ${_months[t.month - 1]} ${t.year} · $hour12:${t.minute.toString().padLeft(2, '0')} $amPm';
}

/// The caption split where it is safe to break: the project name (truncated,
/// never the timestamp), then the stamp.
(String, String) photoOverlayCaptionLines(String projectName, DateTime capturedAt) {
  final project = projectName.length <= maxProjectChars
      ? projectName
      : '${projectName.substring(0, maxProjectChars).trimRight()}…';
  return (project, photoOverlayStamp(capturedAt));
}

/// The one-line caption burned into the attendance photo:
/// "ABC Building Project · 19 Aug 2026 · 7:45 AM".
String photoOverlayCaption(String projectName, DateTime capturedAt) {
  final (project, stamp) = photoOverlayCaptionLines(projectName, capturedAt);
  return '$project · $stamp';
}

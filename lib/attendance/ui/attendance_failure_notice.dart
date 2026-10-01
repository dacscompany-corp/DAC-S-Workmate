import 'package:flutter/material.dart';

import '../../ui/failure_notice.dart';
import '../domain/attendance_failure.dart';
import 'attendance_copy.dart';

/// Why a Time In or Time Out was refused, in both languages. TRY AGAIN only
/// where retrying can help; Open Settings only for the two settings a worker
/// can fix themselves; Dismiss when there is nothing left to do but read it.
class AttendanceFailureNotice extends StatelessWidget {
  const AttendanceFailureNotice({
    super.key,
    required this.failure,
    this.lead,
    this.onRetry,
    this.onOpenSettings,
    this.onDismiss,
  });

  final AttendanceFailure failure;
  final Bilingual? lead;
  final VoidCallback? onRetry;
  final void Function(SettingsRoute route)? onOpenSettings;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final copy = failureCopy(failure);
    final route = settingsRouteFor(failure);
    final retry = onRetry;
    final open = onOpenSettings;
    final dismiss = onDismiss;
    return FailureNotice(
      english: copy.english,
      tagalog: copy.tagalog,
      leadEnglish: lead?.english,
      leadTagalog: lead?.tagalog,
      actions: [
        if (route != null && open != null) noticeAction(openSettingsLabel, () => open(route)),
        if (retry != null && worthRetrying(failure)) noticeAction(retryLabel, retry),
        if (dismiss != null) noticeAction(dismissLabel, dismiss),
      ],
    );
  }
}

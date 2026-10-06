import 'package:flutter/material.dart';

import '../../attendance/ui/status_pill.dart';
import '../../ui/theme.dart';
import '../domain/request_status.dart';
import 'requests_copy.dart';

/// The design's state colours: grey draft (and cancelled: nothing more will
/// happen), brown waiting, green received, red for anything that needs someone.
class SyncChip extends StatelessWidget {
  const SyncChip(this.state, {super.key});
  final SyncState state;

  static const _draftFg = Color(0xFF5F5F5B);

  @override
  Widget build(BuildContext context) => switch (state) {
        SyncState.draft || SyncState.cancelled => StatusPill(syncLabel(state), background: WmColors.inert, foreground: _draftFg),
        SyncState.pending => StatusPill.brown(syncLabel(state)),
        SyncState.received => StatusPill.green(syncLabel(state)),
        SyncState.failed || SyncState.needsResolution =>
          StatusPill(syncLabel(state), background: WmColors.dangerTint, foreground: WmColors.danger),
      };
}

/// "URGENT · by Wed 7 Oct".
class UrgentTag extends StatelessWidget {
  const UrgentTag({super.key, this.neededBy});
  final String? neededBy;

  @override
  Widget build(BuildContext context) => StatusPill(
        neededBy == null ? 'URGENT' : 'URGENT · by ${calendarDay(neededBy!)}',
        background: WmColors.dangerTint,
        foreground: WmColors.danger,
      );
}

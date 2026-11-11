import 'package:flutter/material.dart';

import '../auth/worker_profile.dart';
import 'theme.dart';

/// Who is signed in: initials, name, position and worker ID ([subtitle]
/// instead, for a buyer: an office account has no worker ID).
class WorkerHeader extends StatelessWidget {
  const WorkerHeader({super.key, required this.worker, this.subtitle, this.trailing});
  final WorkerProfile worker;
  final String? subtitle;

  /// At the right end of the row (Home's sync badge).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: WmColors.green,
          child: Text(worker.initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(worker.displayName ?? worker.firstName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            Text(subtitle ?? worker.positionAndId, style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
          ]),
        ),
        if (trailing case final t?) ...[const SizedBox(width: 8), t],
      ]);
}

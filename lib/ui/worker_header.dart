import 'package:flutter/material.dart';

import '../auth/worker_profile.dart';
import 'theme.dart';

/// Who is signed in: initials, name, position and worker ID.
class WorkerHeader extends StatelessWidget {
  const WorkerHeader({super.key, required this.worker});
  final WorkerProfile worker;

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
            Text(worker.positionAndId, style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
          ]),
        ),
      ]);
}

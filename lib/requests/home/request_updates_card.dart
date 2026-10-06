import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../domain/request_status.dart';
import 'request_updates.dart';

/// Home's request card (spec §5): what needs the worker first, then what is
/// still on the phone, then the next delivery. Nothing to say → nothing shown.
class RequestUpdatesCard extends StatelessWidget {
  const RequestUpdatesCard({super.key, required this.updates, required this.onOpen});

  final RequestUpdates updates;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final u = updates;
    if (u.isEmpty) return const SizedBox.shrink();
    final lines = <(IconData, String, Color)>[
      if (u.needsAction > 0) (Icons.report_outlined, '${u.needsAction} need${u.needsAction == 1 ? 's' : ''} your attention', WmColors.danger),
      if (u.pending > 0) (Icons.cloud_off, '${u.pending} waiting for signal', WmColors.brown),
      if (u.drafts > 0) (Icons.edit_note, '${u.drafts} draft${u.drafts == 1 ? '' : 's'} not sent', WmColors.textSecondary),
      if (u.nextDelivery != null) (Icons.local_shipping_outlined, 'Next delivery ${calendarDay(u.nextDelivery!)}', WmColors.green),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: InkWell(
        key: const Key('request-updates'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: WmColors.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Expanded(child: Text('Requests', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              Icon(Icons.chevron_right, color: WmColors.textMuted),
            ]),
            const SizedBox(height: 6),
            for (final (icon, text, color) in lines)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

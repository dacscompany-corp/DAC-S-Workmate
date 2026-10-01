import 'package:flutter/material.dart';

import '../../ui/theme.dart';

/// "Saved", "Not sent yet", "Working", "9h 45m".
class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, required this.background, required this.foreground});
  const StatusPill.green(this.text, {super.key})
      : background = WmColors.greenTint,
        foreground = WmColors.green;
  const StatusPill.brown(this.text, {super.key})
      : background = WmColors.brownTint,
        foreground = WmColors.brown;

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: foreground)),
      );
}

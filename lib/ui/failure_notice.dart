import 'package:flutter/material.dart';

import 'theme.dart';

/// Screen copy is English; failure copy is bilingual (English, then Tagalog).
class FailureNotice extends StatelessWidget {
  const FailureNotice({super.key, required this.english, required this.tagalog});
  final String english;
  final String tagalog;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: WmColors.dangerTint,
          border: Border.all(color: WmColors.dangerBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(english, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: WmColors.danger)),
          const SizedBox(height: 3),
          Text(tagalog, style: const TextStyle(fontSize: 13, color: WmColors.danger)),
        ]),
      );
}

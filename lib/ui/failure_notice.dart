import 'package:flutter/material.dart';

import 'theme.dart';

/// Screen copy is English; failure copy is bilingual (English, then Tagalog).
/// An optional lead line says what happened, then the reason, then the
/// actions a worker can take.
class FailureNotice extends StatelessWidget {
  const FailureNotice({
    super.key,
    required this.english,
    required this.tagalog,
    this.leadEnglish,
    this.leadTagalog,
    this.actions = const [],
  });

  final String english;
  final String tagalog;
  final String? leadEnglish;
  final String? leadTagalog;
  final List<Widget> actions;

  static const _bold = TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: WmColors.danger);
  static const _plain = TextStyle(fontSize: 13, color: WmColors.danger);

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(16, 14, 16, actions.isEmpty ? 14 : 4),
        decoration: BoxDecoration(
          color: WmColors.dangerTint,
          border: Border.all(color: WmColors.dangerBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (leadEnglish != null) ...[Text(leadEnglish!, style: _bold), const SizedBox(height: 2)],
          if (leadTagalog != null) ...[Text(leadTagalog!, style: _plain), const SizedBox(height: 8)],
          Text(english, style: _bold),
          const SizedBox(height: 3),
          Text(tagalog, style: _plain),
          if (actions.isNotEmpty) Wrap(spacing: 4, children: actions),
        ]),
      );
}

/// A text action inside a notice. Its label is bilingual ("Dismiss · Isara").
Widget noticeAction(String label, VoidCallback onPressed) => TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: WmColors.danger, padding: const EdgeInsets.symmetric(horizontal: 4)),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );

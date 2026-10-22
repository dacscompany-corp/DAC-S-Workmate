import 'package:flutter/material.dart';

import 'failure_notice.dart';

/// First launch with no signal: the Terms acceptance cannot be checked and is
/// never assumed. Accepting offline could not be written anywhere. Also used
/// (2A-3b) when whether an office account may buy cannot be checked.
class GateUnavailableScreen extends StatelessWidget {
  const GateUnavailableScreen({
    super.key,
    required this.onRetry,
    required this.onSignOut,
    this.title = 'Terms & Conditions',
    this.english = 'Connect to the internet once so WorkMate can check your Terms.',
    this.tagalog = 'Kumonekta muna sa internet para ma-check ng WorkMate ang Terms mo.',
  });
  final VoidCallback onRetry;
  final VoidCallback onSignOut;
  final String title;
  final String english;
  final String tagalog;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 23)),
              const SizedBox(height: 16),
              FailureNotice(english: english, tagalog: tagalog),
              const SizedBox(height: 24),
              FilledButton(onPressed: onRetry, child: const Text('TRY AGAIN')),
              const SizedBox(height: 8),
              TextButton(onPressed: onSignOut, child: const Text('Log out')),
            ]),
          ),
        ),
      );
}

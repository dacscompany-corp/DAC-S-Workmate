import 'package:flutter/material.dart';

import '../attendance/ui/formats.dart';
import '../auth/login_failure.dart';
import '../terms/attendance_terms.dart';
import 'failure_notice.dart';
import 'theme.dart';

/// The numbered clauses, English then Tagalog. One list for the first-login
/// screen and the read-only copy on Profile, so the two can never differ.
List<Widget> termsClauseWidgets() => [
      for (var i = 0; i < AttendanceTerms.clauses.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${i + 1}. ${AttendanceTerms.clauses[i].heading}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 4),
            Text(AttendanceTerms.clauses[i].english, style: const TextStyle(fontSize: 14.5, height: 1.4)),
            const SizedBox(height: 4),
            Text(AttendanceTerms.clauses[i].tagalog, style: const TextStyle(fontSize: 13.5, height: 1.4, color: WmColors.textMuted)),
          ]),
        ),
    ];

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key, required this.onAccept});

  /// Returns the failure to show, or null when accepted.
  final Future<LoginFailure?> Function() onAccept;

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  bool _agreed = false;
  bool _busy = false;
  LoginFailure? _failure;

  Future<void> _accept() async {
    if (!_agreed || _busy) return;
    setState(() => _busy = true);
    final failure = await widget.onAccept();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 12), children: [
                const Text('Terms & Conditions', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 23)),
                const Text('You only need to do this once, on your first log in.',
                    style: TextStyle(fontSize: 15, color: WmColors.textMuted)),
                const SizedBox(height: 16),
                ...termsClauseWidgets(),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(children: [
                if (_failure != null) ...[
                  FailureNotice(english: _failure!.english, tagalog: _failure!.tagalog),
                  const SizedBox(height: 12),
                ],
                InkWell(
                  onTap: () => setState(() => _agreed = !_agreed),
                  child: Row(children: [
                    Icon(_agreed ? Icons.check_box : Icons.check_box_outline_blank, color: WmColors.green),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('I have read and I agree.', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        Text('Required before you continue.', style: TextStyle(fontSize: 13, color: WmColors.textMuted)),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _agreed && !_busy ? _accept : null, child: const Text('ACCEPT & CONTINUE')),
              ]),
            ),
          ]),
        ),
      );
}

/// The Terms the worker accepted, read-only, from Profile.
class TermsReaderScreen extends StatelessWidget {
  const TermsReaderScreen({super.key, this.acceptedAt});
  final DateTime? acceptedAt;

  @override
  Widget build(BuildContext context) {
    final at = acceptedAt;
    return Scaffold(
      appBar: AppBar(title: const Text('Terms & Conditions', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
        if (at != null) ...[
          Text('Accepted ${shortDate(at)}', style: const TextStyle(fontSize: 14, color: WmColors.textMuted)),
          const SizedBox(height: 14),
        ],
        ...termsClauseWidgets(),
      ]),
    );
  }
}

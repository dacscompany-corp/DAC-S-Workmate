import 'package:flutter/material.dart';

import '../auth/login_failure.dart';
import 'failure_notice.dart';
import 'theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onSignIn, this.initialNotice});

  /// Returns the failure to show, or null when signed in.
  final Future<LoginFailure?> Function(String email, String password) onSignIn;
  final LoginFailure? initialNotice;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _show = false;
  bool _busy = false;
  LoginFailure? _failure;

  @override
  void initState() {
    super.initState();
    _failure = widget.initialNotice;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final failure = await widget.onSignIn(_email.text, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 30, 24, 26), children: [
            const Row(children: [
              Icon(Icons.apartment, color: WmColors.green, size: 40),
              SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('WorkMate', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                Text("Dacs Building Design Services", style: TextStyle(fontSize: 13, color: WmColors.textMuted)),
              ]),
            ]),
            const SizedBox(height: 22),
            const Text('Welcome back', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 23)),
            const Text('Use the email your admin gave you. It is the same account as Attendance.',
                style: TextStyle(fontSize: 15, color: WmColors.textMuted)),
            const SizedBox(height: 22),
            const Text('Email', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: WmColors.textSecondary)),
            const SizedBox(height: 7),
            TextField(key: const Key('email'), controller: _email, keyboardType: TextInputType.emailAddress, autocorrect: false),
            const SizedBox(height: 16),
            const Text('Password', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: WmColors.textSecondary)),
            const SizedBox(height: 7),
            TextField(
              key: const Key('password'),
              controller: _password,
              obscureText: !_show,
              decoration: InputDecoration(
                suffixIcon: TextButton(onPressed: () => setState(() => _show = !_show), child: Text(_show ? 'Hide' : 'Show')),
              ),
            ),
            if (_failure != null) ...[
              const SizedBox(height: 16),
              FailureNotice(english: _failure!.english, tagalog: _failure!.tagalog),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('SIGN IN'),
            ),
            const SizedBox(height: 14),
            const Center(child: Text('No account? Call the office.', style: TextStyle(fontSize: 14, color: WmColors.textMuted))),
          ]),
        ),
      );
}

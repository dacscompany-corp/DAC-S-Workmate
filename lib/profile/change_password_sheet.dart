import 'package:flutter/material.dart';

import '../ui/failure_notice.dart';
import '../ui/theme.dart';
import 'password_change.dart';

/// Changing the password (design screen 11). Everything decidable without
/// the network is decided first; pops `true` once the server accepted.
class ChangePasswordSheet extends StatefulWidget {
  const ChangePasswordSheet({super.key, required this.onSave});
  final Future<void> Function(String newPassword) onSave;

  @override
  State<ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<ChangePasswordSheet> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  PasswordChangeFailure? _failure;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final local = PasswordChangeFailure.validate(_password.text, _confirm.text);
    if (local != null) return setState(() => _failure = local);
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await widget.onSave(_password.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = PasswordChangeFailure.of(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Change password', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 21)),
            const SizedBox(height: 6),
            const Text('Any 8 letters or numbers. Do not share it with anyone.',
                style: TextStyle(fontSize: 14, color: WmColors.textMuted)),
            const SizedBox(height: 16),
            TextField(
              key: const Key('new-password'),
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('confirm-password'),
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Type it again'),
              onSubmitted: (_) => _save(),
            ),
            if (failure != null) ...[
              const SizedBox(height: 12),
              FailureNotice(english: failure.english, tagalog: failure.tagalog),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('SAVE PASSWORD'),
            ),
          ]),
        ),
      ),
    );
  }
}

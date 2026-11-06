import 'package:flutter/material.dart';

import '../ui/failure_notice.dart';
import '../ui/theme.dart';
import 'password_change.dart';
import 'password_prompt.dart';

/// The forced change of a temporary password (3b, Q3; P1 = A). Full screen,
/// over Home, with no way past it while the server can be reached — but a save
/// that fails for a reason other than what was typed (no signal, the server's
/// fault, a lost session) offers "Continue for now": Home and Time In stay
/// reachable, and the prompt comes back once the server answers again. It
/// closes itself the moment the prompt is no longer wanted.
class SetOwnPasswordScreen extends StatefulWidget {
  const SetOwnPasswordScreen({super.key, required this.prompt, required this.onSignOut});

  final PasswordPrompt prompt;

  /// "Not you?": a shared phone. Signing out keeps the change owed.
  final Future<void> Function() onSignOut;

  @override
  State<SetOwnPasswordScreen> createState() => _SetOwnPasswordScreenState();
}

class _SetOwnPasswordScreenState extends State<SetOwnPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _leaving = false;
  PasswordChangeFailure? _failure;

  /// What was typed can be fixed; everything else may be continued past.
  static const _typing = {PasswordChangeFailure.tooShort, PasswordChangeFailure.mismatch, PasswordChangeFailure.reused};

  bool get _canContinue => _failure != null && !_typing.contains(_failure);

  @override
  void initState() {
    super.initState();
    widget.prompt.addListener(_follow);
  }

  @override
  void dispose() {
    widget.prompt.removeListener(_follow);
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// Done, paused, or no longer owed: this screen goes.
  void _follow() {
    if (!widget.prompt.wanted) _leave();
  }

  void _leave() {
    if (_leaving || !mounted) return;
    _leaving = true;
    Navigator.of(context).pop();
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
      await widget.prompt.save(_password.text);
      // The prompt is done (or only its record waits): _follow closes this.
    } catch (e) {
      if (mounted) setState(() => _failure = PasswordChangeFailure.of(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _continue() => widget.prompt.continueForNow(_failure ?? PasswordChangeFailure.noConnection);

  Future<void> _signOut() async {
    _leave();
    await widget.onSignOut();
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 28, 20, 20), children: [
            const Text('Set your own password', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 23)),
            const Text('Gumawa ng sarili mong password', style: TextStyle(fontSize: 13, color: WmColors.textMuted)),
            const SizedBox(height: 12),
            const Text('The office gave you a temporary password. Choose a new one that only you know: any 8 letters or numbers.',
                style: TextStyle(fontSize: 15)),
            const Text('Binigyan ka ng opisina ng pansamantalang password. Pumili ng bago na ikaw lang ang nakakaalam: kahit anong 8 letra o numero.',
                style: TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
            const SizedBox(height: 16),
            TextField(
              key: const Key('own-password'),
              controller: _password,
              obscureText: true,
              enabled: !_busy,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('own-password-again'),
              controller: _confirm,
              obscureText: true,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Type it again'),
              onSubmitted: (_) => _save(),
            ),
            if (failure != null) ...[
              const SizedBox(height: 12),
              FailureNotice(key: const Key('own-password-failure'), english: failure.english, tagalog: failure.tagalog),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('own-password-save'),
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('SAVE PASSWORD'),
            ),
            if (_canContinue && !_busy) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('own-password-continue'),
                onPressed: _continue,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('Continue for now', style: TextStyle(fontWeight: FontWeight.w800)),
                    Text('Ituloy muna', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
                  ]),
                ),
              ),
              const SizedBox(height: 6),
              const Text("You can still Time In. You'll be asked again when there's signal.",
                  style: TextStyle(fontSize: 13, color: WmColors.textSecondary)),
              const Text('Puwede ka pa ring mag-Time In. Itatanong ulit ito kapag may signal na.',
                  style: TextStyle(fontSize: 12, color: WmColors.textMuted)),
            ],
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(key: const Key('own-password-sign-out'), onPressed: _busy ? null : _signOut, child: const Text('Not you? Log out')),
            ),
          ]),
        ),
      ),
    );
  }
}

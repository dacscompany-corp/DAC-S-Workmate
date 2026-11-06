import 'password_prompt.dart';

/// What Profile needs from the signed-in account, built once in main.dart.
class AccountServices {
  const AccountServices({required this.changePassword, required this.termsAcceptedAt, this.passwordPrompt});

  /// Throws on refusal; PasswordChangeFailure.of explains it.
  final Future<void> Function(String newPassword) changePassword;

  /// When the current Terms were accepted; null when unknown. Never throws.
  final Future<DateTime?> Function() termsAcceptedAt;

  /// The forced change of a temporary password (3b); null asks nothing.
  final PasswordPromptServices? passwordPrompt;
}

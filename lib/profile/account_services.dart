/// What Profile needs from the signed-in account, built once in main.dart.
class AccountServices {
  const AccountServices({required this.changePassword, required this.termsAcceptedAt});

  /// Throws on refusal; PasswordChangeFailure.of explains it.
  final Future<void> Function(String newPassword) changePassword;

  /// When the current Terms were accepted; null when unknown. Never throws.
  final Future<DateTime?> Function() termsAcceptedAt;
}

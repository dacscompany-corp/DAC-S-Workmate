/// Quantities exactly as the server takes them (0085 pr_submit_request and
/// pr_change_quantity): above 0, at most 1,000,000, at most 3 decimals.
const maxQuantity = 1000000;

/// The typed text as a quantity, or null when the server would refuse it.
double? parseQuantity(String text) {
  final t = text.trim();
  if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(t)) return null;
  final v = double.parse(t);
  return v > 0 && v <= maxQuantity ? v : null;
}

/// "10", "2.5", "1.125", "1,000,000": no trailing zeros, thousands grouped.
String formatQuantity(num value) {
  final fixed = value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  final parts = fixed.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return parts.length == 2 ? '$whole.${parts[1]}' : whole;
}

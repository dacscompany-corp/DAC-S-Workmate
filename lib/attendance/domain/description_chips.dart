/// The "Or tap a common one" chips as a pure operation on the description.
/// ADDITIVE: nothing a worker typed is ever discarded.
const _separator = ', ';

/// Split on commas only (a newline stays inside its part), blanks dropped.
List<String> descriptionParts(String description) =>
    description.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

bool isChipSelected(String description, String chip) =>
    descriptionParts(description).any((p) => p.toLowerCase() == chip.toLowerCase());

/// Adds [chip], or removes it if already there (case-insensitive match; the
/// chip's own capitalisation is what gets stored).
String toggleDescriptionChip(String description, String chip) {
  final parts = descriptionParts(description);
  final without = parts.where((p) => p.toLowerCase() != chip.toLowerCase()).toList();
  return without.length == parts.length ? [...parts, chip].join(_separator) : without.join(_separator);
}

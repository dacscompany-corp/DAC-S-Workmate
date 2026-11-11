/// What Home's sync badge says (redesign spec §6).
class SyncSummary {
  const SyncSummary.hidden()
      : waiting = 0,
        hidden = true;
  const SyncSummary.count(this.waiting) : hidden = false;

  /// Records still on this phone, all sources together.
  final int waiting;

  /// Some source has not been read yet: show nothing, never a guess.
  final bool hidden;

  bool get allSent => !hidden && waiting == 0;
}

/// [counts]: one per source (attendance, requests, My Work, tools); null =
/// not read yet. A source that is off passes 0.
SyncSummary syncSummary(List<int?> counts) {
  if (counts.any((c) => c == null)) return const SyncSummary.hidden();
  return SyncSummary.count(counts.fold<int>(0, (n, c) => n + c!));
}

/// Tool records the phone holds that are not confirmed: each unresolved one,
/// each unreadable one, and one more when the store itself needs recovery.
int toolsNotConfirmed(int unresolved, int unreadable, bool recoveryNeeded) => unresolved + unreadable + (recoveryNeeded ? 1 : 0);

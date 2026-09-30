enum TermsDecision { mustAccept, alreadyAccepted }

/// Whether a signed-in worker sees the Terms screen. Pure, so the one gate
/// between a worker and the app is provable without a network.
TermsDecision decideTerms(Set<String> accepted, String current) =>
    accepted.contains(current) ? TermsDecision.alreadyAccepted : TermsDecision.mustAccept;

enum StartupDecision { ready, mustAccept, unavailable }

/// What to show a worker who already has a session. Trust the server when it
/// answers; fall back to what this device recorded when it cannot be asked
/// ([acceptedVersions] is null); never guess "not accepted" offline, because
/// accepting again offline cannot be written anywhere.
StartupDecision decideStartup({
  required Set<String>? acceptedVersions,
  required String? cachedVersion,
  required String currentVersion,
}) {
  if (acceptedVersions != null) {
    return decideTerms(acceptedVersions, currentVersion) == TermsDecision.alreadyAccepted
        ? StartupDecision.ready
        : StartupDecision.mustAccept;
  }
  return cachedVersion == currentVersion ? StartupDecision.ready : StartupDecision.unavailable;
}

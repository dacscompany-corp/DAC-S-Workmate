/// What the auth client can say about the session on this device.
/// "No session" and "a session I cannot check right now" are different
/// facts; only the first means the worker is signed out.
enum SessionPresence { confirmed, unverifiable, absent }

enum SessionDecision {
  /// Read the profile as this worker; its answer is authoritative.
  askTheServer,

  /// Cannot verify: stand on the last profile this device saw.
  useLastKnown,

  /// Nothing to resolve: the login screen is correct.
  signedOut,
}

/// Decided BEFORE anything is read. A read made with no session does not
/// fail: it succeeds as the anon role and returns zero rows, and believing
/// that "nobody" is what signed Attendance workers out of an app they
/// never left (see the Kotlin SessionGate).
SessionDecision decideSession(SessionPresence presence, {required bool hasLastKnownWorker}) =>
    switch (presence) {
      SessionPresence.confirmed => SessionDecision.askTheServer,
      SessionPresence.unverifiable =>
        hasLastKnownWorker ? SessionDecision.useLastKnown : SessionDecision.signedOut,
      SessionPresence.absent => SessionDecision.signedOut,
    };

/// Where WorkMate finds the shared DAC's backend.
///
/// The anon key is PUBLIC by design: js/supabase-config.js ships the same
/// string to every browser. It grants nothing on its own; every table is
/// behind RLS. Never put the service_role key in this app.
class AppConfig {
  static const supabaseUrl = 'https://hqbgduyonlbbsvjuapre.supabase.co';
  static const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhxYmdkdXlvbmxiYnN2anVhcHJlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2Mjc3NDEsImV4cCI6MjA5NjIwMzc0MX0.sDKSroNIm-1Lip6ueq2lN1VTsvO1g4mT7Rf_WZ5AxWo';

  /// Sign-in runs server-side: Turnstile guards the auth endpoint and has no
  /// native Android SDK. The function also refuses non-workers.
  static const signInFunctionUrl = '$supabaseUrl/functions/v1/attendance-signin';

  static const releaseBucket = 'app-releases';

  /// 0082: how the server tells WorkMate from the old Attendance app.
  static const appHeader = 'x-dacs-app';
  static const appName = 'workmate';
  static const appVersionHeader = 'x-dacs-app-version';
}

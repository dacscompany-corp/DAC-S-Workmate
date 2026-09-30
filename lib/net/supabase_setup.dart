import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'workmate_http_client.dart';

/// The ONE Supabase configuration, used by the app and by the background sync
/// (which runs in its own isolate and must build the same client). Initialize
/// is a no-op when the engine is already initialized.
Future<SupabaseClient> initWorkMateSupabase({
  required WorkMateHttpClient httpClient,
  required LocalStorage localStorage,
}) async {
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
    httpClient: httpClient,
    authOptions: FlutterAuthClientOptions(localStorage: localStorage),
    // postgrest's default 3 retries with 2/4/8 s back-off held the offline
    // launch on a spinner for ~15 s; the app has its own fallbacks.
    postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
  );
  return Supabase.instance.client;
}

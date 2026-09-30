import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'app_controller.dart';
import 'auth/auth_backend.dart';
import 'auth/auth_repository.dart';
import 'auth/session_storage.dart';
import 'auth/sign_in_api.dart';
import 'auth/worker_cache.dart';
import 'config/app_config.dart';
import 'net/update_nudges.dart';
import 'net/workmate_http_client.dart';
import 'terms/terms_repository.dart';
import 'update/apk_installer.dart';
import 'update/app_update_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final info = await PackageInfo.fromPlatform();
  final versionCode = int.parse(info.buildNumber);
  final android = await DeviceInfoPlugin().androidInfo;
  final userAgent =
      'DacsWorkMate/${info.version} (Android ${android.version.release}; ${android.manufacturer} ${android.model})';

  final prefs = await SharedPreferences.getInstance();
  final nudges = UpdateNudges();
  final httpClient = WorkMateHttpClient(versionCode: versionCode, nudges: nudges);
  final sessionStorage = WorkMateSessionStorage(secure: SecureBox(), plain: prefs);

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
    httpClient: httpClient,
    authOptions: FlutterAuthClientOptions(localStorage: sessionStorage),
  );
  final client = Supabase.instance.client;

  final cache = WorkerCache(prefs);
  final updates = AppUpdateRepository(
    source: SupabaseReleaseSource(client),
    prefs: prefs,
    installedVersionCode: versionCode,
    download: http.Client(),
    cacheDir: getTemporaryDirectory,
  );
  final controller = AppController(
    auth: AuthRepository(api: SignInApi(httpClient), backend: SupabaseAuthBackend(client, sessionStorage), cache: cache),
    terms: TermsRepository(backend: SupabaseTermsBackend(client), cache: cache, userAgent: userAgent),
    updates: updates,
    nudges: nudges.events,
  );

  runApp(WorkMateApp(controller: controller, updates: updates, installer: ApkInstaller(), versionName: info.version));
}

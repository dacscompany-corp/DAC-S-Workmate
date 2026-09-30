import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'app_controller.dart';
import 'attendance/device/clock_anchor_store.dart';
import 'attendance/device/device_bridge.dart';
import 'attendance/sync/background_sync.dart';
import 'attendance/sync/sync_host.dart';
import 'attendance/sync/upload_scheduler.dart';
import 'auth/auth_backend.dart';
import 'auth/auth_repository.dart';
import 'auth/session_storage.dart';
import 'auth/sign_in_api.dart';
import 'auth/worker_cache.dart';
import 'net/supabase_setup.dart';
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
  final device = MethodChannelDeviceBridge();
  final clockAnchors = ClockAnchorStore(prefs, device);
  final httpClient = WorkMateHttpClient(
    versionCode: versionCode,
    nudges: nudges,
    // Every server answer re-anchors the tamper-proof clock (0078). Never let
    // a failure here fail the request itself.
    onServerDate: (date) => clockAnchors.recordServerDate(date).catchError((_) {}),
  );
  final sessionStorage = WorkMateSessionStorage(secure: SecureBox(), plain: prefs);

  final client = await initWorkMateSupabase(httpClient: httpClient, localStorage: sessionStorage);

  // The live app is the one token refresher: background tasks delegate here.
  AttendanceSyncHost(drain: () => syncWith(client)).register();

  // Background sending of queued Time Ins / Time Outs (0C). The sweeper is the
  // backstop for a row whose enqueue never happened (process killed mid-submit).
  // The app must start even if background setup fails.
  try {
    await Workmanager().initialize(attendanceCallbackDispatcher);
    await WorkmanagerUploadScheduler().ensureSweeper();
  } catch (e) {
    debugPrint('Background sync setup failed: $e');
  }

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

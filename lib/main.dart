import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'app_controller.dart';
import 'attendance/attendance_services.dart';
import 'attendance/data/attendance_db.dart';
import 'attendance/data/attendance_photos.dart';
import 'attendance/data/attendance_remote.dart';
import 'attendance/data/attendance_repository.dart';
import 'attendance/data/reward_remote.dart';
import 'attendance/device/clock_anchor_store.dart';
import 'attendance/device/device_bridge.dart';
import 'attendance/sync/background_sync.dart';
import 'attendance/sync/queue_settled.dart';
import 'attendance/sync/sync_host.dart';
import 'attendance/sync/upload_scheduler.dart';
import 'attendance/ui/attendance_copy.dart';
import 'auth/auth_backend.dart';
import 'auth/auth_repository.dart';
import 'auth/session_storage.dart';
import 'auth/sign_in_api.dart';
import 'auth/worker_cache.dart';
import 'net/supabase_setup.dart';
import 'net/update_nudges.dart';
import 'net/workmate_http_client.dart';
import 'profile/account_services.dart';
import 'terms/terms_repository.dart';
import 'update/apk_installer.dart';
import 'update/app_update_repository.dart';
import 'widget/start_flow.dart';
import 'widget/widget_app_sync.dart';
import 'widget/widget_aware_attendance.dart';
import 'widget/widget_bridge.dart';
import 'widget/widget_publisher.dart';

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
  // Registered again on every resume (a slow answer can drop the mapping).
  // What it sends reaches the widget and Home at once.
  final widgets = WidgetPublisher(const ChannelWidgetBridge());
  // Who is let in right now; set once the repository exists (never read the
  // late `controller` from here: a send handed over early would throw).
  String Function() letInWorker = () => '';
  final queueSettled = QueueSettled();
  final syncHost = AttendanceSyncHost(
    drain: () => syncWith(client, afterChange: (db, workerId) async {
      await widgets.publishIfCurrent(db, workerId, () => letInWorker());
      queueSettled.fire();
    }),
  )..register();

  // Background sending of queued Time Ins / Time Outs. The sweeper is the
  // backstop for a row whose enqueue never happened. The app must start even
  // if background setup fails.
  final scheduler = WorkmanagerUploadScheduler();
  try {
    await Workmanager().initialize(attendanceCallbackDispatcher);
    await scheduler.ensureSweeper();
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

  late final AppController controller;
  final attendance = AttendanceRepository(
    db: await openDeviceAttendanceDb(),
    remote: SupabaseAttendanceRemote(client),
    device: device,
    scheduler: scheduler,
    // The worker the app let in (eligible, Terms accepted); nobody otherwise.
    currentWorkerId: () => switch (controller.state) {
      Ready(:final worker) => worker.id,
      _ => '',
    },
    photoDir: () async =>
        Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}attendance-photos'),
  );
  letInWorker = attendance.currentWorkerId;
  final auth = AuthRepository(api: SignInApi(httpClient), backend: SupabaseAuthBackend(client, sessionStorage), cache: cache);
  final terms = TermsRepository(backend: SupabaseTermsBackend(client), cache: cache, userAgent: userAgent);
  controller = AppController(auth: auth, terms: terms, updates: updates, nudges: nudges.events);
  // The home-screen widget follows every change to today, and every sign-in / sign-out.
  Future<void> publishWidget() => widgets.publish(attendance.db, attendance.currentWorkerId());
  final widgetSync = WidgetAppSync(publishWidget);
  controller.addListener(() => widgetSync.onAppState(controller.state));
  final account = AccountServices(
    changePassword: auth.changePassword,
    termsAcceptedAt: () async => switch (controller.state) {
      Ready(:final worker) => terms.acceptedAt(worker.id),
      _ => null,
    },
  );

  final photos = AttendancePhotos.supabase(client);
  final services = AttendanceServices(
    attendance: WidgetAwareAttendance(attendance, onTodayChanged: publishWidget),
    device: device,
    scheduler: scheduler,
    trustedNow: clockAnchors.now,
    photoUrl: photos.signedUrl,
    rewards: SupabaseRewardRemote(client),
    queueSettled: queueSettled,
    openSettings: (route) async {
      try {
        if (route == SettingsRoute.locationSwitch) {
          await device.openLocationSettings();
        } else {
          await openAppSettings();
        }
      } catch (e) {
        debugPrint('Could not open Settings: $e');
      }
    },
  );

  runApp(WorkMateApp(
    controller: controller,
    updates: updates,
    installer: ApkInstaller(),
    versionName: info.version,
    attendance: services,
    account: account,
    onResumed: syncHost.register,
    launches: const ChannelLaunchRequests(),
  ));
}

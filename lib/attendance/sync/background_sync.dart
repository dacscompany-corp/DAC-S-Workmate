import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../../auth/session_storage.dart';
import '../../net/supabase_setup.dart';
import '../../net/update_nudges.dart';
import '../../net/workmate_http_client.dart';
import '../data/attendance_db.dart';
import '../data/attendance_remote.dart';
import 'submission_sync.dart';
import 'sync_host.dart';

/// WorkManager's entry point. The task ALWAYS runs in a new engine (platform
/// channels of MainActivity are NOT available and nothing below needs them).
/// When the app is alive the work is handed to it; otherwise this isolate builds
/// its own client and database.
@pragma('vm:entry-point')
void attendanceCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      return await runBackgroundSync();
    } catch (_) {
      // false = retry with backoff; the rows are still on disk.
      return false;
    }
  });
}

/// True when the queue is settled (or nothing may be sent), false to retry.
Future<bool> runBackgroundSync() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A live app owns the session's token refresh: hand the work to it.
  final delegated = await delegateToLiveApp();
  if (delegated != null) return delegated;

  // Nothing to send: never touch auth (a needless refresh can burn a rotating token).
  final probe = await openDeviceAttendanceDb(singleInstance: false);
  try {
    if (!await probe.hasAnySendable()) return true;
  } finally {
    await probe.close();
  }

  final prefs = await SharedPreferences.getInstance();
  final info = await PackageInfo.fromPlatform();
  final client = await initWorkMateSupabase(
    httpClient: WorkMateHttpClient(versionCode: int.parse(info.buildNumber), nudges: UpdateNudges()),
    localStorage: WorkMateSessionStorage(secure: SecureBox(), plain: prefs),
  );
  return syncWith(client);
}

/// Refresh the session if needed, then drain this worker's queue. Shared by the
/// background isolate and the live app's [AttendanceSyncHost].
Future<bool> syncWith(SupabaseClient client) async {
  // The stored session may be expired: join (or start) its refresh before sending.
  try {
    await client.auth.getSession().timeout(const Duration(seconds: 60));
  } on AuthRetryableFetchException {
    return false;
  } on TimeoutException {
    return false;
  } on AuthException {
    return true; // signed out (e.g. token revoked): nothing may be sent under nobody
  }

  final workerId = client.auth.currentUser?.id ?? '';
  // Own connection: sqflite_android shares singleInstance handles across engines,
  // so closing one here would close another engine's database.
  final db = await openDeviceAttendanceDb(singleInstance: false);
  try {
    final result = await SubmissionSync(db: db, remote: SupabaseAttendanceRemote(client)).drain(workerId);
    return result == SyncResult.done;
  } finally {
    await db.close();
  }
}

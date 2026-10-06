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
import '../../requests/data/request_remote.dart';
import '../../requests/data/requests_db.dart';
import '../../requests/sync/request_sync.dart';
import '../data/attendance_db.dart';
import '../data/attendance_remote.dart';
import '../../widget/widget_bridge.dart';
import '../../widget/widget_publisher.dart';
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
    if (!await probe.hasAnySendable() && !await _requestsWaiting()) return true;
  } finally {
    await probe.close();
  }

  final prefs = await SharedPreferences.getInstance();
  final info = await PackageInfo.fromPlatform();
  final client = await initWorkMateSupabase(
    httpClient: WorkMateHttpClient(versionCode: int.parse(info.buildNumber), nudges: UpdateNudges()),
    localStorage: WorkMateSessionStorage(secure: SecureBox(), plain: prefs),
  );
  // No live app: this engine updates the widget itself (the plugin works here).
  return syncWith(client, afterChange: WidgetPublisher(const ChannelWidgetBridge()).publish);
}

/// Requests waiting to be sent. False when the requests database cannot be
/// read: a request problem must never stop attendance from going out.
Future<bool> _requestsWaiting() async {
  try {
    final db = await openDeviceRequestsDb(singleInstance: false);
    try {
      return await db.hasAnySendable();
    } finally {
      await db.close();
    }
  } catch (_) {
    return false;
  }
}

/// Refresh the session if needed, then drain this worker's queues: attendance
/// first, then requests (0085). Shared by the background isolate and the live
/// app's [AttendanceSyncHost]. [afterChange] (the widget and Home) runs as soon
/// as the ATTENDANCE drain settled a row, with its own database — never held
/// back by request photo uploads. [onRequestsSettled] runs when the requests
/// drain settled one: it only tells the screens (the widget shows no requests).
Future<bool> syncWith(
  SupabaseClient client, {
  Future<void> Function(AttendanceDb db, String workerId)? afterChange,
  FutureOr<void> Function()? onRequestsSettled,
}) async {
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
    final sync = SubmissionSync(db: db, remote: SupabaseAttendanceRemote(client));
    return await drainInOrder(
      attendance: () async {
        final result = await sync.drain(workerId);
        return (result: result, settled: sync.settled);
      },
      requests: () async {
        final requestsDb = await openDeviceRequestsDb(singleInstance: false);
        try {
          final requests = RequestSync(db: requestsDb, remote: SupabaseRequestRemote(client));
          final result = await requests.drain(workerId);
          return (result: result, settled: requests.settled);
        } finally {
          await requestsDb.close();
        }
      },
      attendanceWaiting: () async => workerId.isNotEmpty && (await db.sendable(workerId)).isNotEmpty,
      afterAttendance: afterChange == null ? null : () => afterChange(db, workerId),
      onRequestsSettled: onRequestsSettled,
    );
  } finally {
    await db.close();
  }
}

/// One drain's answer: whether to come back, and how many rows it finished.
typedef DrainOutcome = ({SyncResult result, int settled});

/// [syncWith]'s order, apart from the session and the databases:
/// 1. attendance, and at once [afterAttendance] if it settled a row;
/// 2. requests — any failure, even opening its database, only asks WorkManager
///    to come back; it never fails or blocks attendance — then
///    [onRequestsSettled] if they settled one;
/// 3. attendance ONCE more when a row is waiting again: a Time In queued while
///    request photos uploaded goes now, not at the next sweep.
/// An attendance failure propagates exactly as before (the caller retries).
@visibleForTesting
Future<bool> drainInOrder({
  required Future<DrainOutcome> Function() attendance,
  required Future<DrainOutcome> Function() requests,
  required Future<bool> Function() attendanceWaiting,
  Future<void> Function()? afterAttendance,
  FutureOr<void> Function()? onRequestsSettled,
}) async {
  var att = await attendance();
  if (att.settled > 0) await _tell(afterAttendance);

  DrainOutcome req;
  try {
    req = await requests();
  } catch (_) {
    req = (result: SyncResult.retry, settled: 0);
  }
  if (req.settled > 0) await _tell(onRequestsSettled);

  // A pass that must retry would only fail again: WorkManager comes back.
  if (att.result == SyncResult.done && await _waiting(attendanceWaiting)) {
    att = await attendance();
    if (att.settled > 0) await _tell(afterAttendance);
  }
  return att.result == SyncResult.done && req.result == SyncResult.done;
}

/// The rows are sent; telling the widget and the screens is best effort.
Future<void> _tell(FutureOr<void> Function()? notify) async {
  if (notify == null) return;
  try {
    await notify();
  } catch (_) {}
}

/// Unreadable counts as nothing waiting: the first pass's answer stands.
Future<bool> _waiting(Future<bool> Function() probe) async {
  try {
    return await probe();
  } catch (_) {
    return false;
  }
}

import 'package:workmanager/workmanager.dart';

/// "Send what is waiting" — an interface so the repository and screens test
/// without WorkManager.
abstract class UploadScheduler {
  /// Queue an upload attempt (KEEP: an attempt already scheduled drains this row too).
  Future<void> enqueue(String eventId);

  /// A fresh attempt NOW, restarting any accrued backoff (REPLACE): the moment a
  /// human opens the app and can see "Not sent yet".
  Future<void> sendNow();

  /// The 15-minute backstop for a row whose enqueue never happened.
  Future<void> ensureSweeper();
}

/// ONE name for every upload attempt, so WorkManager serialises them (the
/// Kotlin app once sent the same photo three times in two seconds with a
/// per-event name).
const submitWork = 'attendance-submission';
const sweepWork = 'attendance-submission-sweep';

/// The WorkManager calls, behind a seam so the policies are testable.
abstract class WorkRegistrar {
  Future<void> oneOff({required String uniqueName, required bool replace});
  Future<void> periodic({required String uniqueName, required Duration frequency});
}

class _WorkmanagerRegistrar implements WorkRegistrar {
  final _constraints = Constraints(networkType: NetworkType.connected);

  @override
  Future<void> oneOff({required String uniqueName, required bool replace}) => Workmanager().registerOneOffTask(
        uniqueName,
        submitWork,
        constraints: _constraints,
        existingWorkPolicy: replace ? ExistingWorkPolicy.replace : ExistingWorkPolicy.keep,
        // Exponential from 30 s: a site with intermittent signal is not hammered.
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(seconds: 30),
      );

  @override
  Future<void> periodic({required String uniqueName, required Duration frequency}) => Workmanager().registerPeriodicTask(
        uniqueName,
        submitWork,
        frequency: frequency,
        constraints: _constraints,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
}

class WorkmanagerUploadScheduler implements UploadScheduler {
  WorkmanagerUploadScheduler([WorkRegistrar? registrar]) : _registrar = registrar ?? _WorkmanagerRegistrar();

  final WorkRegistrar _registrar;

  @override
  Future<void> enqueue(String eventId) => _registrar.oneOff(uniqueName: submitWork, replace: false);

  @override
  Future<void> sendNow() => _registrar.oneOff(uniqueName: submitWork, replace: true);

  @override
  Future<void> ensureSweeper() => _registrar.periodic(uniqueName: sweepWork, frequency: const Duration(minutes: 15));
}

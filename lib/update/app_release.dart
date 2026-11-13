import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../config/app_config.dart';

/// One APK the office published from Dacs Web (app_releases, 0079/0082).
/// sizeBytes and sha256 were computed from the uploaded file, so a download
/// that does not reproduce both is not that file.
class AppRelease {
  const AppRelease({
    required this.versionCode,
    required this.versionName,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.sha256,
  });

  factory AppRelease.fromRow(Map<String, dynamic> row) {
    final notes = (row['release_notes'] as String?)?.trim();
    return AppRelease(
      versionCode: (row['version_code'] as num).toInt(),
      versionName: row['version_name'] as String,
      releaseNotes: (notes == null || notes.isEmpty) ? null : notes,
      downloadUrl: '${AppConfig.supabaseUrl}/storage/v1/object/public/${AppConfig.releaseBucket}/${row['storage_path']}',
      sizeBytes: (row['size_bytes'] as num).toInt(),
      sha256: row['sha256'] as String,
    );
  }

  factory AppRelease.fromJson(Map<String, dynamic> j) => AppRelease(
        versionCode: j['versionCode'] as int,
        versionName: j['versionName'] as String,
        releaseNotes: j['releaseNotes'] as String?,
        downloadUrl: j['downloadUrl'] as String,
        sizeBytes: j['sizeBytes'] as int,
        sha256: j['sha256'] as String,
      );

  final int versionCode;
  final String versionName;
  final String? releaseNotes;
  final String downloadUrl;
  final int sizeBytes;
  final String sha256;

  Map<String, dynamic> toJson() => {
        'versionCode': versionCode,
        'versionName': versionName,
        'releaseNotes': releaseNotes,
        'downloadUrl': downloadUrl,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
      };
}

/// The release this build must install, or null. Every published release is
/// required: publishing raises min_workmate_version, so the server refuses
/// older builds anyway. The server's answer wins when there is one; the cache
/// speaks only when the check failed; with neither, never block the worker.
AppRelease? pickRequiredRelease({
  required int installedVersionCode,
  required bool fetchedOk,
  required AppRelease? fetched,
  required AppRelease? cached,
}) {
  final known = fetchedOk ? fetched : cached;
  return (known != null && known.versionCode > installedVersionCode) ? known : null;
}

enum CopyResult { verified, wrongSize, wrongHash, paused }

/// The worker's PAUSE tap, handed to a running download. One per download:
/// once requested it stays requested.
class DownloadPause {
  final _requested = Completer<void>();
  bool get requested => _requested.isCompleted;
  Future<void> get whenRequested => _requested.future;
  void request() {
    if (!_requested.isCompleted) _requested.complete();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

const _pausedMark = Object();

/// Streams [input] into [output], hashing as it goes: one pass, so an APK is
/// never held in memory on a 2 GB phone.
///
/// A download that continues after a pause passes [alreadyWritten]: the bytes
/// already on disk, hashed and counted first but not written again, so the
/// hash still covers the whole file. [pause] stops between chunks (or while
/// waiting for one) and answers [CopyResult.paused] with everything received
/// so far flushed to [output].
Future<CopyResult> copyVerifying(
  Stream<List<int>> input,
  IOSink output, {
  required int expectedSize,
  required String expectedSha256,
  void Function(double fraction)? onProgress,
  Stream<List<int>>? alreadyWritten,
  DownloadPause? pause,
}) async {
  final digestSink = _DigestSink();
  final hasher = sha256.startChunkedConversion(digestSink);
  var copied = 0;
  var lastPercent = -1;
  void report() {
    final percent = expectedSize > 0 ? (copied * 100) ~/ expectedSize : 0;
    if (percent != lastPercent) {
      lastPercent = percent;
      onProgress?.call(percent / 100);
    }
  }

  final chunks = StreamIterator<List<int>>(input);
  try {
    if (alreadyWritten != null) {
      await for (final chunk in alreadyWritten) {
        hasher.add(chunk);
        copied += chunk.length;
      }
      if (copied > expectedSize) return CopyResult.wrongSize;
      report();
    }
    while (true) {
      if (pause != null && pause.requested) {
        await output.flush();
        return CopyResult.paused;
      }
      final next = chunks.moveNext();
      final bool has;
      if (pause == null) {
        has = await next;
      } else {
        final first = await Future.any<Object>([next, pause.whenRequested.then<Object>((_) => _pausedMark)]);
        if (identical(first, _pausedMark)) {
          await output.flush();
          return CopyResult.paused;
        }
        has = first as bool;
      }
      if (!has) break;
      final chunk = chunks.current;
      output.add(chunk);
      hasher.add(chunk);
      copied += chunk.length;
      // Longer than promised is already wrong: stop pulling bytes.
      if (copied > expectedSize) return CopyResult.wrongSize;
      report();
    }
  } finally {
    // Stop pulling bytes; never let a slow socket close hold the answer up.
    try {
      await chunks.cancel().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }
  await output.flush();
  hasher.close();
  if (copied != expectedSize) return CopyResult.wrongSize;
  return digestSink.value.toString() == expectedSha256.toLowerCase() ? CopyResult.verified : CopyResult.wrongHash;
}


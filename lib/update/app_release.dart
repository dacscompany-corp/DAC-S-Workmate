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

enum CopyResult { verified, wrongSize, wrongHash }

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Streams [input] into [output], hashing as it goes: one pass, so an APK is
/// never held in memory on a 2 GB phone.
Future<CopyResult> copyVerifying(
  Stream<List<int>> input,
  IOSink output, {
  required int expectedSize,
  required String expectedSha256,
  void Function(double fraction)? onProgress,
}) async {
  final digestSink = _DigestSink();
  final hasher = sha256.startChunkedConversion(digestSink);
  var copied = 0;
  var lastPercent = -1;
  await for (final chunk in input) {
    output.add(chunk);
    hasher.add(chunk);
    copied += chunk.length;
    // Longer than promised is already wrong: stop pulling bytes.
    if (copied > expectedSize) return CopyResult.wrongSize;
    final percent = expectedSize > 0 ? (copied * 100) ~/ expectedSize : 0;
    if (percent != lastPercent) {
      lastPercent = percent;
      onProgress?.call(percent / 100);
    }
  }
  await output.flush();
  hasher.close();
  if (copied != expectedSize) return CopyResult.wrongSize;
  return digestSink.value.toString() == expectedSha256.toLowerCase() ? CopyResult.verified : CopyResult.wrongHash;
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_release.dart';

abstract class ReleaseSource {
  /// The newest WorkMate release row, null when none is published. Throws
  /// when the server cannot be asked.
  Future<Map<String, dynamic>?> latestWorkMate();
}

class SupabaseReleaseSource implements ReleaseSource {
  SupabaseReleaseSource(this._client);
  final SupabaseClient _client;

  /// 0082: WorkMate's own stream. `app_latest_release()` is the OLD app's.
  @override
  Future<Map<String, dynamic>?> latestWorkMate() async {
    final rows = await _client
        .rpc('app_latest_release_for', params: {'p_app': 'workmate'})
        .timeout(const Duration(seconds: 15)) as List<dynamic>;
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first as Map);
  }
}

enum UpdateFailure {
  downloadFailed('Download failed. Check your internet and try again.',
      'Hindi natapos ang pag-download. Tingnan ang internet at subukan ulit.'),
  fileDamaged('The update file was damaged. Try again.', 'Sira ang update file. Subukan ulit.');

  const UpdateFailure(this.english, this.tagalog);
  final String english;
  final String tagalog;
}

sealed class DownloadResult {}

class DownloadReady extends DownloadResult {
  DownloadReady(this.file);
  final File file;
}

class DownloadFailed extends DownloadResult {
  DownloadFailed(this.reason);
  final UpdateFailure reason;
}

class AppUpdateRepository {
  AppUpdateRepository({
    required this.source,
    required this.prefs,
    required this.installedVersionCode,
    required http.Client download,
    required this.cacheDir,
  }) : _http = download;

  final ReleaseSource source;
  final SharedPreferences prefs;
  final int installedVersionCode;

  /// A plain client: the APK is a public Storage object.
  final http.Client _http;

  /// Must be the app cache dir: res/xml/update_file_paths.xml shares only cache/updates/.
  final Future<Directory> Function() cacheDir;

  static const _cacheKey = 'update.required';

  /// A corrupt or old-shape cached value is no cache: it is dropped so it
  /// cannot break every later check.
  Future<AppRelease?> _readCache() async {
    try {
      final raw = prefs.getString(_cacheKey);
      return raw == null ? null : AppRelease.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      try {
        await prefs.remove(_cacheKey);
      } catch (_) {}
      return null;
    }
  }

  Future<void> _writeCache(AppRelease? r) async {
    try {
      await (r == null ? prefs.remove(_cacheKey) : prefs.setString(_cacheKey, jsonEncode(r.toJson())));
    } catch (_) {}
  }

  /// Never throws: see [pickRequiredRelease] in app_release.dart.
  Future<AppRelease?> requiredRelease() async {
    try {
      AppRelease? fetched;
      var ok = true;
      try {
        final row = await source.latestWorkMate();
        fetched = row == null ? null : AppRelease.fromRow(row);
      } catch (_) {
        ok = false;
      }
      final required = pickRequiredRelease(
        installedVersionCode: installedVersionCode,
        fetchedOk: ok,
        fetched: fetched,
        cached: await _readCache(),
      );
      await _writeCache(required);
      return required;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _updatesDir() async {
    final dir = Directory('${(await cacheDir()).path}${Platform.pathSeparator}updates');
    await dir.create(recursive: true);
    return dir;
  }

  Future<DownloadResult> download(AppRelease release, void Function(double) onProgress) async {
    File? partial;
    try {
      final dir = await _updatesDir();
      // One APK on disk at a time.
      for (final f in dir.listSync()) {
        await f.delete();
      }
      final sep = Platform.pathSeparator;
      final target = File('${dir.path}${sep}dacs-workmate-${release.versionCode}.apk');
      final part = partial = File('${target.path}.part');
      final response = await _http
          .send(http.Request('GET', Uri.parse(release.downloadUrl)))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw http.ClientException('HTTP ${response.statusCode}');
      final sink = part.openWrite();
      final CopyResult result;
      try {
        // An idle timeout: a stalled transfer fails instead of freezing at X%.
        result = await copyVerifying(response.stream.timeout(const Duration(seconds: 30)), sink,
            expectedSize: release.sizeBytes, expectedSha256: release.sha256, onProgress: onProgress);
      } finally {
        await sink.close();
      }
      if (result != CopyResult.verified) {
        await part.delete();
        return DownloadFailed(UpdateFailure.fileDamaged);
      }
      await part.rename(target.path);
      return DownloadReady(target);
    } on Object catch (_) {
      try {
        if (partial != null && await partial.exists()) await partial.delete();
      } catch (_) {}
      return DownloadFailed(UpdateFailure.downloadFailed);
    }
  }

  Future<void> discardDownloads() async {
    final dir = await _updatesDir();
    for (final f in dir.listSync()) {
      await f.delete();
    }
  }
}

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

/// The worker paused it. What was downloaded stays on the phone and the next
/// [AppUpdateRepository.download] of the same release continues from there.
class DownloadPaused extends DownloadResult {}

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

  /// Downloads and verifies [release]. An unfinished download of this same
  /// release (paused, or cut off when the app closed) continues from where it
  /// stopped when the server allows it, and starts again when it does not.
  /// The hash always covers the whole file, so a bad leftover is refused like
  /// any damaged download.
  Future<DownloadResult> download(AppRelease release, void Function(double) onProgress, {DownloadPause? pause}) async {
    // One download writes the part at a time: a second call waits for the
    // first to stop, so two can never interleave their bytes in one file.
    while (_running != null) {
      await _running;
    }
    // Paused while it waited its turn: nothing to ask the server for.
    if (pause != null && pause.requested) return DownloadPaused();
    final done = Completer<void>();
    _running = done.future;
    try {
      return await _download(release, onProgress, pause);
    } finally {
      _running = null;
      done.complete();
    }
  }

  Future<void>? _running;

  Future<DownloadResult> _download(AppRelease release, void Function(double) onProgress, DownloadPause? pause) async {
    File? partial;
    // False while the answer being written could be something other than this
    // APK (the server gave no length to check): a fresh part of it is not kept.
    var checked = true;
    try {
      final dir = await _updatesDir();
      final sep = Platform.pathSeparator;
      final target = File('${dir.path}${sep}dacs-workmate-${release.versionCode}.apk');
      final part = partial = File('${target.path}.part');
      final partName = 'dacs-workmate-${release.versionCode}.apk.part';
      // One APK on disk at a time; only this release's unfinished part stays.
      for (final f in dir.listSync()) {
        if (!f.path.endsWith('$sep$partName')) await f.delete(recursive: true);
      }
      var offset = 0;
      if (await part.exists()) {
        final length = await part.length();
        if (length > 0 && length < release.sizeBytes) {
          offset = length;
        } else {
          await part.delete();
        }
      }
      final request = http.Request('GET', Uri.parse(release.downloadUrl));
      if (offset > 0) request.headers['range'] = 'bytes=$offset-';
      // The file as it is: a compressed answer has no length or range to check.
      request.headers['accept-encoding'] = 'identity';
      final response = await _http.send(request).timeout(const Duration(seconds: 30));
      // 206 = the rest of the file; 200 to a continue request = the whole file again.
      final continued = offset > 0 && response.statusCode == 206;
      // The server says this part cannot be continued: it is no use any more.
      if (response.statusCode == 416) throw const _BadPart();
      if (!continued && response.statusCode != 200) throw http.ClientException('HTTP ${response.statusCode}');
      if (continued && !_continuesFrom(response.headers['content-range'], offset, release.sizeBytes)) throw const _BadPart();
      // Before any file is touched: an answer of the wrong length is not this
      // APK (a Wi-Fi login page, say). Fail and keep what was downloaded.
      final length = response.contentLength;
      final expected = continued ? release.sizeBytes - offset : release.sizeBytes;
      if (length != null && length != expected) throw http.ClientException('Unexpected length');
      // A kept part is only added to, or replaced, by an answer of a known,
      // right length. The release server always sends one.
      if (offset > 0 && length == null) throw http.ClientException('No length');
      checked = length != null;
      final already = continued ? part.openRead(0, offset) : null;
      final sink = part.openWrite(mode: continued ? FileMode.append : FileMode.write);
      final CopyResult result;
      try {
        // An idle timeout: a stalled transfer fails instead of freezing at X%.
        result = await copyVerifying(response.stream.timeout(const Duration(seconds: 30)), sink,
            expectedSize: release.sizeBytes,
            expectedSha256: release.sha256,
            onProgress: onProgress,
            alreadyWritten: already,
            pause: pause);
      } finally {
        await sink.close();
      }
      if (result == CopyResult.paused) return DownloadPaused();
      // Verified in the stream; the file on disk must be that long too.
      if (result != CopyResult.verified || await part.length() != release.sizeBytes) {
        await part.delete();
        return DownloadFailed(UpdateFailure.fileDamaged);
      }
      await part.rename(target.path);
      return DownloadReady(target);
    } on _BadPart {
      await _discard(partial);
      return DownloadFailed(UpdateFailure.downloadFailed);
    } on Object catch (_) {
      // Paused while the connection was failing: still a pause.
      if (pause != null && pause.requested) return DownloadPaused();
      // An answer nobody could check by its length: none of it is kept.
      if (!checked) await _discard(partial);
      // No signal, a dropped or stalled connection: what already arrived stays,
      // so TRY AGAIN continues from there. The hash covers the whole file, so
      // a bad leftover is still refused at the end.
      return DownloadFailed(UpdateFailure.downloadFailed);
    }
  }

  Future<void> _discard(File? f) async {
    try {
      if (f != null && await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// "bytes 300-999/1000" continues from 300 of a 1000-byte file. A total the
  /// server does not give ("*") is not held against it.
  static bool _continuesFrom(String? contentRange, int offset, int size) {
    final m = RegExp(r'^bytes\s+(\d+)-\d*/(\d+|\*)').firstMatch(contentRange?.trim() ?? '');
    if (m == null || int.parse(m.group(1)!) != offset) return false;
    return m.group(2) == '*' || int.parse(m.group(2)!) == size;
  }

  /// How much of [release] is already on this phone from an unfinished
  /// download (0..1): what a retry continues from. 0 when there is none.
  Future<double> savedFraction(AppRelease release) async {
    try {
      final dir = await _updatesDir();
      final part = File('${dir.path}${Platform.pathSeparator}dacs-workmate-${release.versionCode}.apk.part');
      if (release.sizeBytes <= 0 || !await part.exists()) return 0;
      final length = await part.length();
      return length > 0 && length < release.sizeBytes ? length / release.sizeBytes : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> discardDownloads() async {
    final dir = await _updatesDir();
    for (final f in dir.listSync()) {
      await f.delete();
    }
  }
}

/// The kept part cannot be continued (bad range, or the server refused it).
class _BadPart implements Exception {
  const _BadPart();
}

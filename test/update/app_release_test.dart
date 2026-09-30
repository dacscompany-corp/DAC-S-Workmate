import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/update/app_release.dart';

AppRelease rel(int code) => AppRelease(
    versionCode: code, versionName: 'v$code', releaseNotes: null,
    downloadUrl: 'https://x/$code.apk', sizeBytes: 3, sha256: 'x');

void main() {
  group('pickRequiredRelease', () {
    test('a newer published build is required', () {
      expect(pickRequiredRelease(installedVersionCode: 1000, fetchedOk: true, fetched: rel(1001), cached: null)!.versionCode, 1001);
    });
    test('the same or older build is not', () {
      expect(pickRequiredRelease(installedVersionCode: 1001, fetchedOk: true, fetched: rel(1001), cached: null), isNull);
    });
    test('the server answer beats a stale cache', () {
      expect(pickRequiredRelease(installedVersionCode: 1001, fetchedOk: true, fetched: null, cached: rel(1002)), isNull);
    });
    test('offline, the cache keeps the update screen up', () {
      expect(pickRequiredRelease(installedVersionCode: 1000, fetchedOk: false, fetched: null, cached: rel(1001))!.versionCode, 1001);
    });
    test('offline with no cache never blocks the worker', () {
      expect(pickRequiredRelease(installedVersionCode: 1000, fetchedOk: false, fetched: null, cached: null), isNull);
    });
  });

  test('fromRow builds the public download URL from storage_path', () {
    final r = AppRelease.fromRow({
      'version_code': 1001, 'version_name': '0.1.1', 'release_notes': '  ',
      'storage_path': 'workmate/1001.apk', 'size_bytes': 123, 'sha256': 'ab',
    });
    expect(r.downloadUrl, 'https://hqbgduyonlbbsvjuapre.supabase.co/storage/v1/object/public/app-releases/workmate/1001.apk');
    expect(r.releaseNotes, isNull);
    expect(AppRelease.fromJson(r.toJson()).toJson(), r.toJson());
  });

  group('copyVerifying', () {
    final bytes = utf8.encode('hello apk');
    final good = sha256.convert(bytes).toString();

    Future<CopyResult> run(List<List<int>> chunks, int size, String hash) async {
      final dir = await Directory.systemTemp.createTemp('wm');
      final sink = File('${dir.path}/a.part').openWrite();
      final r = await copyVerifying(Stream.fromIterable(chunks), sink, expectedSize: size, expectedSha256: hash);
      await sink.close();
      await dir.delete(recursive: true);
      return r;
    }

    test('exact size and hash is verified', () async {
      expect(await run([bytes.sublist(0, 4), bytes.sublist(4)], bytes.length, good), CopyResult.verified);
    });
    test('a cut-off download is the wrong size', () async {
      expect(await run([bytes.sublist(0, 4)], bytes.length, good), CopyResult.wrongSize);
    });
    test('a longer download stops early as the wrong size', () async {
      expect(await run([bytes, bytes], bytes.length, good), CopyResult.wrongSize);
    });
    test('a swapped file is the wrong hash', () async {
      expect(await run([bytes], bytes.length, '0' * 64), CopyResult.wrongHash);
    });
  });
}

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate/update/app_update_repository.dart';

class FakeSource implements ReleaseSource {
  FakeSource(this.row, {this.error});
  Map<String, dynamic>? row;
  Object? error;
  @override
  Future<Map<String, dynamic>?> latestWorkMate() async {
    if (error != null) throw error!;
    return row;
  }
}

Map<String, dynamic> row(int code, List<int> bytes) => {
      'version_code': code, 'version_name': '0.1.$code', 'release_notes': 'Fixes',
      'storage_path': 'workmate/$code.apk', 'size_bytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
    };

void main() {
  final apk = List<int>.generate(1000, (i) => i % 256);
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('wmupd');
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<AppUpdateRepository> repo(ReleaseSource source, {http.Client? download}) async => AppUpdateRepository(
        source: source,
        prefs: await SharedPreferences.getInstance(),
        installedVersionCode: 1000,
        download: download ?? MockClient((_) async => http.Response.bytes(apk, 200)),
        cacheDir: () async => tmp,
      );

  test('learns of 1001 online, still knows offline', () async {
    final source = FakeSource(row(1001, apk));
    final r = await repo(source);
    expect((await r.requiredRelease())!.versionCode, 1001);
    source.error = const SocketException('down');
    expect((await r.requiredRelease())!.versionCode, 1001);
  });

  test('downloads, verifies and keeps one APK under cache/updates', () async {
    final r = await repo(FakeSource(row(1001, apk)));
    final release = (await r.requiredRelease())!;
    final result = await r.download(release, (_) {});
    expect(result, isA<DownloadReady>());
    final file = (result as DownloadReady).file;
    expect(file.path.replaceAll(r'\', '/'), endsWith('/updates/dacs-workmate-1001.apk'));
    expect(await file.readAsBytes(), apk);
  });

  test('a damaged download is refused and deleted', () async {
    final r = await repo(FakeSource(row(1001, apk)),
        download: MockClient((_) async => http.Response.bytes(List<int>.filled(1000, 7), 200)));
    final result = await r.download((await r.requiredRelease())!, (_) {});
    expect((result as DownloadFailed).reason, UpdateFailure.fileDamaged);
    expect(Directory('${tmp.path}/updates').listSync(), isEmpty);
  });

  test('no signal during download is a download failure', () async {
    final r = await repo(FakeSource(row(1001, apk)),
        download: MockClient((_) async => throw const SocketException('down')));
    final result = await r.download((await r.requiredRelease())!, (_) {});
    expect((result as DownloadFailed).reason, UpdateFailure.downloadFailed);
  });

  test('a corrupt cache is treated as no cache', () async {
    SharedPreferences.setMockInitialValues({'update.required': '{"versionCode":"x"}'});
    final r = await repo(FakeSource(row(1001, apk)));
    expect((await r.requiredRelease())!.versionCode, 1001);
    SharedPreferences.setMockInitialValues({'update.required': 'not json'});
    final r2 = await repo(FakeSource(null));
    expect(await r2.requiredRelease(), isNull);
    final r3 = await repo(FakeSource(null, error: const SocketException('down')));
    SharedPreferences.setMockInitialValues({'update.required': 'not json'});
    expect(await r3.requiredRelease(), isNull);
  });

  test('a body stream that fails midway is a download failure and leaves no file', () async {
    final r = await repo(FakeSource(row(1001, apk)),
        download: MockClient.streaming((req, _) async => http.StreamedResponse(
            Stream<List<int>>.multi((c) {
              c.add(apk.sublist(0, 300));
              c.addError(const SocketException('reset'));
              c.close();
            }),
            200)));
    final result = await r.download((await r.requiredRelease())!, (_) {});
    expect((result as DownloadFailed).reason, UpdateFailure.downloadFailed);
    expect(Directory('${tmp.path}/updates').listSync(), isEmpty);
  });
}

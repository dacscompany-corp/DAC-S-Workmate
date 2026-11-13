import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate/update/app_release.dart';
import 'package:workmate/update/app_update_repository.dart';
import 'package:workmate/update/download_rate.dart';

class _Source implements ReleaseSource {
  @override
  Future<Map<String, dynamic>?> latestWorkMate() async => null;
}

void main() {
  final apk = List<int>.generate(1000, (i) => (i * 7) % 256);
  late Directory tmp;
  late AppRelease release;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('wmpause');
    release = AppRelease(
        versionCode: 1001,
        versionName: '0.1',
        releaseNotes: null,
        downloadUrl: 'https://x/a.apk',
        sizeBytes: apk.length,
        sha256: sha256.convert(apk).toString());
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<AppUpdateRepository> repo(http.Client client) async => AppUpdateRepository(
      source: _Source(),
      prefs: await SharedPreferences.getInstance(),
      installedVersionCode: 1000,
      download: client,
      cacheDir: () async => tmp);

  File part() => File('${tmp.path}/updates/dacs-workmate-1001.apk.part');

  /// Sends the first 300 bytes then waits forever; a continue request gets the rest.
  http.Client server({bool honourRange = true, List<String?>? ranges, List<int>? body}) =>
      MockClient.streaming((req, _) async {
        final range = req.headers['range'];
        ranges?.add(range);
        final data = body ?? apk;
        if (range != null && honourRange) {
          final from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
          return http.StreamedResponse(Stream.value(data.sublist(from)), 206,
              contentLength: data.length - from,
              headers: {'content-range': 'bytes $from-${data.length - 1}/${data.length}'});
        }
        if (range != null) return http.StreamedResponse(Stream.value(data), 200, contentLength: data.length);
        final c = StreamController<List<int>>();
        c.add(data.sublist(0, 300));
        return http.StreamedResponse(c.stream, 200, contentLength: data.length);
      });

  Future<DownloadResult> pauseAt300(AppUpdateRepository r) async {
    final pause = DownloadPause();
    return r.download(release, (p) {
      if (p >= 0.3) pause.request();
    }, pause: pause);
  }

  test('pause keeps what was downloaded; resume asks only for the rest and verifies the whole file', () async {
    final ranges = <String?>[];
    final r = await repo(server(ranges: ranges));
    expect(await pauseAt300(r), isA<DownloadPaused>());
    expect(part().lengthSync(), 300);

    final seen = <double>[];
    final result = await r.download(release, seen.add);
    expect(result, isA<DownloadReady>());
    expect(ranges, [null, 'bytes=300-']);
    expect(seen.first, 0.3);
    expect(seen.last, 1.0);
    expect(await (result as DownloadReady).file.readAsBytes(), apk);
    expect(part().existsSync(), isFalse);
  });

  test('a server that ignores the continue request starts the file again', () async {
    final r = await repo(server(honourRange: false));
    expect(await pauseAt300(r), isA<DownloadPaused>());
    final result = await r.download(release, (_) {});
    expect(result, isA<DownloadReady>());
    expect(await (result as DownloadReady).file.readAsBytes(), apk);
  });

  test('a kept part that does not belong to this file is refused as damaged and deleted', () async {
    final r = await repo(server());
    expect(await pauseAt300(r), isA<DownloadPaused>());
    part().writeAsBytesSync(List<int>.filled(300, 9));
    final result = await r.download(release, (_) {});
    expect((result as DownloadFailed).reason, UpdateFailure.fileDamaged);
    expect(Directory('${tmp.path}/updates').listSync(), isEmpty);
  });

  test("another release's leftovers are removed, never continued", () async {
    final dir = Directory('${tmp.path}/updates')..createSync(recursive: true);
    File('${dir.path}/dacs-workmate-999.apk.part').writeAsBytesSync([1, 2, 3]);
    File('${dir.path}/dacs-workmate-999.apk').writeAsBytesSync([1, 2, 3]);
    final ranges = <String?>[];
    final r = await repo(MockClient((req) async {
      ranges.add(req.headers['range']);
      return http.Response.bytes(apk, 200);
    }));
    expect(await r.download(release, (_) {}), isA<DownloadReady>());
    expect(ranges, [null]);
    expect(dir.listSync().length, 1);
  });

  test('a continue answer that starts at the wrong place is a download failure', () async {
    final r0 = await repo(server());
    expect(await pauseAt300(r0), isA<DownloadPaused>());
    final r = await repo(MockClient.streaming((req, _) async => http.StreamedResponse(
        Stream.value(apk.sublist(200)), 206,
        headers: {'content-range': 'bytes 200-999/1000'})));
    final result = await r.download(release, (_) {});
    expect((result as DownloadFailed).reason, UpdateFailure.downloadFailed);
  });

  test('a pause already asked for stops before any byte is taken', () async {
    final dir = await Directory.systemTemp.createTemp('wmcopy');
    final sink = File('${dir.path}/a.part').openWrite();
    final pause = DownloadPause()..request();
    final result = await copyVerifying(Stream.value(apk), sink,
        expectedSize: apk.length, expectedSha256: release.sha256, pause: pause);
    await sink.close();
    expect(result, CopyResult.paused);
    expect(File('${dir.path}/a.part').lengthSync(), 0);
    await dir.delete(recursive: true);
  });

  group('DownloadRate', () {
    test('no speed until there is enough to measure', () {
      final rate = DownloadRate();
      expect(rate.bytesPerSecond, isNull);
      rate.add(0, 0);
      rate.add(200, 1000);
      expect(rate.bytesPerSecond, isNull);
      expect(rate.secondsLeft(1000), isNull);
    });
    test('speed and time left come from what arrived', () {
      final rate = DownloadRate()
        ..add(0, 0)
        ..add(1000, 2 * 1024 * 1024);
      expect(formatSpeed(rate.bytesPerSecond!), '2.0 MB/S');
      expect(rate.secondsLeft(4 * 1024 * 1024), 2);
      expect(formatTimeLeft(45), '45 SEC LEFT');
      expect(formatTimeLeft(61), '2 MIN LEFT');
      expect(formatSpeed(300 * 1024), '300 KB/S');
    });
  });

  Future<void> seedPart(int n) async {
    await Directory('${tmp.path}/updates').create(recursive: true);
    await part().writeAsBytes(apk.sublist(0, n));
  }

  test('no signal on TRY AGAIN keeps what was downloaded; the next try continues from it', () async {
    await seedPart(300);
    final down = await repo(MockClient((_) async => throw const SocketException('down')));
    final failed = await down.download(release, (_) {}, pause: DownloadPause());
    expect((failed as DownloadFailed).reason, UpdateFailure.downloadFailed);
    expect(await part().length(), 300, reason: 'the 300 bytes are still there');
    final ranges = <String?>[];
    final ok = await (await repo(server(ranges: ranges))).download(release, (_) {}, pause: DownloadPause());
    expect(ranges, ['bytes=300-']);
    expect(await (ok as DownloadReady).file.readAsBytes(), apk);
  });

  test('a connection cut midway keeps what arrived, and the next try finishes the same file', () async {
    final cut = MockClient.streaming((req, _) async => http.StreamedResponse(
        Stream<List<int>>.multi((c) {
          c.add(apk.sublist(0, 300));
          c.addError(const SocketException('reset'));
          c.close();
        }),
        200,
        contentLength: apk.length));
    final failed = await (await repo(cut)).download(release, (_) {}, pause: DownloadPause());
    expect((failed as DownloadFailed).reason, UpdateFailure.downloadFailed);
    expect(await part().length(), 300);
    final ok = await (await repo(server())).download(release, (_) {}, pause: DownloadPause());
    expect(await (ok as DownloadReady).file.readAsBytes(), apk);
  });

  test('a Wi-Fi login page answering a continue request does not wipe the part', () async {
    await seedPart(300);
    final portal = MockClient((_) async => http.Response.bytes(List<int>.filled(50, 60), 200));
    final failed = await (await repo(portal)).download(release, (_) {}, pause: DownloadPause());
    expect((failed as DownloadFailed).reason, UpdateFailure.downloadFailed);
    expect(await part().readAsBytes(), apk.sublist(0, 300), reason: 'untouched');
  });

  test('a part the server refuses to continue (416) is deleted, so the next try starts clean', () async {
    await seedPart(300);
    final failed = await (await repo(MockClient((_) async => http.Response('', 416)))).download(release, (_) {}, pause: DownloadPause());
    expect((failed as DownloadFailed).reason, UpdateFailure.downloadFailed);
    expect(await part().exists(), isFalse);
  });

  test('a continue answer for a file of another size is refused and the part deleted', () async {
    await seedPart(300);
    final other = MockClient.streaming((req, _) async =>
        http.StreamedResponse(Stream.value(apk.sublist(300)), 206, headers: {'content-range': 'bytes 300-1998/1999'}));
    final failed = await (await repo(other)).download(release, (_) {}, pause: DownloadPause());
    expect(failed, isA<DownloadFailed>());
    expect(await part().exists(), isFalse);
  });

  test('a whole download with a pause button that is never pressed installs the right file', () async {
    final r = await repo(MockClient((_) async => http.Response.bytes(apk, 200)));
    final ok = await r.download(release, (_) {}, pause: DownloadPause());
    expect(await (ok as DownloadReady).file.readAsBytes(), apk);
    expect(await part().exists(), isFalse);
  });

  test('two downloads started together never write the same file at once', () async {
    var active = 0, most = 0;
    final slow = MockClient.streaming((req, _) async {
      active++;
      most = active > most ? active : most;
      final c = StreamController<List<int>>();
      c.add(apk.sublist(0, 500));
      Timer(const Duration(milliseconds: 20), () {
        c.add(apk.sublist(500));
        active--;
        c.close();
      });
      return http.StreamedResponse(c.stream, 200, contentLength: apk.length);
    });
    final r = await repo(slow);
    final results = await Future.wait([r.download(release, (_) {}), r.download(release, (_) {})]);
    expect(most, 1, reason: 'the second waited for the first');
    expect(results, everyElement(isA<DownloadReady>()));
    expect(await (results.last as DownloadReady).file.readAsBytes(), apk);
  });

  test('the phone knows how much of an unfinished download it kept', () async {
    final r = await repo(MockClient((_) async => throw const SocketException('down')));
    expect(await r.savedFraction(release), 0);
    await seedPart(300);
    expect(await r.savedFraction(release), 0.3);
    await r.download(release, (_) {}, pause: DownloadPause());
    expect(await r.savedFraction(release), 0.3, reason: 'a failed try keeps it');
    await part().writeAsBytes(apk);
    expect(await r.savedFraction(release), 0, reason: 'a full-size leftover is not continued');
  });

  test('a login page with no length answering a continue request does not wipe the part', () async {
    await seedPart(800);
    final portal = MockClient.streaming(
        (req, _) async => http.StreamedResponse(Stream.value(List<int>.filled(50, 60)), 200));
    final failed = await (await repo(portal)).download(release, (_) {}, pause: DownloadPause());
    expect((failed as DownloadFailed).reason, UpdateFailure.downloadFailed);
    expect(await part().readAsBytes(), apk.sublist(0, 800), reason: 'untouched');
    final ok = await (await repo(server())).download(release, (_) {}, pause: DownloadPause());
    expect(await (ok as DownloadReady).file.readAsBytes(), apk);
  });

  test('a continue answer of the wrong length keeps the part', () async {
    await seedPart(300);
    final short = MockClient.streaming((req, _) async => http.StreamedResponse(Stream.value(apk.sublist(300, 400)), 206,
        contentLength: 100, headers: {'content-range': 'bytes 300-999/1000'}));
    final failed = await (await repo(short)).download(release, (_) {}, pause: DownloadPause());
    expect((failed as DownloadFailed).reason, UpdateFailure.downloadFailed);
    expect(await part().readAsBytes(), apk.sublist(0, 300), reason: 'untouched');
  });

  test('a first answer of the wrong length is refused and nothing is saved', () async {
    final portal = MockClient((_) async => http.Response.bytes(List<int>.filled(50, 60), 200));
    final r = await repo(portal);
    final failed = await r.download(release, (_) {}, pause: DownloadPause());
    expect((failed as DownloadFailed).reason, UpdateFailure.downloadFailed);
    expect(await r.savedFraction(release), 0);
  });

  test('a first answer with no length that breaks midway leaves nothing saved', () async {
    final junk = MockClient.streaming((req, _) async => http.StreamedResponse(
        Stream<List<int>>.multi((c) {
          c.add(List<int>.filled(100, 60));
          c.addError(const SocketException('reset'));
          c.close();
        }),
        200));
    final failed = await (await repo(junk)).download(release, (_) {}, pause: DownloadPause());
    expect((failed as DownloadFailed).reason, UpdateFailure.downloadFailed);
    expect(await part().exists(), isFalse, reason: 'unchecked bytes are not kept');
    final ok = await (await repo(MockClient((_) async => http.Response.bytes(apk, 200)))).download(release, (_) {});
    expect(await (ok as DownloadReady).file.readAsBytes(), apk, reason: 'the next try starts clean');
  });

  test('a full-size leftover that is not the file is thrown away and downloaded again', () async {
    await Directory('${tmp.path}/updates').create(recursive: true);
    await part().writeAsBytes(List<int>.filled(apk.length, 1));
    final ranges = <String?>[];
    final r = await repo(MockClient((req) async {
      ranges.add(req.headers['range']);
      return http.Response.bytes(apk, 200);
    }));
    final ok = await r.download(release, (_) {}, pause: DownloadPause());
    expect(ranges, [null], reason: 'asked for the whole file');
    expect(await (ok as DownloadReady).file.readAsBytes(), apk);
  });

  test('paused while the connection is failing is still a pause, and the part stays', () async {
    await seedPart(300);
    final pause = DownloadPause();
    final r = await repo(MockClient((_) async {
      pause.request();
      throw const SocketException('down');
    }));
    expect(await r.download(release, (_) {}, pause: pause), isA<DownloadPaused>());
    expect(await part().length(), 300);
  });

  test('a download paused while it waits its turn asks the server for nothing', () async {
    var requests = 0;
    final gate = Completer<void>();
    final r = await repo(MockClient((_) async {
      requests++;
      await gate.future;
      return http.Response.bytes(apk, 200);
    }));
    final first = r.download(release, (_) {});
    final pause = DownloadPause();
    final second = r.download(release, (_) {}, pause: pause);
    final third = r.download(release, (_) {});
    pause.request();
    gate.complete();
    expect(await first, isA<DownloadReady>());
    expect(await second, isA<DownloadPaused>());
    expect(await third, isA<DownloadReady>());
    expect(requests, 2, reason: 'the paused one never reached the server');
  });
}

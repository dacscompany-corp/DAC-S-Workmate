import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate/ui/loading_screen.dart';
import 'package:workmate/ui/theme.dart';
import 'package:workmate/ui/update_overlay.dart';
import 'package:workmate/update/apk_installer.dart';
import 'package:workmate/update/app_release.dart';
import 'package:workmate/update/app_update_repository.dart';

class _Installer implements InstallGateway {
  @override
  Future<bool> canInstall() async => true;
  @override
  Future<void> openInstallPermission() async {}
  @override
  Future<void> install(File apk) async {}
}

class _NoSource implements ReleaseSource {
  @override
  Future<Map<String, dynamic>?> latestWorkMate() async => null;
}

/// A download the test drives by hand: progress, then pause or finish.
class _HandRepo extends AppUpdateRepository {
  _HandRepo(SharedPreferences prefs)
      : super(
            source: _NoSource(),
            prefs: prefs,
            installedVersionCode: 1,
            download: MockClient((_) async => http.Response('', 404)),
            cacheDir: () async => Directory.systemTemp);
  int calls = 0;
  double saved = 0;
  DownloadPause? lastPause;
  void Function(double)? progress;
  Completer<DownloadResult>? _end;

  void finish(DownloadResult r) => _end!.complete(r);

  @override
  Future<double> savedFraction(AppRelease release) async => saved;

  @override
  Future<DownloadResult> download(AppRelease release, void Function(double) onProgress, {DownloadPause? pause}) {
    calls++;
    lastPause = pause;
    progress = onProgress;
    final end = _end = Completer<DownloadResult>();
    pause!.whenRequested.then((_) {
      if (!end.isCompleted) end.complete(DownloadPaused());
    });
    return end.future;
  }
}

const _release = AppRelease(
    versionCode: 2, versionName: '0.2', releaseNotes: 'Fixes', downloadUrl: 'u', sizeBytes: 10 * 1024 * 1024, sha256: 'a');

void main() {
  testWidgets('PAUSE holds the download where it is; RESUME DOWNLOAD continues it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = _HandRepo(await SharedPreferences.getInstance());
    await tester.pumpWidget(MaterialApp(
        theme: workMateTheme(), home: UpdateOverlay(release: _release, updates: repo, installer: _Installer())));

    expect(find.text('WorkMate update'), findsOneWidget);
    expect(find.text('Version 0.2 · 10.0 MB'), findsOneWidget);
    expect(find.text('NEW UPDATE'), findsOneWidget);
    expect(find.text('Fixes'), findsOneWidget);

    await tester.tap(find.text('UPDATE NOW!'));
    await tester.pump();
    expect(find.text('PAUSE'), findsOneWidget);
    expect(find.text('DOWNLOADING'), findsOneWidget);

    repo.progress!(0.4);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('4.0 / 10.0 MB'), findsOneWidget);
    expect(find.text('4.0 of 10.0 MB'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);

    await tester.tap(find.text('PAUSE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('RESUME DOWNLOAD'), findsOneWidget);
    expect(find.text('PAUSED'), findsNWidgets(2));
    expect(find.text('ON HOLD'), findsOneWidget);
    expect(find.text('4.0 / 10.0 MB'), findsOneWidget);

    await tester.tap(find.text('RESUME DOWNLOAD'));
    await tester.pump();
    expect(repo.calls, 2);
    expect(find.text('PAUSE'), findsOneWidget);

    repo.progress!(1);
    repo.finish(DownloadReady(File('${Directory.systemTemp.path}/none.apk')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('INSTALL'), findsOneWidget);
    expect(find.text('READY TO INSTALL'), findsOneWidget);
    expect(find.text('COMPLETE'), findsOneWidget);
  });

  testWidgets('a failed download with nothing kept starts over from zero with TRY AGAIN', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = _HandRepo(await SharedPreferences.getInstance());
    await tester.pumpWidget(MaterialApp(
        theme: workMateTheme(), home: UpdateOverlay(release: _release, updates: repo, installer: _Installer())));
    await tester.tap(find.text('UPDATE NOW!'));
    await tester.pump();
    repo.progress!(0.5);
    repo.finish(DownloadFailed(UpdateFailure.downloadFailed));
    await tester.pumpAndSettle();
    expect(find.text('TRY AGAIN'), findsOneWidget);
    expect(find.text('0.0 / 10.0 MB'), findsOneWidget);
    expect(find.textContaining('Download failed'), findsOneWidget);
  });

  testWidgets('a failed download shows what the phone kept, not zero', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = _HandRepo(await SharedPreferences.getInstance());
    await tester.pumpWidget(MaterialApp(
        theme: workMateTheme(), home: UpdateOverlay(release: _release, updates: repo, installer: _Installer())));
    await tester.tap(find.text('UPDATE NOW!'));
    await tester.pump();
    repo.progress!(0.5);
    repo.saved = 0.5;
    repo.finish(DownloadFailed(UpdateFailure.downloadFailed));
    await tester.pumpAndSettle();
    expect(find.text('TRY AGAIN'), findsOneWidget);
    expect(find.text('5.0 / 10.0 MB'), findsOneWidget);
    expect(find.text('NOT FINISHED'), findsOneWidget);
    expect(find.text('NOT DOWNLOADED'), findsNothing);
    expect(find.text('5.0 of 10.0 MB'), findsOneWidget);
    expect(find.text('SAVED'), findsOneWidget);
    // The failure sits with the button, below the scrolling part.
    expect(tester.getTopLeft(find.textContaining('Download failed')).dy,
        greaterThan(tester.getBottomLeft(find.byType(SingleChildScrollView)).dy - 1));
    expect(find.textContaining('Download failed'), findsOneWidget);
  });

  testWidgets('reopened with an unfinished download, the screen shows what is saved', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = _HandRepo(await SharedPreferences.getInstance())..saved = 0.627;
    await tester.pumpWidget(MaterialApp(
        theme: workMateTheme(), home: UpdateOverlay(release: _release, updates: repo, installer: _Installer())));
    await tester.pump();
    expect(find.text('6.2 / 10.0 MB'), findsOneWidget);
    expect(find.text('NOT FINISHED'), findsOneWidget);
    expect(find.text('SAVED'), findsOneWidget);
    expect(find.text('CONTINUE DOWNLOAD'), findsOneWidget);
    expect(find.text('UPDATE NOW!'), findsNothing);
    expect(repo.calls, 0, reason: 'nothing downloads until the worker taps');
  });

  testWidgets('closing the screen mid-download stops that download', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = _HandRepo(await SharedPreferences.getInstance());
    await tester.pumpWidget(MaterialApp(
        theme: workMateTheme(), home: UpdateOverlay(release: _release, updates: repo, installer: _Installer())));
    await tester.tap(find.text('UPDATE NOW!'));
    await tester.pump();
    expect(repo.lastPause!.requested, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(repo.lastPause!.requested, isTrue);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved progress never replaces a live download', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = _HandRepo(await SharedPreferences.getInstance())..saved = 0.2;
    await tester.pumpWidget(MaterialApp(
        theme: workMateTheme(), home: UpdateOverlay(release: _release, updates: repo, installer: _Installer())));
    await tester.tap(find.text('UPDATE NOW!'));
    await tester.pump();
    repo.progress!(0.4);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('4.0 / 10.0 MB'), findsOneWidget);
    await tester.tap(find.text('PAUSE'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('4.0 / 10.0 MB'), findsOneWidget);
  });

  testWidgets('a failure fits a small phone with large text, button still on screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _HandRepo(await SharedPreferences.getInstance());
    await tester.pumpWidget(MaterialApp(
        theme: workMateTheme(),
        home: MediaQuery(
            data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.6)),
            child: UpdateOverlay(release: _release, updates: repo, installer: _Installer()))));
    await tester.tap(find.text('UPDATE NOW!'));
    await tester.pump();
    repo.saved = 0.5;
    repo.finish(DownloadFailed(UpdateFailure.downloadFailed));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getBottomLeft(find.text('TRY AGAIN')).dy, lessThan(568));
  });

  testWidgets('the screen fits a small phone with large text', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _HandRepo(await SharedPreferences.getInstance());
    await tester.pumpWidget(MaterialApp(
        theme: workMateTheme(),
        home: MediaQuery(
            data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.6)),
            child: UpdateOverlay(release: _release, updates: repo, installer: _Installer()))));
    await tester.tap(find.text('UPDATE NOW!'));
    await tester.pump();
    repo.progress!(0.37);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('PAUSE'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the loading screen shows the real status and version, and no made-up progress', (tester) async {
    for (final size in const [Size(320, 568), Size(412, 892)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: workMateTheme(), home: const LoadingScreen(versionName: '0.16.0')));
      await tester.pump(const Duration(milliseconds: 1700));
      expect(tester.takeException(), isNull);
      expect(find.text('WorkMate'), findsOneWidget);
      expect(find.text('Checking your account…'), findsOneWidget);
      expect(find.text('V 0.16.0'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('STEP'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}

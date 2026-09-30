import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate/ui/theme.dart';
import 'package:workmate/ui/update_overlay.dart';
import 'package:workmate/update/apk_installer.dart';
import 'package:workmate/update/app_release.dart';
import 'package:workmate/update/app_update_repository.dart';

class FakeInstaller implements InstallGateway {
  bool can = false;
  int opened = 0;
  int installed = 0;
  bool throwOnInstall = false;
  @override
  Future<bool> canInstall() async => can;
  @override
  Future<void> openInstallPermission() async => opened++;
  @override
  Future<void> install(File apk) async {
    if (throwOnInstall) throw StateError('no installer');
    installed++;
  }
}

class _NoSource implements ReleaseSource {
  @override
  Future<Map<String, dynamic>?> latestWorkMate() async => null;
}

class _ReadyRepo extends AppUpdateRepository {
  _ReadyRepo(SharedPreferences prefs)
      : super(
            source: _NoSource(),
            prefs: prefs,
            installedVersionCode: 1,
            download: MockClient((_) async => http.Response('', 404)),
            cacheDir: () async => Directory.systemTemp);
  final File file = File('${Directory.systemTemp.path}/wm_overlay_${DateTime.now().microsecondsSinceEpoch}.apk');
  @override
  Future<DownloadResult> download(AppRelease release, void Function(double) onProgress) async {
    file.writeAsBytesSync([1]);
    return DownloadReady(file);
  }
}

void main() {
  testWidgets('a downloaded file that has gone missing shows download failed and TRY AGAIN', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final installer = FakeInstaller()..can = true;
    final repo = _ReadyRepo(await SharedPreferences.getInstance());
    const release = AppRelease(
        versionCode: 2, versionName: '0.2', releaseNotes: null, downloadUrl: 'u', sizeBytes: 1, sha256: 'a');
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: UpdateOverlay(release: release, updates: repo, installer: installer),
    ));
    await tester.tap(find.text('UPDATE NOW!'));
    await tester.pumpAndSettle();
    repo.file.deleteSync();
    await tester.tap(find.text('INSTALL'));
    await tester.pumpAndSettle();
    expect(installer.installed, 0);
    expect(find.text('TRY AGAIN'), findsOneWidget);
    expect(find.textContaining('Download failed'), findsOneWidget);
  });

  testWidgets('an installer that throws also falls back to TRY AGAIN', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final installer = FakeInstaller()
      ..can = true
      ..throwOnInstall = true;
    final repo = _ReadyRepo(await SharedPreferences.getInstance());
    const release = AppRelease(
        versionCode: 2, versionName: '0.2', releaseNotes: null, downloadUrl: 'u', sizeBytes: 1, sha256: 'a');
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: UpdateOverlay(release: release, updates: repo, installer: installer),
    ));
    await tester.tap(find.text('UPDATE NOW!'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('INSTALL'));
    await tester.pumpAndSettle();
    expect(find.text('TRY AGAIN'), findsOneWidget);
    repo.file.deleteSync();
  });

  testWidgets('resume without the switch on does not reopen Settings; with it on, installs once', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final installer = FakeInstaller();
    const release = AppRelease(
        versionCode: 2, versionName: '0.2', releaseNotes: null, downloadUrl: 'u', sizeBytes: 1, sha256: 'a');
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: UpdateOverlay(
          release: release, updates: _ReadyRepo(await SharedPreferences.getInstance()), installer: installer),
    ));
    await tester.tap(find.text('UPDATE NOW!'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('INSTALL'));
    await tester.pumpAndSettle();
    expect(installer.opened, 1);
    expect(find.text('ALLOW INSTALLS'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(installer.opened, 1);
    expect(installer.installed, 0);
    expect(find.text('ALLOW INSTALLS'), findsOneWidget);

    installer.can = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(installer.installed, 1);
    expect(installer.opened, 1);
  });
}

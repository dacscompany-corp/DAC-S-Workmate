import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The identity 0082 depends on. A wrong value here is not a style issue:
/// a versionCode below 1000 falls into the server's legacy phone-clock
/// branch, and a changed application id can never update an installed app.
void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('application id is com.dacs.workmate, debug builds get .debug', () {
    expect(gradle, contains('applicationId = "com.dacs.workmate"'));
    expect(gradle, contains('applicationIdSuffix = ".debug"'));
  });

  test('versionCode is 1000 or higher', () {
    final m = RegExp(r'^version:\s*\S+\+(\d+)\s*$', multiLine: true).firstMatch(pubspec);
    expect(m, isNotNull, reason: 'pubspec version must be name+code');
    expect(int.parse(m!.group(1)!), greaterThanOrEqualTo(1000));
  });

  test('minSdk stays 24 like the Attendance app', () {
    expect(gradle, contains('minSdk = 24'));
  });

  test('the emulator-only x86_64 engine stays out of the APK (50 MB bucket limit)', () {
    expect(gradle, contains('excludes += "lib/x86_64/**"'));
  });

  test('a release never builds without the upload key', () {
    expect(gradle, contains('keystore.properties is missing'));
  });

  test('release builds can reach the network and install updates', () {
    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, contains('android.permission.REQUEST_INSTALL_PACKAGES'));
    expect(manifest, contains(r'android:label="${appLabel}"'));
  });

  test('Android backup is off: the refresh token never leaves the phone', () {
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
    expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml').readAsStringSync();
    for (final section in ['cloud-backup', 'device-transfer']) {
      final m = RegExp('<$section>(.*?)</$section>', dotAll: true).firstMatch(rules);
      expect(m, isNotNull, reason: section);
      for (final d in ['sharedpref', 'file', 'database']) {
        expect(m!.group(1), contains('<exclude domain="$d"'), reason: '$section $d');
      }
    }
  });

  test('the upload key never enters git', () {
    final ignore = File('.gitignore').readAsStringSync();
    expect(ignore, contains('keystore.properties'));
    expect(ignore, contains('*.jks'));
  });

  test('nothing tells anyone to split the APK per ABI', () {
    const banned = 'split' '-per-abi';
    // Walk by hand so build output is never entered: once the plugins build, its
    // paths pass Windows' length limit and a recursive listing throws.
    Iterable<File> walk(Directory d) sync* {
      for (final e in d.listSync()) {
        final name = e.path.replaceAll(r'\', '/').split('/').last;
        if (name == 'build' || name == '.dart_tool' || name == '.git' || name == '.gradle') continue;
        if (e is Directory) {
          yield* walk(e);
        } else if (e is File) {
          yield e;
        }
      }
    }

    for (final f in walk(Directory('.'))) {
      final p = f.path.replaceAll(r'\', '/');
      if (p.contains('/build/') || p.contains('/.dart_tool/') || p.contains('/.git/')) continue;
      if (!RegExp(r'\.(md|ps1|sh|yaml|kts|gradle)$').hasMatch(p)) continue;
      expect(f.readAsStringSync().contains(banned), isFalse, reason: p);
    }
  });

  test('attendance can ask for the camera and the location', () {
    expect(manifest, contains('android.permission.CAMERA'));
    expect(manifest, contains('android.permission.ACCESS_FINE_LOCATION'));
    expect(manifest, contains('android.permission.ACCESS_COARSE_LOCATION'));
  });
}

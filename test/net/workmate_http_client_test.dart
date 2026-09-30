import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:workmate/net/update_nudges.dart';
import 'package:workmate/net/workmate_http_client.dart';

void main() {
  test('every request carries x-dacs-app: workmate and the versionCode', () async {
    late http.BaseRequest seen;
    final client = WorkMateHttpClient(
      versionCode: 1000,
      nudges: UpdateNudges(),
      inner: MockClient((req) async {
        seen = req;
        return http.Response('[]', 200);
      }),
    );
    await client.get(Uri.parse('https://example.test/rest/v1/profiles'));
    expect(seen.headers['x-dacs-app'], 'workmate');
    expect(seen.headers['x-dacs-app-version'], '1000');
  });

  test('a 4xx APP_UPDATE_REQUIRED nudges, and the body still reaches the caller', () async {
    final nudges = UpdateNudges();
    var fired = 0;
    final sub = nudges.events.listen((_) => fired++);
    final client = WorkMateHttpClient(
      versionCode: 1000,
      nudges: nudges,
      inner: MockClient((_) async => http.Response('{"message":"APP_UPDATE_REQUIRED"}', 400)),
    );
    final res = await client.get(Uri.parse('https://example.test/rest/v1/rpc/x'));
    await Future<void>.delayed(Duration.zero);
    expect(fired, 1);
    expect(res.statusCode, 400);
    expect(res.body, contains('APP_UPDATE_REQUIRED'));
    await sub.cancel();
  });

  test('other failures do not nudge', () async {
    final nudges = UpdateNudges();
    var fired = 0;
    final sub = nudges.events.listen((_) => fired++);
    final client = WorkMateHttpClient(
      versionCode: 1000,
      nudges: nudges,
      inner: MockClient((req) async => req.url.path.endsWith('a')
          ? http.Response('APP_UPDATE_REQUIRED', 500)
          : http.Response('{"message":"permission denied"}', 403)),
    );
    await client.get(Uri.parse('https://example.test/a'));
    await client.get(Uri.parse('https://example.test/b'));
    await Future<void>.delayed(Duration.zero);
    expect(fired, 0);
    await sub.cancel();
  });

  test('the server Date header is reported (0C anchors trusted time on it)', () async {
    String? date;
    final client = WorkMateHttpClient(
      versionCode: 1000,
      nudges: UpdateNudges(),
      onServerDate: (d) => date = d,
      inner: MockClient((_) async =>
          http.Response('[]', 200, headers: {'date': 'Wed, 30 Sep 2026 07:00:00 GMT'})),
    );
    await client.get(Uri.parse('https://example.test/'));
    expect(date, 'Wed, 30 Sep 2026 07:00:00 GMT');
  });
}

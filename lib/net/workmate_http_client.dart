import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../config/app_config.dart';
import 'update_nudges.dart';

/// 0077's refusal code for a build the server no longer accepts.
const appUpdateRequired = 'APP_UPDATE_REQUIRED';

/// The client under every Supabase call and the sign-in function.
///
/// - Adds the identity headers 0082 reads: `x-dacs-app: workmate` and the
///   versionCode. Without them WorkMate would be taken for the old app.
/// - Reports each response's Date header (0C anchors trusted time on it).
/// - Peeks a 4xx body for APP_UPDATE_REQUIRED and hands it back intact.
class WorkMateHttpClient extends http.BaseClient {
  WorkMateHttpClient({
    required this.versionCode,
    required this.nudges,
    http.Client? inner,
    this.onServerDate,
  }) : _inner = inner ?? IOClient(HttpClient()..connectionTimeout = const Duration(seconds: 15));

  final int versionCode;
  final UpdateNudges nudges;
  final void Function(String date)? onServerDate;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers[AppConfig.appHeader] = AppConfig.appName;
    request.headers[AppConfig.appVersionHeader] = versionCode.toString();

    final response = await _inner.send(request);

    final date = response.headers['date'];
    if (date != null) onServerDate?.call(date);

    if (response.statusCode < 400 || response.statusCode > 499) return response;

    final bytes = await response.stream.toBytes();
    if (utf8.decode(bytes, allowMalformed: true).contains(appUpdateRequired)) {
      nudges.nudge();
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}

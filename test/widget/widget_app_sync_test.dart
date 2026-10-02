import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/app_controller.dart';
import 'package:workmate/auth/worker_profile.dart';
import 'package:workmate/widget/widget_app_sync.dart';

void main() {
  const juan = WorkerProfile(id: 'u1');

  test('sign-in and sign-out each update the widget once', () {
    var published = 0;
    final sync = WidgetAppSync(() async => published++);
    sync.onAppState(Starting());
    expect(published, 0);
    sync.onAppState(Ready(juan));
    sync.onAppState(Ready(juan)); // a re-notify (update check) is not a change
    expect(published, 1);
    sync.onAppState(Starting());
    sync.onAppState(SignedOut());
    expect(published, 2);
  });

  test('the Terms screens leave the widget as it was', () {
    var published = 0;
    final sync = WidgetAppSync(() async => published++);
    sync.onAppState(NeedsTerms(juan));
    sync.onAppState(TermsUnavailable(juan));
    expect(published, 0);
  });
}

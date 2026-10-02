import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/app_controller.dart';
import 'package:workmate/attendance/domain/work_date.dart';
import 'package:workmate/auth/worker_profile.dart';
import 'package:workmate/widget/start_flow.dart';

/// Ported from StartFlowRequestTest.kt. A widget tap is a request, not a
/// command: the widget may show a day that has moved on, and the worker may
/// be halfway through a capture.
void main() {
  const worker = WorkerProfile(id: 'w1', email: 'w1@example.com', displayName: 'Juan', workerNo: 42, role: 'worker', status: 'active');
  final signedIn = Ready(worker);
  const homeNoRecord = (loading: false, nextAction: TimeDirection.timeIn);
  const homeWorking = (loading: false, nextAction: TimeDirection.timeOut);
  const homeClosed = (loading: false, nextAction: null);

  test('the extra names a direction exactly', () {
    expect(startFlowFromExtra('IN'), TimeDirection.timeIn);
    expect(startFlowFromExtra('OUT'), TimeDirection.timeOut);
  });

  test('anything else is no request', () {
    expect(startFlowFromExtra(null), isNull);
    expect(startFlowFromExtra(''), isNull);
    expect(startFlowFromExtra('in'), isNull);
    expect(startFlowFromExtra('SIDEWAYS'), isNull);
  });

  test('still starting waits', () {
    expect(resolveStartFlow(TimeDirection.timeIn, Starting(), flowOpen: false), StartFlowDecision.wait);
  });

  test('signed out, Terms, or the offline gate drop the request', () {
    for (final state in [SignedOut(), NeedsTerms(worker), TermsUnavailable(worker)]) {
      expect(resolveStartFlow(TimeDirection.timeIn, state, flowOpen: false, home: homeNoRecord), StartFlowDecision.drop);
    }
  });

  test('a flow already open is never replaced', () {
    expect(resolveStartFlow(TimeDirection.timeOut, signedIn, flowOpen: true, home: homeNoRecord), StartFlowDecision.drop);
  });

  test('Home not read yet waits', () {
    expect(resolveStartFlow(TimeDirection.timeIn, signedIn, flowOpen: false), StartFlowDecision.wait);
    expect(resolveStartFlow(TimeDirection.timeIn, signedIn, flowOpen: false, home: (loading: true, nextAction: null)),
        StartFlowDecision.wait);
  });

  test('Time In on a fresh day opens the flow', () {
    expect(resolveStartFlow(TimeDirection.timeIn, signedIn, flowOpen: false, home: homeNoRecord), StartFlowDecision.open);
  });

  test('Time Out on an open day opens the flow', () {
    expect(resolveStartFlow(TimeDirection.timeOut, signedIn, flowOpen: false, home: homeWorking), StartFlowDecision.open);
  });

  test('a stale Time In on an open day stays on Home', () {
    // A photo taken now would only be refused as ALREADY_TIMED_IN.
    expect(resolveStartFlow(TimeDirection.timeIn, signedIn, flowOpen: false, home: homeWorking), StartFlowDecision.stayOnHome);
  });

  test('a stale Time Out on a fresh day stays on Home', () {
    expect(resolveStartFlow(TimeDirection.timeOut, signedIn, flowOpen: false, home: homeNoRecord), StartFlowDecision.stayOnHome);
  });

  test('a closed day stays on Home whatever was asked', () {
    for (final d in TimeDirection.values) {
      expect(resolveStartFlow(d, signedIn, flowOpen: false, home: homeClosed), StartFlowDecision.stayOnHome);
    }
  });

  test('offline with nothing mirrored still opens Time In, as Home does', () {
    // HomeController.nextAction is timeIn on noConnection with no record.
    expect(resolveStartFlow(TimeDirection.timeIn, signedIn, flowOpen: false, home: homeNoRecord), StartFlowDecision.open);
  });

  test('the inbox holds one request until taken', () {
    final inbox = StartFlowInbox();
    var told = 0;
    inbox.addListener(() => told++);
    inbox.put(TimeDirection.timeIn);
    expect(inbox.pending, TimeDirection.timeIn);
    inbox.clear();
    expect(inbox.pending, isNull);
    inbox.clear(); // already empty: no news
    expect(told, 2);
  });
}

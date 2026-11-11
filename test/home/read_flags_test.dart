import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/home/home_controller.dart';
import 'package:workmate/requests/data/requests_api.dart';
import 'package:workmate/requests/list/requests_controller.dart';
import 'package:workmate/tools/data/tool_pending_store.dart';
import 'package:workmate/tools/data/tool_submitter.dart';
import 'package:workmate/tools/domain/tool_submission.dart';
import 'package:workmate/workplan/data/workplan_api.dart';
import 'package:workmate/workplan/ui/my_work_controller.dart';

import '../attendance/fakes.dart';
import '../requests/request_fakes.dart';
import '../tools/tool_fakes.dart';
import '../workplan/workplan_fakes.dart';

/// A tool store the phone cannot read at all.
class BrokenToolStore implements ToolPendingStore {
  @override
  Future<ToolPendingLoad> load() async => throw StateError('unreadable');
  @override
  Future<void> save(List<ToolSubmission> readable) async {}
  @override
  Future<void> dropUnreadable(String userId, String opId) async {}
}

/// Lets unawaited reads (HomeController's side loads) finish.
Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('My Work is read once a load gave a list the phone can trust', () {
    test('not before the first load', () {
      expect(MyWorkController(api: FakeWorkPlanApi()).read, isFalse);
    });

    test('the server answered', () async {
      final c = MyWorkController(api: FakeWorkPlanApi());
      await c.refresh();
      expect(c.read, isTrue);
    });

    test('no signal, but a saved copy', () async {
      final api = FakeWorkPlanApi()..view = WorkPlanView(error: Exception('no signal'), fetchedAt: DateTime.utc(2026, 11, 10));
      final c = MyWorkController(api: api);
      await c.refresh();
      expect(c.read, isTrue);
    });

    test('no signal and nothing saved: not read', () async {
      final api = FakeWorkPlanApi()..view = WorkPlanView(error: Exception('no signal'));
      final c = MyWorkController(api: api);
      await c.refresh();
      expect(c.read, isFalse);
    });

    test('the phone could not load at all: not read', () async {
      final c = MyWorkController(api: FakeWorkPlanApi()..loadError = StateError('db'));
      await c.refresh();
      expect(c.read, isFalse);
    });
  });

  group('Requests is read the same way', () {
    test('not before the first load', () {
      expect(RequestsController(api: FakeRequestsApi()).read, isFalse);
    });

    test('the server answered', () async {
      final c = RequestsController(api: FakeRequestsApi());
      await c.refresh();
      expect(c.read, isTrue);
    });

    test('no signal, but a saved copy', () async {
      final api = FakeRequestsApi()
        ..view = RequestsView(entries: const [], error: Exception('no signal'), fetchedAt: DateTime.utc(2026, 11, 10));
      final c = RequestsController(api: api);
      await c.refresh();
      expect(c.read, isTrue);
    });

    test('no signal and nothing saved: not read', () async {
      final api = FakeRequestsApi()..view = RequestsView(entries: const [], error: Exception('no signal'));
      final c = RequestsController(api: api);
      await c.refresh();
      expect(c.read, isFalse);
    });

    test('the read threw: not read', () async {
      final c = RequestsController(api: FakeRequestsApi()..viewError = StateError('db'));
      await c.refresh();
      expect(c.read, isFalse);
    });
  });

  group('tool records on the phone', () {
    test('loaded only after the phone\'s store was read', () async {
      final s = ToolSubmitter(remote: FakeToolsRemote(), store: MemoryToolPendingStore());
      expect(s.loaded, isFalse);
      await s.load('u1');
      expect(s.loaded, isTrue);
    });

    test('an unreadable store: never loaded', () async {
      final s = ToolSubmitter(remote: FakeToolsRemote(), store: BrokenToolStore());
      await expectLater(s.load('u1'), throwsStateError);
      expect(s.loaded, isFalse);
    });
  });

  group('attendance waiting on the phone', () {
    test('unknown until read, then the count', () async {
      final a = FakeAttendance()..waiting = 2;
      final c = HomeController(attendance: a, scheduler: FakeScheduler());
      expect(c.waiting, isNull);
      await c.refresh();
      await settle();
      expect(c.waiting, 2);
    });

    test('a failed local read makes it unknown again', () async {
      final a = FakeAttendance()..waiting = 2;
      final c = HomeController(attendance: a, scheduler: FakeScheduler());
      await c.refresh();
      await settle();
      a.waitingError = StateError('db');
      await c.refresh();
      await settle();
      expect(c.waiting, isNull);
    });
  });
}

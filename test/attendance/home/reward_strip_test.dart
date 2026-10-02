import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/weekly_reward.dart';
import 'package:workmate/attendance/home/home_controller.dart';
import 'package:workmate/attendance/home/home_screen.dart';
import 'package:workmate/auth/worker_profile.dart';
import 'package:workmate/ui/theme.dart';

import '../fakes.dart';

void main() {
  late FakeRewards rewards;
  final now = DateTime.parse('2026-09-11T02:00:00Z'); // 10:00 AM, Friday 11 Sep, Manila
  const worker = WorkerProfile(id: 'u1', displayName: 'Juan dela Cruz', position: 'Mason', workerNo: 42);

  RewardDay day(int d, RewardDayStatus s) => RewardDay(date: DateTime.utc(2026, 9, d), required: true, status: s);

  Future<void> show(WidgetTester tester) async {
    useTallPhone(tester);
    final c = HomeController(attendance: FakeAttendance(), scheduler: FakeScheduler(), rewards: rewards, now: () => now);
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(
        body: HomeScreen(
          worker: worker,
          controller: c,
          onStartFlow: (_) {},
          onSeeHistory: () {},
          openSettings: (_) {},
        ),
      ),
    ));
    await c.refresh();
    await tester.pumpAndSettle();
  }

  setUp(() => rewards = FakeRewards());

  testWidgets('a qualifying week shows the pill with the amount and the count', (tester) async {
    rewards.days = [for (var d = 7; d <= 11; d++) day(d, RewardDayStatus.onTime)];
    rewards.amount = 500;
    await show(tester);
    expect(find.text('WEEKLY REWARD'), findsOneWidget);
    expect(find.text('Qualified · ₱500'), findsOneWidget);
    expect(find.text('5 of 5 on time'), findsOneWidget);
    expect(find.byKey(const Key('reward-dot-2026-09-08-onTime')), findsOneWidget);
  });

  testWidgets('a lost week never shows a peso figure', (tester) async {
    rewards.days = [day(7, RewardDayStatus.late), for (var d = 8; d <= 11; d++) day(d, RewardDayStatus.onTime)];
    rewards.amount = 500;
    await show(tester);
    expect(find.text('Disqualified'), findsOneWidget);
    expect(find.textContaining('₱'), findsNothing);
  });

  testWidgets('an unverified day explains itself', (tester) async {
    rewards.days = [day(7, RewardDayStatus.unverified), for (var d = 8; d <= 11; d++) day(d, RewardDayStatus.onTime)];
    await show(tester);
    expect(find.textContaining('A brown day could not be verified'), findsOneWidget);
  });

  testWidgets('no signal says so instead of drawing five empty days', (tester) async {
    rewards.error = const SocketException('no route');
    await show(tester);
    expect(find.text('WEEKLY REWARD'), findsOneWidget);
    expect(find.text('Needs signal to check'), findsOneWidget);
    expect(find.byKey(const Key('reward-dot-2026-09-07-missing')), findsNothing);
  });

  testWidgets('the reward status sits at the right edge, apart from the label', (tester) async {
    rewards.error = const SocketException('no route');
    await show(tester);
    final label = tester.getRect(find.text('WEEKLY REWARD'));
    final status = tester.getRect(find.text('Needs signal to check'));
    expect(status.right, moreOrLessEquals(380, epsilon: 1)); // 400-wide test phone, 20 px side padding
    expect(status.left, greaterThanOrEqualTo(label.right + 12));
  });

  testWidgets('Home greets by the Manila hour', (tester) async {
    await show(tester);
    expect(find.text('Good morning, Juan'), findsOneWidget);
  });
}

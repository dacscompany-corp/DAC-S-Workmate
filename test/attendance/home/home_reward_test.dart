import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/weekly_reward.dart';
import 'package:workmate/attendance/home/home_controller.dart';

import '../fakes.dart';

void main() {
  late FakeAttendance attendance;
  late FakeScheduler scheduler;
  late FakeRewards rewards;
  final now = DateTime.parse('2026-09-09T02:00:00Z'); // 10:00 AM, Wednesday 9 Sep, Manila
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  HomeController home() => HomeController(attendance: attendance, scheduler: scheduler, rewards: rewards, now: () => now);

  setUp(() {
    attendance = FakeAttendance();
    scheduler = FakeScheduler();
    rewards = FakeRewards();
  });

  test('the reward week is asked from its Monday, Manila time', () async {
    final c = home();
    await c.refresh();
    await settle();
    expect(rewards.weekStarts, [DateTime.utc(2026, 9, 7)]);
  });

  test('the server days become five cells and a summary', () async {
    rewards.days = [
      RewardDay(date: DateTime.utc(2026, 9, 7), required: true, status: RewardDayStatus.onTime),
      RewardDay(date: DateTime.utc(2026, 9, 8), required: true, status: RewardDayStatus.onTime),
      RewardDay(date: DateTime.utc(2026, 9, 9), required: true, status: RewardDayStatus.missing),
    ];
    final c = home();
    await c.refresh();
    await settle();
    expect(c.rewardCells.length, 5);
    expect(c.rewardCells[2].isToday, isTrue);
    expect(c.reward!.status, RewardStatus.inProgress);
    expect(c.rewardUnavailable, isFalse);
  });

  test('no signal says the reward cannot be checked, with no cells to misread', () async {
    rewards.error = const SocketException('no route');
    final c = home();
    await c.refresh();
    await settle();
    expect(c.rewardUnavailable, isTrue);
    expect(c.rewardCells, isEmpty);
    expect(c.reward, isNull);
  });

  test('the amount is read separately, and its failure costs nothing else', () async {
    rewards.amount = 500;
    final c = home();
    await c.refresh();
    await settle();
    expect(c.rewardAmount, 500);

    rewards.amountError = const SocketException('no route');
    final d = home();
    await d.refresh();
    await settle();
    expect(d.rewardAmount, isNull);
    expect(d.rewardUnavailable, isFalse);
  });

  test('without a reward source Home still works', () async {
    final c = HomeController(attendance: attendance, scheduler: scheduler, now: () => now);
    await c.refresh();
    await settle();
    expect(c.rewardCells, isEmpty);
    expect(c.rewardUnavailable, isFalse);
  });
}

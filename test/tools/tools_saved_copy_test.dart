import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate/app_controller.dart';
import 'package:workmate/auth/worker_profile.dart';
import 'package:workmate/tools/data/tools_account_wipe.dart';
import 'package:workmate/tools/data/tools_saved_copy.dart';

import 'server_answers.dart';
import 'tool_fakes.dart';

void main() {
  late SharedPreferences prefs;
  late ToolsSavedCopy saved;
  final at = DateTime.utc(2026, 11, 6, 0, 42);

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    saved = ToolsSavedCopy(prefs);
  });

  test('kept as the server sent it, with the time it was read', () async {
    final rows = answerRows(myToolsJson);
    await saved.save('u1', ToolsPart.mine, rows, at);
    final back = saved.load('u1', ToolsPart.mine)!;
    expect(back.rows, rows);
    expect(back.at, at);
    expect(saved.load('u1', ToolsPart.team), isNull, reason: 'each part on its own');
  });

  test('another account on the same phone sees none of it', () async {
    await saved.save('u1', ToolsPart.mine, answerRows(myToolsJson), at);
    expect(saved.load('u2', ToolsPart.mine), isNull);
  });

  test('one account\'s copy at a time: saving for another drops the first', () async {
    await saved.save('u1', ToolsPart.mine, answerRows(myToolsJson), at);
    await saved.save('u1', ToolsPart.team, answerRows(teamToolsJson), at);
    await saved.save('u2', ToolsPart.mine, const [], at);
    expect(saved.load('u1', ToolsPart.mine), isNull);
    expect(saved.load('u1', ToolsPart.team), isNull);
    expect(saved.load('u2', ToolsPart.mine)!.rows, isEmpty);
  });

  test('keepOnly: another account\'s copy goes; signed out, none is kept', () async {
    await saved.save('u1', ToolsPart.mine, answerRows(myToolsJson), at);
    await saved.keepOnly('u1');
    expect(saved.load('u1', ToolsPart.mine), isNotNull);
    await saved.keepOnly('u2');
    expect(saved.load('u1', ToolsPart.mine), isNull);
    await saved.save('u2', ToolsPart.mine, answerRows(myToolsJson), at);
    await saved.keepOnly('');
    expect(saved.load('u2', ToolsPart.mine), isNull);
  });

  test('a damaged saved copy reads as none, and the next good read replaces it', () async {
    await prefs.setString(ToolsSavedCopy.key, 'not json');
    expect(saved.load('u1', ToolsPart.mine), isNull);
    await saved.save('u1', ToolsPart.mine, answerRows(myToolsJson), at);
    expect(saved.load('u1', ToolsPart.mine), isNotNull);
  });

  test('the account wipe follows the app: let in keeps only theirs; signed out keeps none', () async {
    await saved.save('u1', ToolsPart.mine, answerRows(myToolsJson), at);
    final wipe = ToolsAccountWipe(saved);
    wipe.onAppState(Starting());
    await Future<void>.delayed(Duration.zero);
    expect(saved.load('u1', ToolsPart.mine), isNotNull, reason: 'startup decides nothing');
    wipe.onAppState(Ready(const WorkerProfile(id: 'u1')));
    await Future<void>.delayed(Duration.zero);
    expect(saved.load('u1', ToolsPart.mine), isNotNull);
    wipe.onAppState(Ready(const WorkerProfile(id: 'u2')));
    await Future<void>.delayed(Duration.zero);
    expect(saved.load('u1', ToolsPart.mine), isNull);
    await saved.save('u2', ToolsPart.mine, const [], at);
    wipe.onAppState(SignedOut());
    await Future<void>.delayed(Duration.zero);
    expect(saved.load('u2', ToolsPart.mine), isNull);
  });
}

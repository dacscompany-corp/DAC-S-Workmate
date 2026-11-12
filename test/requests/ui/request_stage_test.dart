import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/requests/data/requests_api.dart';
import 'package:workmate/requests/domain/remote_request.dart';
import 'package:workmate/requests/domain/request_draft.dart';
import 'package:workmate/requests/domain/request_status.dart';
import 'package:workmate/requests/ui/request_stage.dart';
import 'package:workmate/ui/theme.dart';

import '../domain/request_models_test.dart' show requestDoc;

void main() {
  test('the bar reads Saved · Sent · Received', () {
    expect(requestStageLabels, ['Saved', 'Sent', 'Received']);
  });

  test('each state: segments, icon, words, colour (spec §5)', () {
    final rows = {
      SyncState.draft: ([WmColors.textMuted, WmColors.border, WmColors.border], Icons.edit_note, 'Not sent yet · finish and send', WmColors.textSecondary),
      SyncState.pending: ([WmColors.green, WmColors.brown, WmColors.border], Icons.cloud_off, 'Saved on this phone · sends when there is signal', WmColors.brown),
      SyncState.received: ([WmColors.green, WmColors.green, WmColors.green], Icons.check_circle, 'Received by the office', WmColors.green),
      SyncState.failed: ([WmColors.green, WmColors.danger, WmColors.border], Icons.report, 'Needs attention · open it to see why', WmColors.danger),
      SyncState.needsResolution: ([WmColors.green, WmColors.danger, WmColors.border], Icons.report, 'Needs attention · open it to see why', WmColors.danger),
      SyncState.cancelled: ([WmColors.textDisabled, WmColors.textDisabled, WmColors.textDisabled], Icons.block, 'Cancelled', WmColors.textMuted),
    };
    expect(rows.keys.toSet(), SyncState.values.toSet(), reason: 'every state has a row');
    for (final MapEntry(key: s, value: (segs, icon, line, color)) in rows.entries) {
      final st = stageOf(s);
      expect([st.segments, st.icon, st.line, st.color], [segs, icon, line, color], reason: s.name);
    }
  });

  test('a red border only for the worker\'s own request that needs attention', () {
    RequestEntry remote(SyncState s, {bool mine = true}) => RequestEntry(state: s, remote: RemoteRequest.fromJson(requestDoc(mine: mine)));
    final onPhone = RequestEntry(state: SyncState.failed, draft: RequestDraft(id: 'd1', createdAt: DateTime.utc(2026, 10, 5)));
    expect(needsMe(remote(SyncState.needsResolution)), isTrue);
    expect(needsMe(remote(SyncState.failed)), isTrue);
    expect(needsMe(onPhone), isTrue);
    expect(needsMe(remote(SyncState.needsResolution, mine: false)), isFalse, reason: 'a leader reads a team member\'s request');
    expect(needsMe(remote(SyncState.received)), isFalse);
    expect(needsMe(remote(SyncState.pending)), isFalse);
  });

  testWidgets('the bar paints the three segments; the line shows icon and words', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(body: Column(children: [RequestStageBar(stageOf(SyncState.pending)), RequestStageLine(stageOf(SyncState.pending))])),
    ));
    Color seg(int i) => (tester.widget<Container>(find.byKey(Key('stage-seg-$i'))).decoration! as BoxDecoration).color!;
    expect([seg(0), seg(1), seg(2)], [WmColors.green, WmColors.brown, WmColors.border]);
    expect(find.text('Saved on this phone · sends when there is signal'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });
}

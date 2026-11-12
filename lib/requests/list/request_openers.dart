import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/wm_sheet.dart';
import '../compose/compose_screen.dart';
import '../data/requests_api.dart';
import '../detail/request_sheet.dart';
import '../domain/request_draft.dart';
import '../domain/request_status.dart';
import '../requests_services.dart';
import 'requests_controller.dart';

// The Requests tab and Home both open requests through these, so a row on
// Home opens a request exactly as the tab does (redesign spec §9).

/// [draft] in the New request sheet (redesign Phase 3c), then the list is read
/// again. [resumed]: reopened from its draft card.
Future<void> composeRequest(
  BuildContext context,
  RequestsController controller,
  RequestsServices services,
  RequestDraft draft, {
  String? editLine,
  bool resumed = false,
}) async {
  await showWmSheet<bool>(
    context,
    builder: (_) => ComposeScreen(draft: draft, services: services, editLineOnOpen: editLine, resumed: resumed),
  );
  await controller.refresh();
}

/// The draft is stored on its first change (ComposeController saves every
/// change), so backing straight out leaves nothing behind.
Future<void> newRequest(BuildContext context, RequestsController controller, RequestsServices services) =>
    composeRequest(context, controller, services, services.api.newDraft());

/// A draft opens for editing; anything else opens its details as a sheet
/// (redesign Phase 3), which asks for a fresh copy as it opens.
Future<void> openRequestEntry(BuildContext context, RequestsController controller, RequestsServices services, RequestEntry e) async {
  if (e.state == SyncState.draft) return composeRequest(context, controller, services, e.draft!, resumed: true);
  unawaited(controller.refresh());
  await showWmSheet<void>(
    context,
    builder: (sheetContext) => RequestSheet(
      controller: controller,
      api: services.api,
      entryKey: e.key,
      onEditDraft: (draftId) async {
        final back = await controller.returnToDrafts(draftId);
        // Only a draft that is editable again: a queued one ignores every save.
        final again = controller.entry(draftId);
        final draft = again?.draft;
        if (!back || again?.state != SyncState.draft || draft == null || !sheetContext.mounted || !context.mounted) return;
        // Close this sheet only while it is on top: never another screen (a
        // prompt that opened over it). The draft stays in Drafts either way.
        final route = ModalRoute.of(sheetContext);
        if (route == null || !route.isCurrent) return;
        Navigator.of(sheetContext).pop();
        await composeRequest(context, controller, services, draft, resumed: true);
      },
    ),
  );
  await controller.refresh();
}

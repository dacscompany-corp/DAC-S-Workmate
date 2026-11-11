import 'package:flutter/material.dart';

import '../compose/compose_screen.dart';
import '../data/requests_api.dart';
import '../detail/request_detail_screen.dart';
import '../domain/request_draft.dart';
import '../domain/request_status.dart';
import '../requests_services.dart';
import 'requests_controller.dart';

// The Requests tab and Home both open requests through these, so a row on
// Home opens a request exactly as the tab does (redesign spec §9).

/// [draft] in New request / Draft request, then the list is read again.
Future<void> composeRequest(
  BuildContext context,
  RequestsController controller,
  RequestsServices services,
  RequestDraft draft, {
  String? editLine,
}) async {
  await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ComposeScreen(draft: draft, services: services, editLineOnOpen: editLine)));
  await controller.refresh();
}

/// The draft is stored on its first change (ComposeController saves every
/// change), so backing straight out leaves nothing behind.
Future<void> newRequest(BuildContext context, RequestsController controller, RequestsServices services) =>
    composeRequest(context, controller, services, services.api.newDraft());

/// A draft opens for editing; anything else opens its details.
Future<void> openRequestEntry(BuildContext context, RequestsController controller, RequestsServices services, RequestEntry e) async {
  if (e.state == SyncState.draft) return composeRequest(context, controller, services, e.draft!);
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (detailContext) => RequestDetailScreen(
      controller: controller,
      api: services.api,
      entryKey: e.key,
      onEditDraft: (draftId) async {
        final back = await controller.returnToDrafts(draftId);
        // Only a draft that is editable again: a queued one ignores every save.
        final again = controller.entry(draftId);
        final draft = again?.draft;
        if (!back || again?.state != SyncState.draft || draft == null || !detailContext.mounted || !context.mounted) return;
        Navigator.of(detailContext).pop();
        await composeRequest(context, controller, services, draft);
      },
    ),
  ));
  await controller.refresh();
}

import '../data/requests_api.dart';
import '../domain/request_status.dart';

/// What Home says about requests (spec §5: "request updates and pending
/// actions"): what needs the worker, what is still on the phone, and the
/// next expected delivery.
class RequestUpdates {
  const RequestUpdates({this.needsAction = 0, this.pending = 0, this.drafts = 0, this.nextDelivery});

  /// Refused (Failed) or waiting on the office (Needs resolution).
  final int needsAction;

  /// Sent from this phone, not yet received by the office.
  final int pending;
  final int drafts;

  /// "2026-10-14", or null.
  final String? nextDelivery;

  bool get isEmpty => needsAction == 0 && pending == 0 && drafts == 0 && nextDelivery == null;
}

RequestUpdates summarizeRequests(List<RequestEntry> entries, DateTime now) => RequestUpdates(
      needsAction: entries.where((e) => e.state == SyncState.failed || e.state == SyncState.needsResolution).length,
      pending: entries.where((e) => e.state == SyncState.pending).length,
      drafts: entries.where((e) => e.state == SyncState.draft).length,
      nextDelivery: nextDelivery([for (final e in entries) ?e.remote], now),
    );

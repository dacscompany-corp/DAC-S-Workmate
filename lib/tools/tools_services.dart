import 'data/tool_pending_store.dart';
import 'data/tools_remote.dart';
import 'data/tools_saved_copy.dart';

/// Tools on the phone (Stage 3b), built once in main.dart. Optional like
/// Requests and My Work: without it Home simply shows no My tools card, and
/// attendance never depends on it.
class ToolsServices {
  const ToolsServices({required this.remote, required this.store, this.saved});

  final ToolsRemote remote;

  /// Unresolved tool records, saved before they are sent (Q22).
  final ToolPendingStore store;

  /// The last good lists, for weak signal; null keeps none.
  final ToolsSavedCopy? saved;
}

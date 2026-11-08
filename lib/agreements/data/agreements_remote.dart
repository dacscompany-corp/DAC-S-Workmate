import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/my_agreement.dart';

const _readTimeout = Duration(seconds: 15);

/// Linked Labor on the phone: one read, 0113's `ll_my_agreements`, answered
/// for the signed-in worker's own linked agreements only. Nothing is written,
/// and nothing is saved on the phone (Q2).
abstract class AgreementsRemote {
  /// Refuses (AUTH_REQUIRED) when the phone's sign-in is not [userId]: a
  /// shared site phone must never show the last user's money.
  Future<List<MyAgreement>> mine({required String userId});
}

class SupabaseAgreementsRemote implements AgreementsRemote {
  SupabaseAgreementsRemote(this._client);

  final SupabaseClient _client;

  /// Every function the phone calls, with its parameter names: the contract
  /// test holds this list to 0113.
  static const calls = <String, List<String>>{
    'll_my_agreements': [],
  };

  @override
  Future<List<MyAgreement>> mine({required String userId}) async {
    final session = _client.auth.currentUser?.id;
    if (session == null || session != userId) throw StateError('AUTH_REQUIRED');
    final v = await _client.rpc('ll_my_agreements').timeout(_readTimeout);
    final doc = Map<String, dynamic>.from(v as Map);
    return [
      for (final a in (doc['agreements'] as List<dynamic>? ?? const [])) MyAgreement.fromJson(Map<String, dynamic>.from(a as Map)),
    ];
  }
}

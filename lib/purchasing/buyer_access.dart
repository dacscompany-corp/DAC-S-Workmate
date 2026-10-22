import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What the server says about the signed-in office account: whether it may
/// buy (0097 `pur_me().can_buy`, the same rule as `pur_buyer()`) and the
/// company its purchases and receipts file under (`data_owner_id()`).
class BuyerStatus {
  const BuyerStatus({required this.canBuy, required this.companyId});
  final bool canBuy;
  final String companyId;
}

/// `data_owner_id()` (0002): a staff account files under its owner; every
/// other account under itself.
String companyOf(Map<String, dynamic>? profile, String userId) =>
    profile?['role'] == 'staff' ? ((profile?['owner_id'] as String?) ?? userId) : userId;

abstract class BuyerAccessBackend {
  /// Asked as the signed-in account. Throws when it cannot be asked (no
  /// signal, no session): never a guessed "cannot buy".
  Future<BuyerStatus> status(String userId);
}

class SupabaseBuyerAccessBackend implements BuyerAccessBackend {
  SupabaseBuyerAccessBackend(this._client);

  final SupabaseClient _client;

  @override
  Future<BuyerStatus> status(String userId) async {
    // Without a session pur_me would answer for nobody: can_buy false.
    if (_client.auth.currentSession == null) throw StateError('No session to check buying with');
    final me = Map<String, dynamic>.from(await _client.rpc('pur_me').timeout(const Duration(seconds: 15)) as Map);
    final row = await _client.from('profiles').select('id,role,owner_id').eq('id', userId).maybeSingle().timeout(const Duration(seconds: 15));
    return BuyerStatus(canBuy: me['can_buy'] == true, companyId: companyOf(row, userId));
  }
}

enum BuyerDecision {
  /// The Buyer switch is on (or, offline, was on the last time it was asked).
  canBuy,

  /// This phone knew the account as a buyer; the switch is now off (R2).
  turnedOff,

  /// The server says no, and this phone never knew the account as a buyer.
  neverABuyer,

  /// Offline, and this phone was never told. Never assumed either way.
  unknown,
}

/// Whether an office account may use WorkMate's buying screens, as the server
/// last said (Q1, R2). Kept per account on the phone so a buyer at a supplier
/// with no signal still gets in, exactly as workers' profiles are kept.
class BuyerAccess {
  BuyerAccess({required this.backend, required this.prefs});

  final BuyerAccessBackend backend;
  final SharedPreferences prefs;

  static String _key(String id) => 'buyer.$id';
  static String _companyKey(String id) => 'buyer_company.$id';

  /// Asks the server; falls back to what this phone was last told.
  Future<BuyerDecision> decide(String userId) async {
    final BuyerStatus status;
    try {
      status = await backend.status(userId);
    } catch (_) {
      return switch (prefs.getString(_key(userId))) {
        'on' => BuyerDecision.canBuy,
        'off' => BuyerDecision.turnedOff,
        _ => BuyerDecision.unknown,
      };
    }
    await prefs.setString(_companyKey(userId), status.companyId);
    if (status.canBuy) {
      await prefs.setString(_key(userId), 'on');
      return BuyerDecision.canBuy;
    }
    if (prefs.getString(_key(userId)) == null) return BuyerDecision.neverABuyer;
    await prefs.setString(_key(userId), 'off');
    return BuyerDecision.turnedOff;
  }

  /// The sign-in function itself just said "buyer".
  Future<void> letIn(String userId) => prefs.setString(_key(userId), 'on');

  /// A buying screen was refused BUYER_REQUIRED (R2).
  Future<void> markTurnedOff(String userId) async {
    if (prefs.getString(_key(userId)) != null) await prefs.setString(_key(userId), 'off');
  }

  /// The company this account's purchases file under, as last read; null
  /// until the server was asked once.
  String? companyOf(String userId) => prefs.getString(_companyKey(userId));

  /// Sign-out: nothing about a buyer outlives it (site phones are shared).
  Future<void> forget(String userId) async {
    await prefs.remove(_key(userId));
    await prefs.remove(_companyKey(userId));
  }
}

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthRetryableFetchException;

/// One payment line for this agreement: the company's record of it, never the
/// worker's acknowledgement (Linked Labor terms §6). A payment's split parts
/// arrive already summed into one line.
class AgreementPayment {
  const AgreementPayment({required this.date, required this.amount, required this.method});

  /// 'YYYY-MM-DD' as the office recorded it, or null.
  final String? date;
  final double amount;

  /// cash · gcash · bank_transfer · cheque, or null.
  final String? method;

  factory AgreementPayment.fromJson(Map<String, dynamic> j) => AgreementPayment(
        date: j['date'] as String?,
        amount: _num(j['amount']) ?? 0,
        method: j['method'] as String?,
      );
}

/// One of the signed-in worker's OWN linked agreements (0113's
/// ll_my_agreements). Held in memory only: Linked Labor saves nothing about
/// money on the phone (Q2).
class MyAgreement {
  const MyAgreement({
    required this.id,
    required this.project,
    required this.mainProject,
    required this.projectCompleted,
    required this.progressPct,
    required this.scope,
    required this.trade,
    required this.daily,
    required this.works,
    required this.agreed,
    required this.paid,
    required this.balance,
    required this.ended,
    required this.endedAt,
    required this.payments,
  });

  final String id;
  final String project;

  /// The main project's name when this agreement is on its Additional Works; else null.
  final String? mainProject;
  final bool projectCompleted;

  /// The project's own overall progress, 0–100; null when not recorded (Q1).
  /// Never the worker's own progress, and never a stand-in 100%.
  final double? progressPct;
  final String scope;
  final String trade;

  /// Daily basis: no agreed total and no balance, only paid so far.
  final bool daily;
  final List<String> works;
  final double? agreed;
  final double paid;

  /// Agreed − paid; negative means paid over the agreed amount. Null when daily.
  final double? balance;
  final bool ended;
  final DateTime? endedAt;
  final List<AgreementPayment> payments;

  bool get overPaid => !daily && (balance ?? 0) < 0;

  factory MyAgreement.fromJson(Map<String, dynamic> j) {
    final daily = j['pay_basis'] == 'daily';
    return MyAgreement(
      id: j['id'] as String,
      project: (j['project'] as String?) ?? '',
      mainProject: j['main_project'] as String?,
      projectCompleted: j['project_completed'] == true,
      progressPct: _num(j['progress_pct']),
      scope: (j['scope'] as String?) ?? '',
      trade: (j['trade'] as String?) ?? '',
      daily: daily,
      works: [for (final w in (j['works'] as List<dynamic>? ?? const [])) if (w is String && w.trim().isNotEmpty) w.trim()],
      agreed: daily ? null : _num(j['agreed']),
      paid: _num(j['paid']) ?? 0,
      balance: daily ? null : _num(j['balance']),
      ended: j['ended'] == true,
      endedAt: j['ended_at'] == null ? null : DateTime.tryParse(j['ended_at'] as String),
      payments: [
        for (final p in (j['payments'] as List<dynamic>? ?? const [])) AgreementPayment.fromJson(Map<String, dynamic>.from(p as Map)),
      ],
    );
  }
}

double? _num(Object? v) => switch (v) {
      null => null,
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };

/// Every way the agreements read can fail, reduced to what the person can do.
enum AgreementsFailure {
  /// NOT_A_REQUESTER: not an active worker or team leader (switched off, or an office account).
  notAllowed,

  /// AUTH_REQUIRED: the phone's sign-in is not the account this screen belongs to.
  sessionExpired,
  appUpdateRequired,
  noConnection,
  unexpected;

  static AgreementsFailure of(Object error) {
    if (error is IOException || error is TimeoutException || error is http.ClientException || error is AuthRetryableFetchException) {
      return noConnection;
    }
    final s = error.toString();
    if (s.contains('NOT_A_REQUESTER')) return notAllowed;
    if (s.contains('AUTH_REQUIRED')) return sessionExpired;
    if (s.contains('APP_UPDATE_REQUIRED')) return appUpdateRequired;
    return unexpected;
  }
}

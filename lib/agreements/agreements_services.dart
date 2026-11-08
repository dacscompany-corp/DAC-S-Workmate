import 'data/agreements_remote.dart';

/// Linked Labor on the phone (My agreements), built once in main.dart.
/// Optional like Tools: without it Home simply shows no My agreements card,
/// and nothing else depends on it.
class AgreementsServices {
  const AgreementsServices({required this.remote});

  final AgreementsRemote remote;
}

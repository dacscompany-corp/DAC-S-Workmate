/// What `attendance-signin` let an account into WorkMate as (2A-3a, R1).
/// Workers and team leaders are `worker`; an office account the server's
/// pur_buyer() rule allows to buy is `buyer`.
enum WorkMateAccess {
  worker,
  buyer;

  /// The function's `access` field. An answer without one comes from a
  /// function older than 0101, which only ever let workers in.
  static WorkMateAccess parse(Object? value) => value == 'buyer' ? buyer : worker;
}

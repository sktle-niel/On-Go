import '../models/points_wallet.dart';

/// Points, as the server awards and spends them.
///
/// Points are earned when a job is paid (`ServiceRequestApi.payForJob`), spent
/// on a priority fee, or converted to balance by a mechanic. The phone keeps no
/// balance of its own.
abstract interface class PointsWalletApi {
  /// The caller's wallet. Clients and mechanics.
  Future<PointsWallet> fetchWallet();

  /// A mechanic turns [points] into balance at `pesosPerPoint`, and gets the
  /// wallet after the conversion. Refused when the balance is short.
  Future<PointsWallet> convertPoints(double points);
}

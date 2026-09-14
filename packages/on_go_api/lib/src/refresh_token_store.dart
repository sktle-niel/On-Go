/// Where a mobile session's refresh token is kept between launches.
///
/// An interface because the right place is platform-specific — the mobile
/// app backs it with the Keychain / Keystore — and this package is not. The
/// console has none at all: its refresh token is an httpOnly cookie the page
/// never sees.
abstract interface class RefreshTokenStore {
  Future<String?> read();

  /// Must have finished before the token is used: a refresh token works once,
  /// and a crash between receiving a new one and storing it would leave the
  /// old, now-dead one behind.
  Future<void> write(String token);

  Future<void> clear();
}

/// Keeps the token for the life of the process only. For tests.
class InMemoryRefreshTokenStore implements RefreshTokenStore {
  InMemoryRefreshTokenStore([this.token]);

  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async => this.token = token;

  @override
  Future<void> clear() async => token = null;
}

import 'package:on_go_shared/on_go_shared.dart';

import '../../data/client_account_store.dart';
import '../../data/mechanic_account_store.dart';

/// Sign-in for the mobile app, against the accounts this device knows about.
/// Installed only when the app is built with `ONGO_BACKEND=local`; the default
/// build signs in through the On Go API instead (see `MobileApi`).
///
/// Two things it will not do, both of them deliberate:
///
/// * It never signs anyone in as Admin or Moderator. Those roles belong to the
///   console website, so an attempt reports [SignInFailure.wrongSurface] and
///   the Sign In screen says where to go instead — the local half of the rule
///   the server enforces.
/// * It never invents an account. The demo shortcuts below are the same ones
///   the app has always had for local testing, and each still opens the real
///   store rather than a parallel fake identity.
///
/// Registration, password changes and resets are not offered here: in local
/// mode the account stores and `PasswordResetStore` own them, and the screens
/// call those directly.
class LocalAuthService implements AuthApi {
  /// Usernames that open a throwaway session for local testing, mapped to the
  /// role they open it as.
  static const Map<String, UserRole> _demoUsernames = {
    'client': UserRole.client,
    'demo-client': UserRole.client,
    'mechanic': UserRole.mechanic,
    'demo-mechanic': UserRole.mechanic,
  };

  /// Usernames that used to open the Admin and Moderator shells from here.
  /// Recognised only so the screen can point at the console instead of
  /// reporting them as unknown accounts.
  static const Set<String> _consoleUsernames = {'admin', 'moderator'};

  @override
  Future<SignInResult> signIn(SignInRequest request) async {
    final identifier = request.identifier.trim().toLowerCase();
    if (identifier.isEmpty) {
      return const SignInResult.failed(SignInFailure.unknownAccount);
    }

    if (request.surface == AppSurface.mobile && _consoleUsernames.contains(identifier)) {
      return const SignInResult.failed(SignInFailure.wrongSurface);
    }

    final demoRole = _demoUsernames[identifier];
    if (demoRole != null) return SignInResult.success(AuthenticatedAccount(user: _enterDemo(demoRole)));

    final client = ClientAccountStore.instance;
    if (client.hasAccount &&
        client.email.trim().toLowerCase() == identifier &&
        client.verifyPassword(request.password)) {
      return SignInResult.success(AuthenticatedAccount(
        user: AuthenticatedUser(
          displayName: client.name,
          email: client.email,
          role: UserRole.client,
        ),
      ));
    }

    final mechanic = MechanicAccountStore.instance;
    if (mechanic.hasAccount &&
        mechanic.email.trim().toLowerCase() == identifier &&
        mechanic.verifyPassword(request.password)) {
      return SignInResult.success(AuthenticatedAccount(
        user: AuthenticatedUser(
          displayName: mechanic.name,
          email: mechanic.email,
          role: UserRole.mechanic,
        ),
      ));
    }

    // A moderator's email would have matched neither store — their account
    // lives in the console's directory, which this app cannot see. Reporting
    // it as unknown is the truth from here.
    return const SignInResult.failed(SignInFailure.unknownAccount);
  }

  /// Opens a demo session, preserving an account that was really registered
  /// this session rather than overwriting it with a throwaway identity.
  AuthenticatedUser _enterDemo(UserRole role) {
    if (role == UserRole.client) {
      final client = ClientAccountStore.instance;
      if (!client.hasAccount) client.enterDemoMode();
      return AuthenticatedUser(
        displayName: client.name,
        email: client.email,
        role: UserRole.client,
      );
    }

    final mechanic = MechanicAccountStore.instance;
    if (!mechanic.hasAccount) mechanic.enterDemoMode();
    return AuthenticatedUser(
      displayName: mechanic.name,
      email: mechanic.email,
      role: UserRole.mechanic,
    );
  }

  @override
  Future<AuthenticatedAccount> register(RegisterRequest request) {
    throw const ApiException.unsupported(
      'Local accounts are registered through the account store that owns them.',
    );
  }

  /// Local sessions do not outlive the app.
  @override
  Future<AuthenticatedAccount?> restoreSession() async => null;

  @override
  Future<AuthenticatedAccount> fetchCurrentAccount() {
    throw const ApiException.unsupported('Local sessions have no server account to read.');
  }

  @override
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    // The local stores own their own passwords and each Settings screen calls
    // its own store directly, which is where the per-screen rules live.
    throw const ApiException.unsupported(
      'Local password changes go through the account store that owns them.',
    );
  }

  @override
  Future<PasswordResetRequested> requestPasswordReset(String email) {
    throw const ApiException.unsupported('Local password resets go through PasswordResetStore.');
  }

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) {
    throw const ApiException.unsupported('Local password resets go through PasswordResetStore.');
  }

  @override
  Future<void> signOut() async {
    // Nothing to revoke while sessions are local: the Sign In screen replaces
    // the whole navigator stack, which is the sign-out.
  }
}

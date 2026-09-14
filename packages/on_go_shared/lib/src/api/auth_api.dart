import '../models/auth.dart';

/// Accounts and sessions, shared by both front ends.
///
/// The surface split is enforced by the server rather than in either UI — see
/// [SignInRequest.surface] — so neither app has to be trusted to police it.
///
/// Tokens never appear here. Whatever implements this keeps them (the access
/// token in memory, the refresh token in secure storage or an httpOnly
/// cookie); a screen only ever learns who is signed in and what they may do.
abstract interface class AuthApi {
  /// Verifies credentials and opens a session. Never throws for bad
  /// credentials: a wrong password is an expected answer, not an exceptional
  /// one, and comes back as [SignInResult.failed]. Throws [ApiException] for
  /// everything else (rate limiting, validation, an unreachable server).
  Future<SignInResult> signIn(SignInRequest request);

  /// Creates a Client or Mechanic account and signs it in. Throws
  /// [ApiException] with code `conflict` when the email is taken and
  /// `validation_failed` (with field details) when a field is refused.
  Future<AuthenticatedAccount> register(RegisterRequest request);

  /// Re-opens the session this device last held, or returns null when there
  /// is none to open (never signed in, signed out, or the session ended
  /// server-side). Throws [ApiException] of kind
  /// [ApiErrorKind.unreachable] when the server could not be asked, keeping
  /// the stored session for the next attempt.
  Future<AuthenticatedAccount?> restoreSession();

  /// The signed-in account with its current permissions, re-read from the
  /// server — after a `forbidden`, say, when an admin may have changed them.
  Future<AuthenticatedAccount> fetchCurrentAccount();

  /// Changes the signed-in account's own password. Returns false when
  /// [currentPassword] does not match, leaving the password untouched. The
  /// account is always the one signed in.
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Step 1 of a reset: asks for a one-time code for [email]. Answers the same
  /// whether or not the email has an account.
  Future<PasswordResetRequested> requestPasswordReset(String email);

  /// Step 2: sets [newPassword] with the [code] that was delivered. Throws
  /// [ApiException] with code `invalid_reset_code` for a wrong, expired or
  /// over-tried code.
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  });

  /// Ends the session. Never fails on the caller's account: local state is
  /// cleared even when the server cannot be told.
  Future<void> signOut();
}

import 'enums.dart';
import 'json.dart';
import 'moderator_account.dart';

/// What a caller types to sign in. Password-carrying, so it only ever travels
/// to [AuthApi] and only over TLS.
class SignInRequest {
  /// The account email. The local demo implementation also accepts its demo
  /// usernames; the server does not.
  final String identifier;

  final String password;

  /// Which front end is asking. The server refuses a console role signing in
  /// from [AppSurface.mobile] and vice versa (`wrong_surface`), so a leaked
  /// moderator password cannot open a mobile session.
  final AppSurface surface;

  const SignInRequest({
    required this.identifier,
    required this.password,
    required this.surface,
  });

  Map<String, dynamic> toJson() => {
        'identifier': identifier,
        'password': password,
        'surface': surface.wireName,
      };
}

/// A new Client or Mechanic account — `POST /auth/register`. Moderators are
/// never self-registered; an admin creates them.
class RegisterRequest {
  final String email;

  /// 8–128 characters, and must not contain the part of [email] before the
  /// `@` when that part is four or more characters. The server enforces it.
  final String password;

  final String firstName;
  final String? lastName;

  /// Up to 32 characters.
  final String? phone;

  /// [UserRole.client] or [UserRole.mechanic].
  final UserRole role;

  const RegisterRequest({
    required this.email,
    required this.password,
    required this.firstName,
    required this.role,
    this.lastName,
    this.phone,
  });

  /// Optional fields are left out when empty rather than sent as blanks.
  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
        'firstName': firstName,
        if (lastName != null && lastName!.isNotEmpty) 'lastName': lastName,
        if (phone != null && phone!.isNotEmpty) 'phone': phone,
        'role': role.wireName,
      };
}

/// Who is signed in, once [AuthApi.signIn] has said so.
///
/// [accountId] is null for the demo identities the local implementation
/// still supports and for its single built-in admin.
class AuthenticatedUser {
  final String? accountId;
  final String displayName;
  final String email;
  final UserRole role;

  const AuthenticatedUser({
    required this.displayName,
    required this.role,
    this.accountId,
    this.email = '',
  });

  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'displayName': displayName,
        'email': email,
        'role': role.wireName,
      };

  factory AuthenticatedUser.fromJson(Map<String, dynamic> json) => AuthenticatedUser(
        accountId: readStringOrNull(json['accountId']),
        displayName: readString(json['displayName']),
        email: readString(json['email']),
        role: UserRole.fromWire(readString(json['role'])),
      );
}

/// A signed-in account and what it may do — the `{ user, permissions }` pair
/// sign-in, register, refresh and `/auth/me` all return.
///
/// [permissions] is all true for an admin, the granted flags for a moderator,
/// and all false for Clients and Mechanics.
class AuthenticatedAccount {
  final AuthenticatedUser user;
  final ModeratorPermissions permissions;

  const AuthenticatedAccount({
    required this.user,
    this.permissions = ModeratorPermissions.none,
  });

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
        'permissions': permissions.toJson(),
      };

  factory AuthenticatedAccount.fromJson(Map<String, dynamic> json) => AuthenticatedAccount(
        user: AuthenticatedUser.fromJson(readObject(json['user'])),
        permissions: ModeratorPermissions.fromJson(readObject(json['permissions'])),
      );
}

/// The answer to step 1 of a password reset. Always "accepted", whether or not
/// the email has an account, so the reply cannot be used to find accounts.
class PasswordResetRequested {
  /// Safe to show as-is.
  final String message;

  const PasswordResetRequested({required this.message});

  factory PasswordResetRequested.fromJson(Map<String, dynamic> json) =>
      PasswordResetRequested(message: readString(json['message']));
}

/// Why a sign-in did not go through.
///
/// [wrongSurface] is its own case on purpose: an admin typing their password
/// into the mobile app should be told to use the console, not told their
/// password is wrong.
///
/// The server never says whether an email exists, so `invalid_credentials`
/// arrives as [wrongPassword]; [unknownAccount] is only reported by the local
/// implementations.
enum SignInFailure {
  unknownAccount,
  wrongPassword,
  wrongSurface,
  accountInactive,

  /// Too many failed attempts; the account is locked for a while.
  accountLocked,
}

/// The result of a sign-in attempt: exactly one of [account] or [failure].
class SignInResult {
  final AuthenticatedAccount? account;
  final SignInFailure? failure;

  /// The server's own words for [failure], safe to show as-is. Null from the
  /// local implementations, whose screens word the failure themselves.
  final String? message;

  const SignInResult.success(AuthenticatedAccount this.account)
      : failure = null,
        message = null;

  const SignInResult.failed(SignInFailure this.failure, {this.message}) : account = null;

  AuthenticatedUser? get user => account?.user;

  ModeratorPermissions get permissions => account?.permissions ?? ModeratorPermissions.none;

  bool get isSuccess => account != null;
}

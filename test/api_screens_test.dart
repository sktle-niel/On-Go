import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:on_go/data/client_account_store.dart';
import 'package:on_go/data/points_policy_store.dart';
import 'package:on_go/main.dart';
import 'package:on_go/screens/auth/client_registration/client_registration_screen.dart';
import 'package:on_go/screens/auth/client_ui/client_home_screen.dart';
import 'package:on_go/screens/auth/forgot_password_screen.dart';
import 'package:on_go/screens/auth/session_restore_screen.dart';
import 'package:on_go/screens/auth/sign_in_screen.dart';
import 'package:on_go/services/api/mobile_api.dart';
import 'package:on_go/services/backend/mobile_backend.dart';
import 'package:on_go/widgets/change_password_dialog.dart';
import 'package:on_go_api/on_go_api.dart';

import 'api/api_test_support.dart';
import 'responsive_layout_test.dart' show app;

/// The auth screens as they behave with the On Go API installed, driven by a
/// scripted [AuthApi] so no network is involved.
class _ScriptedAuth implements AuthApi {
  Future<SignInResult> Function(SignInRequest request)? signInWith;
  Future<AuthenticatedAccount?> Function()? restoreWith;
  Future<AuthenticatedAccount> Function(RegisterRequest request)? registerWith;
  Future<PasswordResetRequested> Function(String email)? requestResetWith;
  Future<void> Function(String email, String code, String newPassword)? confirmResetWith;
  Future<bool> Function(String current, String next)? changePasswordWith;

  final List<SignInRequest> signInRequests = [];
  final List<RegisterRequest> registerRequests = [];

  @override
  Future<SignInResult> signIn(SignInRequest request) {
    signInRequests.add(request);
    return signInWith!(request);
  }

  @override
  Future<AuthenticatedAccount> register(RegisterRequest request) {
    registerRequests.add(request);
    return registerWith!(request);
  }

  @override
  Future<AuthenticatedAccount?> restoreSession() => restoreWith!();

  @override
  Future<AuthenticatedAccount> fetchCurrentAccount() => throw UnimplementedError();

  @override
  Future<bool> changePassword({required String currentPassword, required String newPassword}) =>
      changePasswordWith!(currentPassword, newPassword);

  @override
  Future<PasswordResetRequested> requestPasswordReset(String email) => requestResetWith!(email);

  @override
  Future<void> confirmPasswordReset({required String email, required String code, required String newPassword}) =>
      confirmResetWith!(email, code, newPassword);

  @override
  Future<void> signOut() async {}
}

const _phone = Size(390, 844);
const _strongPassword = 'Wrench-Turning-42!';

void main() {
  late _ScriptedAuth auth;

  setUp(() {
    auth = _ScriptedAuth();
    MobileBackend.configure(usesApi: true, auth: auth);
  });

  tearDown(() async {
    await MobileApi.debugReset();
    ClientAccountStore.instance.clear();
  });

  Future<void> tapText(WidgetTester tester, String text) async {
    final target = find.text(text);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
    await tester.pump();
  }

  group('Sign In', () {
    Future<void> fillIn(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField).at(0), 'juan@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'a password');
    }

    testWidgets('asks for an email, and an empty form never leaves the phone', (tester) async {
      await tester.pumpWidget(app(_phone, const SignInScreen()));

      expect(find.text('Email'), findsOneWidget);
      await tapText(tester, 'Sign In');

      expect(auth.signInRequests, isEmpty);
      expect(find.text('Enter your email and password.'), findsOneWidget);
    });

    testWidgets("a console account is told so in the server's own words", (tester) async {
      auth.signInWith = (_) async => const SignInResult.failed(
            SignInFailure.wrongSurface,
            message: 'This account signs in on the On Go console.',
          );
      await tester.pumpWidget(app(_phone, const SignInScreen()));
      await fillIn(tester);

      await tapText(tester, 'Sign In');

      expect(auth.signInRequests.single.surface, AppSurface.mobile);
      expect(find.text('This account signs in on the On Go console.'), findsOneWidget);
    });

    testWidgets('an unreachable server is said plainly and the screen stays usable', (tester) async {
      auth.signInWith = (_) async => throw const ApiException(ApiErrorKind.unreachable, unreachableMessage);
      await tester.pumpWidget(app(_phone, const SignInScreen()));
      await fillIn(tester);

      await tapText(tester, 'Sign In');

      expect(find.text(unreachableMessage), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget, reason: 'the button is back, ready to retry');
    });

    testWidgets('a client signs in: the account is taken on and Client Home opens', (tester) async {
      auth.signInWith = (_) async => const SignInResult.success(AuthenticatedAccount(
            user: AuthenticatedUser(
              accountId: '68d136b9-0000-4000-8000-000000000001',
              displayName: 'Juan Dela Cruz',
              email: 'juan@example.com',
              role: UserRole.client,
            ),
          ));
      await tester.pumpWidget(app(_phone, const SignInScreen()));
      await fillIn(tester);

      await tapText(tester, 'Sign In');
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(ClientHomeScreen), findsOneWidget);
      expect(ClientAccountStore.instance.isRegistered, isTrue);
      expect(ClientAccountStore.instance.name, 'Juan Dela Cruz');
      expect(ClientAccountStore.instance.verifyPassword(''), isTrue, reason: 'no password is kept on the phone');
    });
  });

  group('Session restore at launch', () {
    testWidgets('no network: Sign In, with the reason', (tester) async {
      auth.restoreWith = () async => throw const ApiException(ApiErrorKind.unreachable, unreachableMessage);

      await tester.pumpWidget(app(_phone, const SessionRestoreScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.text(restoreUnreachableMessage), findsOneWidget);
    });

    testWidgets('a session that is over: Sign In, without a notice', (tester) async {
      auth.restoreWith = () async => null;

      await tester.pumpWidget(app(_phone, const SessionRestoreScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  testWidgets('Forgot Password: server code, a bad code sends you back, then it goes through', (tester) async {
    const accepted = 'If that email has an account, a code is on its way.';
    final confirmations = <(String, String, String)>[];
    auth.requestResetWith = (_) async => const PasswordResetRequested(message: accepted);
    auth.confirmResetWith = (email, code, password) async {
        confirmations.add((email, code, password));
        if (confirmations.length == 1) {
          throw const ApiException(
            ApiErrorKind.rejected,
            'That code is wrong or has expired.',
            code: ApiErrorCodes.invalidResetCode,
            statusCode: 400,
          );
        }
      };

    await tester.pumpWidget(app(
      _phone,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'juan@example.com');
    await tapText(tester, 'Send Code');
    expect(find.text('Enter your code'), findsOneWidget);
    expect(find.text(accepted), findsOneWidget);
    expect(find.textContaining('your code is'), findsNothing, reason: 'the local stand-in is not shown');

    await tester.enterText(find.byType(TextField).first, '12');
    await tapText(tester, 'Verify Code');
    expect(find.text('Enter the 6-digit code from your email.'), findsOneWidget);

    Future<void> submitCodeAndPassword(String code) async {
      await tester.enterText(find.byType(TextField).first, code);
      await tapText(tester, 'Verify Code');
      expect(find.text('Create a new password'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), _strongPassword);
      await tester.enterText(find.byType(TextField).at(1), _strongPassword);
      await tapText(tester, 'Save New Password');
    }

    await submitCodeAndPassword('123456');
    expect(find.text('Enter your code'), findsOneWidget);
    expect(find.text('That code is wrong or has expired.'), findsOneWidget);

    await submitCodeAndPassword('654321');
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(ForgotPasswordScreen), findsNothing);
    expect(find.text('Password updated. Sign in with your new password.'), findsOneWidget);
    expect(confirmations.last, ('juan@example.com', '654321', _strongPassword));
  });

  testWidgets('Client registration: a taken email is shown under Email and nothing is kept', (tester) async {
    auth.registerWith = (_) async => throw const ApiException(
          ApiErrorKind.rejected,
          'That email is already registered.',
          code: ApiErrorCodes.conflict,
          statusCode: 409,
        );
    await tester.pumpWidget(app(_phone, const ClientRegistrationScreen()));

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'juan@example.com');
    await tester.enterText(fields.at(1), 'Juan');
    await tester.enterText(fields.at(2), 'Dela Cruz');
    await tester.enterText(fields.at(3), 'Puerto Princesa City');
    await tester.enterText(fields.at(4), '09170000000');
    await tester.enterText(fields.at(5), _strongPassword);
    await tester.enterText(fields.at(6), _strongPassword);

    final submit = find.byWidgetPredicate((widget) => widget is ElevatedButton).last;
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    await tester.pump();

    final sent = auth.registerRequests.single;
    expect(sent.role, UserRole.client);
    expect(sent.email, 'juan@example.com');
    expect(sent.password, _strongPassword);
    expect(find.text('That email is already registered.'), findsOneWidget);
    expect(ClientAccountStore.instance.isRegistered, isFalse);
  });

  test("a password change on the server: done, wrong current password, or the server's reason", () async {
    auth.changePasswordWith = (current, next) async => current == 'right';
    expect(await changePasswordOnServer('right', _strongPassword), isNull);
    expect(await changePasswordOnServer('wrong', _strongPassword), 'Current password is incorrect.');

    auth.changePasswordWith = (current, next) async => throw const ApiException(
          ApiErrorKind.rejected,
          'Some fields are not valid.',
          code: ApiErrorCodes.validationFailed,
          details: [ApiFieldError(path: '/newPassword', message: 'must NOT have fewer than 8 characters')],
        );
    expect(await changePasswordOnServer('right', 'short'), 'must NOT have fewer than 8 characters');
  });

  test('the points rules come from the API, and a failed fetch keeps the rules in force', () async {
    addTearDown(() => PointsPolicyStore.instance.debugSet(PointsPolicy.defaults));
    ApiClient clientFor(FakeApiServer server) => ApiClient(
          environment: testEnvironment,
          session: ApiSession(surface: AppSurface.mobile, refreshTokens: InMemoryRefreshTokenStore()),
          httpClient: server.client,
        );

    final online = FakeApiServer()
      ..on('GET', ApiEndpoints.pointsPolicy, (_) => apiJson(200, {
            'clientNormal': 2,
            'clientUrgent': 6,
            'clientEmergency': 10,
            'mechanicPerPeso': 0.1,
          }));
    MobileBackend.configure(pointsPolicy: HttpPointsPolicyApi(clientFor(online)));
    await PointsPolicyStore.instance.load();
    await settle();
    expect(PointsPolicyStore.instance.current.clientUrgent, 6);

    final offline = FakeApiServer()
      ..on('GET', ApiEndpoints.pointsPolicy, (_) => throw http.ClientException('offline'));
    MobileBackend.configure(pointsPolicy: HttpPointsPolicyApi(clientFor(offline)));
    await PointsPolicyStore.instance.load();
    await settle();
    expect(PointsPolicyStore.instance.current.clientUrgent, 6);
  });

  testWidgets('a session the server ends sends the user to Sign In and says why', (tester) async {
    final api = MobileApi.install(
      environment: testEnvironment,
      refreshTokens: InMemoryRefreshTokenStore(),
      httpClient: FakeApiServer().client,
      eventConnector: neverConnect,
    );
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    await api.session.adopt(AuthSessionPayload.fromJson(sessionBody()), newSession: true);
    await api.session.end(SessionEndReason.invalid);
    // The session event arrives, the route is replaced and its transition
    // runs, then the notice is shown after Sign In's first frame.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text('You were signed out. Please sign in again.'), findsOneWidget);
  });
}

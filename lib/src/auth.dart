import 'package:http/http.dart' as http;
import 'http.dart';

/// A signed-in user's session.
class Session {
  final String accessToken;
  final String refreshToken;

  /// Epoch seconds when the access token expires (best-effort, from
  /// `expires_in`).
  final int? expiresAt;
  final Map<String, dynamic>? user;

  const Session({
    required this.accessToken,
    required this.refreshToken,
    this.expiresAt,
    this.user,
  });

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        if (expiresAt != null) 'expires_at': expiresAt,
        if (user != null) 'user': user,
      };

  static Session? fromJson(Map<String, dynamic> j) {
    final at = j['access_token'];
    final rt = j['refresh_token'];
    if (at is! String || rt is! String) return null;
    return Session(
      accessToken: at,
      refreshToken: rt,
      expiresAt: j['expires_at'] as int?,
      user: (j['user'] as Map?)?.cast<String, dynamic>(),
    );
  }
}

enum AuthEvent { signedIn, signedOut, tokenRefreshed }

/// Result of [Auth.login]. Either [session] is set (normal login — already
/// stored), or [twofaRequired] is true: the project requires 2-step
/// verification, a code and/or magic link was emailed (see [twofaMethods]),
/// and you finish with [Auth.verifyTwoFactor] / [Auth.verifyTwoFactorMagic].
class LoginResult {
  final Session? session;
  final bool twofaRequired;
  final List<String> twofaMethods;
  const LoginResult({
    this.session,
    this.twofaRequired = false,
    this.twofaMethods = const [],
  });
}

/// Auth surface — signup/login plus session helpers. The [Ichibase] client
/// owns the live session; this talks to `/auth/*` and reports changes back
/// through the supplied callbacks.
class Auth {
  final String _baseUrl;
  final String _key;
  final http.Client _http;
  final Session? Function() _getSession;
  final Future<void> Function(Session?, AuthEvent) _setSession;

  Auth(this._baseUrl, this._key, this._http, this._getSession, this._setSession);

  Future<IchibaseResponse<Map<String, dynamic>>> _call(
    String path, {
    String method = 'POST',
    Object? body,
    String? auth,
  }) async {
    final url = Uri.parse(urlJoin(_baseUrl, '/auth$path'));
    // auth-svc requires the project (anon) key in the `apikey` header. The
    // end-user's access token — only when acting as a user (e.g. /me, /logout) —
    // goes in Authorization: Bearer.
    final res = await sendRequest(_http, method, url,
        bearer: auth, jsonBody: body, extraHeaders: {'apikey': _key});
    return toResponse<Map<String, dynamic>>(
        res, (b) => (b is Map ? b.cast<String, dynamic>() : <String, dynamic>{}));
  }

  /// Register a new end user.
  Future<IchibaseResponse<Map<String, dynamic>>> signup({
    required String email,
    required String password,
  }) =>
      _call('/signup', body: {'email': email, 'password': password});

  /// Log in. Returns a [LoginResult]: normally `result.session` is set (and
  /// stored, so subsequent data calls run as this user). When the project
  /// requires 2-step verification, the password step instead yields
  /// `result.twofaRequired == true` — a code and/or magic link was emailed;
  /// finish with [verifyTwoFactor] or [verifyTwoFactorMagic].
  Future<IchibaseResponse<LoginResult>> login({
    required String email,
    required String password,
  }) async {
    final res = await _call('/login', body: {'email': email, 'password': password});
    final d = res.data;
    if (d == null) return IchibaseResponse(error: res.error);
    if (d['twofa_required'] == true) {
      return IchibaseResponse(
        data: LoginResult(
          twofaRequired: true,
          twofaMethods: (d['methods'] as List?)?.cast<String>() ?? const <String>[],
        ),
      );
    }
    if (d['access_token'] != null) {
      final s = Session(
        accessToken: d['access_token'] as String,
        refreshToken: d['refresh_token'] as String,
        expiresAt: _expiresAt(d['expires_in']),
        user: (d['user'] as Map?)?.cast<String, dynamic>(),
      );
      await _setSession(s, AuthEvent.signedIn);
      return IchibaseResponse(data: LoginResult(session: s));
    }
    return IchibaseResponse(error: res.error);
  }

  /// Exchange the stored refresh token for a fresh access token.
  Future<IchibaseResponse<Session>> refresh() async {
    final cur = _getSession();
    if (cur == null) {
      return IchibaseResponse<Session>(
          error: const IchibaseError(
              code: 'no_session', detail: 'not logged in', status: 401));
    }
    final res = await _call('/refresh', body: {'refresh_token': cur.refreshToken});
    final d = res.data;
    if (d != null && d['access_token'] != null) {
      final s = Session(
        accessToken: d['access_token'] as String,
        refreshToken: d['refresh_token'] as String,
        expiresAt: _expiresAt(d['expires_in']),
        user: cur.user,
      );
      await _setSession(s, AuthEvent.tokenRefreshed);
      return IchibaseResponse(data: s);
    }
    return IchibaseResponse(error: res.error);
  }

  /// The current signed-in user (from the live access token), or `null`.
  Future<Map<String, dynamic>?> getUser() async {
    final s = _getSession();
    if (s == null) return null;
    final res = await _call('/me', method: 'GET', auth: s.accessToken);
    return res.data;
  }

  /// Sign out: revoke the refresh token and clear the local session.
  Future<void> logout() async {
    final s = _getSession();
    if (s != null) {
      await _call('/logout', body: {'refresh_token': s.refreshToken}, auth: s.accessToken);
    }
    await _setSession(null, AuthEvent.signedOut);
  }

  Future<IchibaseResponse<Map<String, dynamic>>> requestPasswordReset(String email) =>
      _call('/password-reset/request', body: {'email': email});

  Future<IchibaseResponse<Map<String, dynamic>>> confirmPasswordReset(
          String token, String newPassword) =>
      _call('/password-reset/confirm',
          body: {'token': token, 'new_password': newPassword});

  /// Confirm a password reset with the emailed 6-digit code (reset mode
  /// 'otp'/'both') instead of a link token.
  Future<IchibaseResponse<Map<String, dynamic>>> confirmPasswordResetOtp(
          String email, String code, String newPassword) =>
      _call('/password-reset/confirm-otp',
          body: {'email': email, 'code': code, 'new_password': newPassword});

  Future<IchibaseResponse<Map<String, dynamic>>> verifyEmail(String token) =>
      _call('/verify-email', body: {'token': token});

  Future<IchibaseResponse<Map<String, dynamic>>> verifyEmailOtp(
          String email, String code) =>
      _call('/verify-email/otp', body: {'email': email, 'code': code});

  Future<IchibaseResponse<Map<String, dynamic>>> resendVerification(String email) =>
      _call('/verify-email/resend', body: {'email': email});

  // ── Passwordless login (OTP + magic link) ──────────────────────────
  // Additive to email+password. The project must enable it (and configure
  // custom SMTP). One email may carry an OTP code, a magic link, or both —
  // whichever the project enabled.

  /// Send the passwordless sign-in email. Always succeeds (202) even for
  /// unknown emails — it never reveals whether an account exists; a new
  /// email creates the account on first verify. Finish with [verifyOtp]
  /// (the typed code) or [verifyMagicLink] (the token from the tapped link).
  Future<IchibaseResponse<Map<String, dynamic>>> signInWithOtp({
    required String email,
  }) =>
      _call('/login/passwordless/request', body: {'email': email});

  /// Verify a passwordless OTP code and sign the user in. On success the
  /// session is stored and subsequent data calls run as this user.
  Future<IchibaseResponse<Session>> verifyOtp({
    required String email,
    required String code,
  }) async {
    final res = await _call('/login/passwordless/verify',
        body: {'email': email, 'code': code});
    return _finishLogin(res);
  }

  /// Redeem a magic-link token (the `token` query-param from the tapped
  /// URL) and sign the user in. On success the session is stored.
  Future<IchibaseResponse<Session>> verifyMagicLink(String token) async {
    final res = await _call('/login/magic', body: {'token': token});
    return _finishLogin(res);
  }

  // ── 2-step verification (second factor after a password login) ──────
  // Call after [login] returns a result with twofaRequired == true.

  /// Finish a 2-step login with the emailed code. Stores the session.
  Future<IchibaseResponse<Session>> verifyTwoFactor({
    required String email,
    required String code,
  }) async {
    final res = await _call('/login/2fa/verify', body: {'email': email, 'code': code});
    return _finishLogin(res);
  }

  /// Finish a 2-step login by redeeming a magic-link token (from the tapped
  /// link). Stores the session.
  Future<IchibaseResponse<Session>> verifyTwoFactorMagic(String token) async {
    final res = await _call('/login/2fa/magic', body: {'token': token});
    return _finishLogin(res);
  }

  /// Turn a token-pair response into a stored session (SIGNED_IN), or pass
  /// the error through. Shared by the passwordless verify calls.
  Future<IchibaseResponse<Session>> _finishLogin(
    IchibaseResponse<Map<String, dynamic>> res,
  ) async {
    final d = res.data;
    if (d != null && d['access_token'] != null) {
      final s = Session(
        accessToken: d['access_token'] as String,
        refreshToken: d['refresh_token'] as String,
        expiresAt: _expiresAt(d['expires_in']),
        user: (d['user'] as Map?)?.cast<String, dynamic>(),
      );
      await _setSession(s, AuthEvent.signedIn);
      return IchibaseResponse(data: s);
    }
    return IchibaseResponse(error: res.error);
  }

  static int? _expiresAt(dynamic expiresIn) {
    if (expiresIn is! int) return null;
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 + expiresIn;
  }
}

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
    final res = await sendRequest(_http, method, url,
        bearer: auth ?? _key, jsonBody: body);
    return toResponse<Map<String, dynamic>>(
        res, (b) => (b is Map ? b.cast<String, dynamic>() : <String, dynamic>{}));
  }

  /// Register a new end user.
  Future<IchibaseResponse<Map<String, dynamic>>> signup({
    required String email,
    required String password,
  }) =>
      _call('/signup', body: {'email': email, 'password': password});

  /// Log in. On success the session is stored and subsequent data calls run
  /// as this user.
  Future<IchibaseResponse<Session>> login({
    required String email,
    required String password,
  }) async {
    final res = await _call('/login', body: {'email': email, 'password': password});
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

  Future<IchibaseResponse<Map<String, dynamic>>> verifyEmail(String token) =>
      _call('/verify-email', body: {'token': token});

  Future<IchibaseResponse<Map<String, dynamic>>> verifyEmailOtp(
          String email, String code) =>
      _call('/verify-email/otp', body: {'email': email, 'code': code});

  Future<IchibaseResponse<Map<String, dynamic>>> resendVerification(String email) =>
      _call('/verify-email/resend', body: {'email': email});

  static int? _expiresAt(dynamic expiresIn) {
    if (expiresIn is! int) return null;
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 + expiresIn;
  }
}

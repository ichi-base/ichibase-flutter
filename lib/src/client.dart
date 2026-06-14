import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth.dart';
import 'http.dart';
import 'mongo.dart';
import 'postgrest.dart';
import 'realtime.dart';
import 'session_storage.dart';
import 'storage.dart';

/// The single client a Flutter/Dart app uses. **Anon key only.**
///
/// ```dart
/// final ichi = Ichibase.createClient(
///   'https://<project>.ichibase.net',
///   'ich_pub_…',
/// );
/// final res = await ichi.from('posts').select('*');
/// await ichi.auth.login(email: email, password: password);
/// ```
///
/// One config + one session shared across Postgres, Auth, Storage, Mongo, and
/// Realtime. After login, data calls use the user's access token so your RLS /
/// policies / realtime rules apply per-user; logged out, they use the
/// publishable anon key.
class Ichibase {
  /// Project base URL, e.g. `https://abc.ichibase.net` (no trailing slash).
  final String url;

  final String _anonKey;
  final http.Client _http;
  final SessionStore _store;
  final String _storageKey;
  Session? _session;
  RealtimeClient? _realtime;
  final StreamController<({AuthEvent event, Session? session})> _authController =
      StreamController.broadcast();

  /// Auth surface (signup/login/logout/refresh/getUser …).
  late final Auth auth;

  Ichibase(
    String url,
    String anonKey, {
    http.Client? httpClient,
    SessionStore? store,
    String storageKey = 'ichibase.session',
  })  : url = _strip(url),
        _anonKey = anonKey,
        _http = httpClient ?? http.Client(),
        _store = store ?? MemorySessionStore(),
        _storageKey = storageKey {
    if (anonKey.isEmpty) {
      throw ArgumentError('ichibase: anon key is required');
    }
    if (anonKey.startsWith('ich_admin_')) {
      throw ArgumentError(
        'ichibase: this client is anon-key only. ich_admin_ (service) keys bypass '
        'RLS — never ship them in an app. Use them server-side instead.',
      );
    }
    auth = Auth(this.url, _anonKey, _http, () => _session, _setSession);
    // Hydrate from a synchronous store (MemorySessionStore). Async adapters
    // need an explicit `await loadSession()`.
    final raw = _store.getItem(_storageKey);
    if (raw is String) _session = _parseSession(raw);
  }

  /// Create a client. Mirrors the TypeScript `createClient`.
  static Ichibase createClient(
    String url,
    String anonKey, {
    http.Client? httpClient,
    SessionStore? store,
    String storageKey = 'ichibase.session',
  }) =>
      Ichibase(url, anonKey,
          httpClient: httpClient, store: store, storageKey: storageKey);

  String _bearer() => _session?.accessToken ?? _anonKey;

  // ── Postgres ───────────────────────────────────────────────────────
  /// Start a PostgREST query against a table or view.
  PostgrestQueryBuilder from(String table) =>
      Postgrest(url, _bearer(), _http).from(table);

  /// Call a Postgres function (RPC).
  Future<IchibaseResponse<dynamic>> rpc(
    String fn, {
    Map<String, dynamic> args = const {},
    String? schema,
    String? count,
  }) =>
      Postgrest(url, _bearer(), _http)
          .rpc(fn, args: args, schema: schema, count: count);

  // ── Storage / Mongo / Realtime ─────────────────────────────────────
  Storage get storage => Storage(url, _bearer(), _http);

  Mongo get mongo {
    final m = Mongo(url, _anonKey, _http);
    final s = _session;
    return s != null ? m.asUser(s.accessToken) : m;
  }

  RealtimeClient get realtime => _realtime ??= RealtimeClient(url, _bearer);

  // ── Session ────────────────────────────────────────────────────────
  Session? get session => _session;

  /// Auth state changes: `(event: signedIn|signedOut|tokenRefreshed, session)`.
  Stream<({AuthEvent event, Session? session})> get onAuthStateChange =>
      _authController.stream;

  /// Hydrate the session from the storage adapter (call once at startup for
  /// async adapters like secure storage).
  Future<Session?> loadSession() async {
    try {
      final raw = await _store.getItem(_storageKey);
      _session = raw is String ? _parseSession(raw) : null;
    } catch (_) {
      _session = null;
    }
    return _session;
  }

  /// Set the session directly (e.g. restored from your own cookie/SSR).
  Future<void> setSession(Session? session) =>
      _setSession(session, session != null ? AuthEvent.signedIn : AuthEvent.signedOut);

  Future<void> _setSession(Session? s, AuthEvent ev) async {
    _session = s;
    try {
      if (s != null) {
        await _store.setItem(_storageKey, jsonEncode(s.toJson()));
      } else {
        await _store.removeItem(_storageKey);
      }
    } catch (_) {
      // persistence is best-effort
    }
    if (!_authController.isClosed) {
      _authController.add((event: ev, session: s));
    }
  }

  /// Release resources (HTTP client, realtime socket, streams).
  void dispose() {
    _realtime?.disconnect();
    _authController.close();
    _http.close();
  }

  static String _strip(String u) =>
      u.endsWith('/') ? u.substring(0, u.length - 1) : u;

  static Session? _parseSession(String raw) {
    try {
      final j = jsonDecode(raw);
      return j is Map ? Session.fromJson(j.cast<String, dynamic>()) : null;
    } catch (_) {
      return null;
    }
  }
}

/// Create a client. Mirrors the TypeScript `createClient(url, anonKey)`.
Ichibase createClient(
  String url,
  String anonKey, {
  http.Client? httpClient,
  SessionStore? store,
  String storageKey = 'ichibase.session',
}) =>
    Ichibase(url, anonKey,
        httpClient: httpClient, store: store, storageKey: storageKey);

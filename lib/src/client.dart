import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth.dart';
import 'functions.dart';
import 'http.dart';
import 'mongo.dart';
import 'postgrest.dart';
import 'realtime.dart';
import 'session_storage.dart';
// Picks a durable session store for the platform (file on IO, localStorage on
// web, in-memory otherwise) so persistence works with zero developer setup.
import 'default_store_stub.dart'
    if (dart.library.io) 'default_store_io.dart'
    if (dart.library.js_interop) 'default_store_web.dart';

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
/// One config + one session shared across Postgres, Auth, Mongo, and Realtime.
/// After login, data calls use the user's access token so your RLS /
/// policies / realtime rules apply per-user; logged out, they use the
/// publishable anon key.
class Ichibase {
  /// Project base URL, e.g. `https://abc.ichibase.net` (no trailing slash).
  final String url;

  final String _anonKey;
  // _rawHttp: used by Auth (its /refresh must not recurse through the refresher).
  // _http: a wrapper that auto-refreshes the JWT + retries once on a 401 — used
  // by all data modules (Postgrest / Mongo / Functions).
  final http.Client _rawHttp;
  late final http.Client _http;
  Future<bool>? _refreshing; // single-flight token refresh
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
        _rawHttp = httpClient ?? http.Client(),
        _store = store ?? defaultSessionStore(),
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
    auth = Auth(this.url, _anonKey, _rawHttp, () => _session, _setSession);
    // Data modules go through a wrapper that transparently refreshes an expired
    // access token + retries the request once on a 401, instead of erroring.
    _http = _RefreshingClient(
        _rawHttp, () => _session?.accessToken, _autoRefresh);
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

  // ── Global singleton (Supabase-style) ──────────────────────────────
  static Ichibase? _instance;

  /// The global client created by [initialize]. Use it anywhere — no
  /// `BuildContext`, no prop-drilling. Throws if [initialize] hasn't run.
  ///
  /// ```dart
  /// await Ichibase.initialize('https://abc.ichibase.net', 'ich_pub_…');
  /// // later, anywhere:
  /// final res = await Ichibase.instance.from('posts').select('*');
  /// ```
  static Ichibase get instance {
    final i = _instance;
    if (i == null) {
      throw StateError(
          'ichibase: call Ichibase.initialize(url, anonKey) before using Ichibase.instance');
    }
    return i;
  }

  /// Whether [initialize] has run.
  static bool get isInitialized => _instance != null;

  /// Initialize the global singleton once (e.g. in `main()`), then use
  /// [Ichibase.instance] everywhere. Mirrors `Supabase.initialize`.
  ///
  /// The session is persisted automatically (a file on mobile/desktop/server,
  /// `localStorage` on web) and rehydrated here — pass [store] only to override
  /// that default. Calling this again replaces the singleton (the previous one
  /// is disposed).
  static Future<Ichibase> initialize(
    String url,
    String anonKey, {
    http.Client? httpClient,
    SessionStore? store,
    String storageKey = 'ichibase.session',
  }) async {
    _instance?.dispose();
    final client = Ichibase(url, anonKey,
        httpClient: httpClient, store: store, storageKey: storageKey);
    await client.loadSession();
    _instance = client;
    return client;
  }

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

  // ── Mongo / Realtime ───────────────────────────────────────────────
  // NOTE: file Storage is intentionally NOT on the client. The project owner
  // mints read tokens / signs upload URLs server-side (Edge Function + service
  // key) and hands them to users. Public files: cdn.ichibase.net/<project>/public/...
  Mongo get mongo {
    final m = Mongo(url, _anonKey, _http);
    final s = _session;
    return s != null ? m.asUser(s.accessToken) : m;
  }

  RealtimeClient get realtime => _realtime ??= RealtimeClient(url, _bearer);

  /// Invoke your deployed Edge Functions: `ichi.functions.invoke('name', body: {...})`.
  Functions get functions {
    final f = Functions(url, _anonKey, _http);
    final s = _session;
    return s != null ? f.asUser(s.accessToken) : f;
  }

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

  // Refresh the access token, sharing one in-flight refresh across concurrent
  // 401 retries. Returns true if a valid session is in place afterwards.
  Future<bool> _autoRefresh() {
    final existing = _refreshing;
    if (existing != null) return existing;
    final f = () async {
      final r = await auth.refresh();
      return r.ok && _session != null;
    }();
    _refreshing = f;
    f.whenComplete(() {
      if (identical(_refreshing, f)) _refreshing = null;
    });
    return f;
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

/// Wraps an [http.Client] so a 401 on a request that carried the signed-in
/// user's access token triggers a single token refresh + one retry — the SDK
/// transparently recovers from an expired JWT instead of surfacing the error.
/// Anon-key requests (no session) are never retried — a 401 there is a real
/// auth failure.
class _RefreshingClient extends http.BaseClient {
  final http.Client _inner;
  final String? Function() _accessToken;
  final Future<bool> Function() _refresh;
  _RefreshingClient(this._inner, this._accessToken, this._refresh);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final res = await _inner.send(request);
    if (res.statusCode != 401 || request is! http.Request) return res;
    final token = _accessToken();
    if (token == null ||
        request.headers['Authorization'] != 'Bearer $token') {
      return res; // anon / non-user-token request → genuine 401
    }
    // Buffer the body so the original 401 can still be returned if refresh fails.
    final body = await res.stream.toBytes();
    final ok = await _refresh();
    final fresh = _accessToken();
    if (!ok || fresh == null) {
      return http.StreamedResponse(Stream.value(body), res.statusCode,
          headers: res.headers,
          reasonPhrase: res.reasonPhrase,
          request: res.request);
    }
    final retry = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = request.bodyBytes
      ..followRedirects = request.followRedirects
      ..persistentConnection = request.persistentConnection;
    retry.headers['Authorization'] = 'Bearer $fresh';
    return _inner.send(retry);
  }

  @override
  void close() => _inner.close();
}

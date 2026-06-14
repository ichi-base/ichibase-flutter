import 'dart:async';
import 'package:http/http.dart' as http;
import 'http.dart';

/// Entry point for the database REST API. Get one via `ichi.from(table)`.
class Postgrest {
  final String _baseUrl;
  final String _key;
  final http.Client _http;
  Postgrest(this._baseUrl, this._key, this._http);

  /// Start a query against a table or view.
  PostgrestQueryBuilder from(String table) =>
      PostgrestQueryBuilder(_baseUrl, _key, _http, table);

  /// Call a Postgres function (RPC). Read-only functions can also be reached
  /// with [head]; pass [count] to get a total alongside the rows.
  Future<IchibaseResponse<dynamic>> rpc(
    String fn, {
    Map<String, dynamic> args = const {},
    String? schema,
    String? count,
  }) async {
    final url = Uri.parse(urlJoin(_baseUrl, '/postgres/rpc/$fn'));
    final headers = <String, String>{};
    if (count != null) headers['Prefer'] = 'count=$count';
    if (schema != null) headers['Content-Profile'] = schema;
    final res = await sendRequest(_http, 'POST', url,
        bearer: _key, jsonBody: args, extraHeaders: headers);
    return toResponse<dynamic>(res, (b) => b);
  }
}

/// A chainable PostgREST query. Awaiting it sends the request, so
/// `await ichi.from('posts').select('*').eq('published', true)` just works.
/// The resolved [IchibaseResponse.data] is a `List<dynamic>` of rows, a single
/// row for [single]/[maybeSingle], or `{rows, count}` when [count] is set.
class PostgrestQueryBuilder implements Future<IchibaseResponse<dynamic>> {
  final String _baseUrl;
  final String _key;
  final http.Client _http;
  final String _table;

  final List<String> _filters = [];
  String _method = 'GET';
  Object? _body;
  bool _returnRepresentation = false;
  bool _single = false;
  bool _maybeSingle = false;
  String? _countMode;
  String? _onConflict;
  int? _rangeFrom;
  int? _rangeTo;
  final Map<String, String> _extraHeaders = {};

  PostgrestQueryBuilder(this._baseUrl, this._key, this._http, this._table);

  // ── verbs ──────────────────────────────────────────────────────────
  PostgrestQueryBuilder select([String columns = '*']) {
    _method = 'GET';
    _filters.add('select=${Uri.encodeQueryComponent(columns)}');
    return this;
  }

  PostgrestQueryBuilder insert(Object rows, {bool returning = true}) {
    _method = 'POST';
    _body = rows;
    _returnRepresentation = returning;
    return this;
  }

  PostgrestQueryBuilder upsert(Object rows,
      {String? onConflict, bool returning = true}) {
    _method = 'POST';
    _body = rows;
    _onConflict = onConflict;
    _returnRepresentation = returning;
    _extraHeaders['Prefer'] = 'resolution=merge-duplicates';
    return this;
  }

  PostgrestQueryBuilder update(Map<String, dynamic> values,
      {bool returning = true}) {
    _method = 'PATCH';
    _body = values;
    _returnRepresentation = returning;
    return this;
  }

  PostgrestQueryBuilder delete({bool returning = true}) {
    _method = 'DELETE';
    _returnRepresentation = returning;
    return this;
  }

  // ── filters ────────────────────────────────────────────────────────
  PostgrestQueryBuilder eq(String col, Object value) => _f(col, 'eq', value);
  PostgrestQueryBuilder neq(String col, Object value) => _f(col, 'neq', value);
  PostgrestQueryBuilder gt(String col, Object value) => _f(col, 'gt', value);
  PostgrestQueryBuilder gte(String col, Object value) => _f(col, 'gte', value);
  PostgrestQueryBuilder lt(String col, Object value) => _f(col, 'lt', value);
  PostgrestQueryBuilder lte(String col, Object value) => _f(col, 'lte', value);
  PostgrestQueryBuilder like(String col, String pattern) =>
      _f(col, 'like', pattern);
  PostgrestQueryBuilder ilike(String col, String pattern) =>
      _f(col, 'ilike', pattern);
  PostgrestQueryBuilder isFilter(String col, Object? value) =>
      _f(col, 'is', value ?? 'null');

  PostgrestQueryBuilder inFilter(String col, List<Object> values) {
    final encoded = values.map((v) => v.toString()).join(',');
    _filters.add('${Uri.encodeQueryComponent(col)}=in.($encoded)');
    return this;
  }

  /// Escape hatch for any PostgREST operator: `.filter('age', 'gte', 18)`.
  PostgrestQueryBuilder filter(String col, String op, Object value) =>
      _f(col, op, value);

  PostgrestQueryBuilder _f(String col, String op, Object value) {
    _filters
        .add('${Uri.encodeQueryComponent(col)}=$op.${Uri.encodeQueryComponent(value.toString())}');
    return this;
  }

  // ── modifiers ──────────────────────────────────────────────────────
  PostgrestQueryBuilder order(String column, {bool ascending = true}) {
    _filters.add('order=${Uri.encodeQueryComponent(column)}.${ascending ? 'asc' : 'desc'}');
    return this;
  }

  PostgrestQueryBuilder limit(int n) {
    _filters.add('limit=$n');
    return this;
  }

  PostgrestQueryBuilder range(int from, int to) {
    _rangeFrom = from;
    _rangeTo = to;
    return this;
  }

  /// Expect exactly one row; [IchibaseResponse.data] is a `Map` (not a list).
  PostgrestQueryBuilder single() {
    _single = true;
    return this;
  }

  /// Return the first row or `null`; never errors on empty.
  PostgrestQueryBuilder maybeSingle() {
    _maybeSingle = true;
    return this;
  }

  /// Ask for a total count: data becomes `{ 'rows': [...], 'count': n }`.
  PostgrestQueryBuilder count([String mode = 'exact']) {
    _countMode = mode;
    return this;
  }

  // ── execution ──────────────────────────────────────────────────────
  Future<IchibaseResponse<dynamic>> _exec() async {
    final filters = List<String>.from(_filters);
    if (_onConflict != null) {
      filters.add('on_conflict=${Uri.encodeQueryComponent(_onConflict!)}');
    }
    final qs = filters.isEmpty ? '' : '?${filters.join('&')}';
    final url = Uri.parse(urlJoin(_baseUrl, '/postgres/$_table$qs'));

    final headers = <String, String>{..._extraHeaders};
    final prefer = <String>[];
    if (headers['Prefer'] != null) prefer.add(headers.remove('Prefer')!);
    if (_returnRepresentation && _method != 'GET') {
      prefer.add('return=representation');
    }
    if (_countMode != null) prefer.add('count=$_countMode');
    if (prefer.isNotEmpty) headers['Prefer'] = prefer.join(',');
    if (_single) headers['Accept'] = 'application/vnd.pgrst.object+json';
    if (_rangeFrom != null && _rangeTo != null) {
      headers['Range-Unit'] = 'items';
      headers['Range'] = '$_rangeFrom-$_rangeTo';
    }

    final res = await sendRequest(_http, _method, url,
        bearer: _key, jsonBody: _body, extraHeaders: headers);

    if (_countMode != null) {
      final contentRange = res.headers['content-range'];
      final total = contentRange?.split('/').last;
      final c = (total != null && total != '*') ? int.tryParse(total) ?? 0 : 0;
      return toResponse<dynamic>(res, (b) => {'rows': b ?? [], 'count': c});
    }
    if (_maybeSingle) {
      return toResponse<dynamic>(res, (b) => b is List ? (b.isEmpty ? null : b.first) : b);
    }
    return toResponse<dynamic>(res, (b) => b);
  }

  // ── Future delegation (makes `await builder` execute the request) ────
  @override
  Future<R> then<R>(FutureOr<R> Function(IchibaseResponse<dynamic>) onValue,
          {Function? onError}) =>
      _exec().then(onValue, onError: onError);

  @override
  Future<IchibaseResponse<dynamic>> catchError(Function onError,
          {bool Function(Object)? test}) =>
      _exec().catchError(onError, test: test);

  @override
  Future<IchibaseResponse<dynamic>> whenComplete(FutureOr<void> Function() action) =>
      _exec().whenComplete(action);

  @override
  Stream<IchibaseResponse<dynamic>> asStream() => _exec().asStream();

  @override
  Future<IchibaseResponse<dynamic>> timeout(Duration timeLimit,
          {FutureOr<IchibaseResponse<dynamic>> Function()? onTimeout}) =>
      _exec().timeout(timeLimit, onTimeout: onTimeout);
}

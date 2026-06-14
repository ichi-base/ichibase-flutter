import 'package:http/http.dart' as http;
import 'http.dart';

/// MongoDB data client. The project key goes in the `apikey` header; the
/// signed-in user's token (set via [asUser]) goes in `Authorization: Bearer`,
/// so your Mongo policy sees both.
class Mongo {
  final String _baseUrl;
  final String _key;
  final http.Client _http;
  final String? _userToken;
  Mongo(this._baseUrl, this._key, this._http, [this._userToken]);

  /// Return a Mongo client that acts as a specific end user.
  Mongo asUser(String accessToken) =>
      Mongo(_baseUrl, _key, _http, accessToken);

  MongoCollection collection(String name) =>
      MongoCollection(_baseUrl, _key, _http, name, _userToken);
}

/// Operations on one collection. Every call POSTs to
/// `/mongo/v1/<op>/<collection>`. Reads/writes are gated by your Mongo policy.
class MongoCollection {
  final String _baseUrl;
  final String _key;
  final http.Client _http;
  final String name;
  final String? _userToken;
  MongoCollection(this._baseUrl, this._key, this._http, this.name, this._userToken);

  Future<IchibaseResponse<dynamic>> _op(String op, Map<String, dynamic> body) async {
    final url = Uri.parse(urlJoin(_baseUrl, '/mongo/v1/$op/$name'));
    final headers = <String, String>{'apikey': _key};
    if (_userToken != null) headers['Authorization'] = 'Bearer $_userToken';
    final res = await sendRequest(_http, 'POST', url,
        jsonBody: body, extraHeaders: headers);
    return toResponse<dynamic>(res, (b) => b);
  }

  // ── reads ──────────────────────────────────────────────────────────
  Future<IchibaseResponse<dynamic>> find(
    Map<String, dynamic> filter, {
    Map<String, dynamic>? projection,
    Map<String, dynamic>? sort,
    int? limit,
    int? skip,
  }) =>
      _op('find', {
        'filter': filter,
        if (projection != null) 'projection': projection,
        if (sort != null) 'sort': sort,
        if (limit != null) 'limit': limit,
        if (skip != null) 'skip': skip,
      });

  Future<IchibaseResponse<dynamic>> findOne(
    Map<String, dynamic> filter, {
    Map<String, dynamic>? projection,
  }) =>
      _op('findOne', {
        'filter': filter,
        if (projection != null) 'projection': projection,
      });

  Future<IchibaseResponse<dynamic>> count(Map<String, dynamic> filter) =>
      _op('count', {'filter': filter});

  Future<IchibaseResponse<dynamic>> aggregate(List<Map<String, dynamic>> pipeline) =>
      _op('aggregate', {'pipeline': pipeline});

  Future<IchibaseResponse<dynamic>> distinct(String field,
          {Map<String, dynamic>? filter}) =>
      _op('distinct', {'field': field, if (filter != null) 'filter': filter});

  // ── inserts ────────────────────────────────────────────────────────
  Future<IchibaseResponse<dynamic>> insertOne(Map<String, dynamic> doc) =>
      _op('insertOne', {'doc': doc});

  Future<IchibaseResponse<dynamic>> insertMany(List<Map<String, dynamic>> docs) =>
      _op('insertMany', {'docs': docs});

  // ── updates ────────────────────────────────────────────────────────
  Future<IchibaseResponse<dynamic>> updateOne(
    Map<String, dynamic> filter,
    Map<String, dynamic> update, {
    bool upsert = false,
  }) =>
      _op('updateOne', {'filter': filter, 'update': update, 'upsert': upsert});

  Future<IchibaseResponse<dynamic>> updateMany(
    Map<String, dynamic> filter,
    Map<String, dynamic> update, {
    bool upsert = false,
  }) =>
      _op('updateMany', {'filter': filter, 'update': update, 'upsert': upsert});

  Future<IchibaseResponse<dynamic>> replaceOne(
    Map<String, dynamic> filter,
    Map<String, dynamic> replacement, {
    bool upsert = false,
  }) =>
      _op('replaceOne',
          {'filter': filter, 'replacement': replacement, 'upsert': upsert});

  Future<IchibaseResponse<dynamic>> findOneAndUpdate(
    Map<String, dynamic> filter,
    Map<String, dynamic> update, {
    bool upsert = false,
    bool returnAfter = true,
  }) =>
      _op('findOneAndUpdate', {
        'filter': filter,
        'update': update,
        'upsert': upsert,
        'return': returnAfter ? 'after' : 'before',
      });

  Future<IchibaseResponse<dynamic>> findOneAndDelete(Map<String, dynamic> filter) =>
      _op('findOneAndDelete', {'filter': filter});

  // ── deletes ────────────────────────────────────────────────────────
  Future<IchibaseResponse<dynamic>> deleteOne(Map<String, dynamic> filter) =>
      _op('deleteOne', {'filter': filter});

  Future<IchibaseResponse<dynamic>> deleteMany(Map<String, dynamic> filter) =>
      _op('deleteMany', {'filter': filter});

  // ── bulk ───────────────────────────────────────────────────────────
  Future<IchibaseResponse<dynamic>> bulkWrite(
    List<Map<String, dynamic>> operations, {
    bool ordered = true,
  }) =>
      _op('bulkWrite', {'operations': operations, 'ordered': ordered});
}

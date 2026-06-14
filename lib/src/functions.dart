import 'dart:convert';
import 'package:http/http.dart' as http;
import 'http.dart';

/// Invoke your deployed Edge Functions without writing a raw request. Sets the
/// `apikey`, attaches the signed-in user's token, JSON-encodes the body, and
/// returns an [IchibaseResponse].
class Functions {
  final String _baseUrl;
  final String _key; // project (anon) key — sent as the `apikey` header
  final http.Client _http;
  final String? _userToken; // end-user access token (Authorization: Bearer)
  Functions(this._baseUrl, this._key, this._http, [this._userToken]);

  /// Return a Functions client that calls AS a specific end user.
  Functions asUser(String accessToken) =>
      Functions(_baseUrl, _key, _http, accessToken);

  /// Invoke a function by name.
  ///
  /// ```dart
  /// final res = await ichi.functions.invoke('hello', body: {'name': 'world'});
  /// ```
  ///
  /// [body] is JSON-encoded unless it's already a `String`. [path] is appended
  /// after the function name (e.g. `/items/42`).
  Future<IchibaseResponse<dynamic>> invoke(
    String name, {
    String method = 'POST',
    Object? body,
    Map<String, String>? headers,
    String path = '',
  }) async {
    final url = Uri.parse(urlJoin(_baseUrl, '/functions/$name$path'));
    final h = <String, String>{'apikey': _key, ...?headers};
    if (_userToken != null) h['Authorization'] = 'Bearer $_userToken';

    String? bodyStr;
    if (body != null) {
      if (body is String) {
        bodyStr = body;
      } else {
        bodyStr = jsonEncode(body);
        h.putIfAbsent('Content-Type', () => 'application/json');
      }
    }

    final req = http.Request(method, url)..headers.addAll(h);
    if (bodyStr != null) req.body = bodyStr;
    final res = await _http.send(req).then(http.Response.fromStream);
    return toResponse<dynamic>(res, (b) => b);
  }
}

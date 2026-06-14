import 'package:http/http.dart' as http;
import 'http.dart';

/// File storage. Scope to a bucket with `ichi.storage.from('avatars')`.
class Storage {
  final String _baseUrl;
  final String _key;
  final http.Client _http;
  Storage(this._baseUrl, this._key, this._http);

  StorageBucket from(String bucket) =>
      StorageBucket(_baseUrl, _key, _http, bucket);
}

/// Operations within one bucket.
class StorageBucket {
  final String _baseUrl;
  final String _key;
  final http.Client _http;
  final String bucket;
  StorageBucket(this._baseUrl, this._key, this._http, this.bucket);

  Future<IchibaseResponse<Map<String, dynamic>>> _post(
      String op, Map<String, dynamic> body) async {
    final url = Uri.parse(urlJoin(_baseUrl, '/storage/$op'));
    final res = await sendRequest(_http, 'POST', url, bearer: _key, jsonBody: body);
    return toResponse<Map<String, dynamic>>(
        res, (b) => (b is Map ? b.cast<String, dynamic>() : <String, dynamic>{}));
  }

  /// Mint a short-lived signed URL to read a private file. Public-bucket files
  /// need no token — read them at `https://cdn.ichibase.net/<project>/<bucket>/<path>`.
  Future<IchibaseResponse<Map<String, dynamic>>> getUrl(
    String path, {
    int? ttlSeconds,
    String? userId,
  }) =>
      _post('get-url', {
        'bucket': bucket,
        'path': path,
        if (ttlSeconds != null) 'ttl_seconds': ttlSeconds,
        if (userId != null) 'user_id': userId,
      });

  /// Mint a presigned PUT URL. Upload the bytes to `data['url']` with an HTTP PUT.
  Future<IchibaseResponse<Map<String, dynamic>>> getPutUrl(
    String path, {
    required String contentType,
    required int contentLength,
  }) =>
      _post('get-put-url', {
        'bucket': bucket,
        'path': path,
        'content_type': contentType,
        'content_length': contentLength,
      });

  /// One-call upload: mints a PUT URL then uploads [bytes].
  Future<IchibaseResponse<Map<String, dynamic>>> upload(
    String path,
    List<int> bytes, {
    String contentType = 'application/octet-stream',
  }) async {
    final signed = await getPutUrl(path,
        contentType: contentType, contentLength: bytes.length);
    if (signed.error != null) return signed;
    final url = signed.data?['url'] as String?;
    if (url == null) {
      return IchibaseResponse<Map<String, dynamic>>(
          error: const IchibaseError(
              code: 'no_url', detail: 'no put url returned', status: 500));
    }
    final put = await _http.put(Uri.parse(url),
        headers: {'Content-Type': contentType}, body: bytes);
    if (put.statusCode >= 200 && put.statusCode < 300) {
      return IchibaseResponse(data: {'path': path});
    }
    return IchibaseResponse(
        error: IchibaseError(
            code: 'upload_failed', detail: 'HTTP ${put.statusCode}', status: put.statusCode));
  }

  Future<IchibaseResponse<Map<String, dynamic>>> delete(String path) =>
      _post('delete', {'bucket': bucket, 'path': path});

  Future<IchibaseResponse<Map<String, dynamic>>> head(String path) =>
      _post('head', {'bucket': bucket, 'path': path});

  Future<IchibaseResponse<Map<String, dynamic>>> list({String prefix = ''}) =>
      _post('list', {'bucket': bucket, 'prefix': prefix});

  Future<IchibaseResponse<Map<String, dynamic>>> move(String from, String to) =>
      _post('move', {'bucket': bucket, 'from': from, 'to': to});
}

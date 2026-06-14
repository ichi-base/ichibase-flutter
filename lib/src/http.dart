import 'dart:convert';
import 'package:http/http.dart' as http;

/// A structured error returned by the ichibase API. Mirrors the TypeScript
/// `IchibaseError` shape.
class IchibaseError {
  final String code;
  final String? detail;
  final int status;
  const IchibaseError({required this.code, this.detail, required this.status});

  @override
  String toString() =>
      'IchibaseError(code: $code, status: $status${detail != null ? ', detail: $detail' : ''})';
}

/// Every call resolves to one of these: `data` on success, `error` on failure.
/// Check [ok] or `error == null`.
class IchibaseResponse<T> {
  final T? data;
  final IchibaseError? error;
  const IchibaseResponse({this.data, this.error});

  bool get ok => error == null;
}

/// Decode an HTTP response body as JSON (or return the raw string / null).
dynamic decodeBody(String body) {
  if (body.isEmpty) return null;
  try {
    return jsonDecode(body);
  } catch (_) {
    return body;
  }
}

/// Turn an [http.Response] into an [IchibaseResponse], mapping the decoded body
/// through [map] on success.
IchibaseResponse<T> toResponse<T>(
  http.Response res,
  T Function(dynamic body) map,
) {
  final body = decodeBody(res.body);
  if (res.statusCode >= 200 && res.statusCode < 300) {
    return IchibaseResponse<T>(data: map(body));
  }
  String? code;
  String? detail;
  if (body is Map) {
    code = body['code'] as String?;
    detail = (body['detail'] ?? body['message']) as String?;
  }
  return IchibaseResponse<T>(
    error: IchibaseError(
      code: code ?? 'http_${res.statusCode}',
      detail: detail ?? 'HTTP ${res.statusCode}',
      status: res.statusCode,
    ),
  );
}

/// Join a base URL and a path, collapsing the slash between them.
String urlJoin(String base, String path) {
  final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  final p = path.startsWith('/') ? path : '/$path';
  return '$b$p';
}

/// Shared low-level request used by every module. [bearer] becomes the
/// `Authorization: Bearer` header; [extraHeaders] is merged last.
Future<http.Response> sendRequest(
  http.Client client,
  String method,
  Uri url, {
  String? bearer,
  Object? jsonBody,
  Map<String, String>? extraHeaders,
}) {
  final headers = <String, String>{};
  if (bearer != null) headers['Authorization'] = 'Bearer $bearer';
  if (jsonBody != null) headers['Content-Type'] = 'application/json';
  if (extraHeaders != null) headers.addAll(extraHeaders);
  final req = http.Request(method, url);
  req.headers.addAll(headers);
  if (jsonBody != null) req.body = jsonEncode(jsonBody);
  return client.send(req).then(http.Response.fromStream);
}

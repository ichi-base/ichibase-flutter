import 'dart:async';
import 'dart:io';

import 'session_storage.dart';

/// Durable session store for IO platforms (Flutter mobile/desktop, Dart server,
/// CLI): a JSON file under the user's home directory, falling back to the system
/// temp dir. No plugin required — uses only `dart:io`.
///
/// On most platforms `HOME`/`USERPROFILE` points at a durable location (incl.
/// the iOS app sandbox). On the rare platform where it doesn't, persistence is
/// best-effort; pass a custom [SessionStore] (e.g. backed by
/// `flutter_secure_storage`) to `Ichibase.initialize`/`createClient` if you need
/// a hard guarantee.
SessionStore defaultSessionStore() => _FileSessionStore();

class _FileSessionStore implements SessionStore {
  File? _file(String key) {
    try {
      final env = Platform.environment;
      final home = env['HOME'] ?? env['USERPROFILE'];
      final base =
          (home != null && home.isNotEmpty) ? home : Directory.systemTemp.path;
      final sep = Platform.pathSeparator;
      final dir = Directory('$base$sep.ichibase');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
      return File('${dir.path}$sep$safe.json');
    } catch (_) {
      return null;
    }
  }

  @override
  FutureOr<String?> getItem(String key) {
    try {
      final f = _file(key);
      return (f != null && f.existsSync()) ? f.readAsStringSync() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  FutureOr<void> setItem(String key, String value) {
    try {
      _file(key)?.writeAsStringSync(value);
    } catch (_) {
      // persistence is best-effort
    }
  }

  @override
  FutureOr<void> removeItem(String key) {
    try {
      final f = _file(key);
      if (f != null && f.existsSync()) f.deleteSync();
    } catch (_) {
      // best-effort
    }
  }
}

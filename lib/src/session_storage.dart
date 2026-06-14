import 'dart:async';

/// Pluggable persistence for the auth session. The SDK keeps the session in
/// memory (so token reads are synchronous) and mirrors it here so it survives a
/// restart. Flutter apps pass an adapter backed by `shared_preferences` or
/// `flutter_secure_storage`; pure-Dart/tests get [MemorySessionStore].
abstract class SessionStore {
  FutureOr<String?> getItem(String key);
  FutureOr<void> setItem(String key, String value);
  FutureOr<void> removeItem(String key);
}

/// In-memory adapter (default) — the session is lost when the process ends.
class MemorySessionStore implements SessionStore {
  final Map<String, String> _m = {};

  @override
  String? getItem(String key) => _m[key];

  @override
  void setItem(String key, String value) => _m[key] = value;

  @override
  void removeItem(String key) => _m.remove(key);
}

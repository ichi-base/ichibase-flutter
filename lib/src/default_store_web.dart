import 'dart:async';

import 'package:web/web.dart' as web;

import 'session_storage.dart';

/// Browser session store backed by `window.localStorage`, so a signed-in
/// session survives a page reload with zero setup.
SessionStore defaultSessionStore() => _WebSessionStore();

class _WebSessionStore implements SessionStore {
  @override
  FutureOr<String?> getItem(String key) {
    try {
      return web.window.localStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }

  @override
  FutureOr<void> setItem(String key, String value) {
    try {
      web.window.localStorage.setItem(key, value);
    } catch (_) {
      // best-effort (e.g. storage disabled / private mode)
    }
  }

  @override
  FutureOr<void> removeItem(String key) {
    try {
      web.window.localStorage.removeItem(key);
    } catch (_) {
      // best-effort
    }
  }
}

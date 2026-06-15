import 'session_storage.dart';

/// Fallback when neither `dart:io` nor the web platform is available:
/// in-memory only (the session is lost when the process ends).
SessionStore defaultSessionStore() => MemorySessionStore();

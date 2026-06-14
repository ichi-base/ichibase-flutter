/// The official client-side SDK for [ichibase](https://ichibase.com) — Postgres,
/// MongoDB, Auth, and Realtime from Flutter, Dart server, or CLI.
///
/// Anon key only:
///
/// ```dart
/// import 'package:ichibase/ichibase.dart';
///
/// final ichi = Ichibase.createClient(
///   'https://<project>.ichibase.net',
///   'ich_pub_…',
/// );
/// final res = await ichi.from('posts').select('*');
/// ```
library;

export 'src/client.dart' show Ichibase, createClient;
export 'src/http.dart' show IchibaseError, IchibaseResponse;
export 'src/auth.dart' show Auth, Session, AuthEvent;
export 'src/postgrest.dart' show Postgrest, PostgrestQueryBuilder;
export 'src/mongo.dart' show Mongo, MongoCollection;
export 'src/functions.dart' show Functions;
export 'src/realtime.dart' show RealtimeClient, Subscription;
export 'src/session_storage.dart' show SessionStore, MemorySessionStore;

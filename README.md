# ichibase (Dart / Flutter)

The official **client-side** SDK for [ichibase](https://ichibase.com) — Postgres,
MongoDB, Auth, Storage, and Realtime from a single client. Works in **Flutter**
(iOS, Android, web, desktop), Dart servers, and CLIs. **Anon key only.**

> Mirrors the TypeScript [`@ichibase/client`](https://github.com/AliKales/ichibase-client).
> Building a backend/admin tool with the **service** key? Use the server SDKs —
> this package refuses `ich_admin_` keys by design.

## Install

```yaml
# pubspec.yaml
dependencies:
  ichibase: ^0.1.0
```

```dart
import 'package:ichibase/ichibase.dart';

final ichi = Ichibase.createClient(
  'https://<project>.ichibase.net',
  'ich_pub_…', // publishable (anon) key — safe to ship in your app
);
```

## Database (PostgREST)

Awaiting a query runs it. Every call returns an `IchibaseResponse` with `data`
and `error` (check `res.ok`).

```dart
// Read with filters / ordering / pagination
final res = await ichi
    .from('posts')
    .select('id, title, author')
    .eq('published', true)
    .order('created_at', ascending: false)
    .limit(20);
print(res.data); // List of rows

// Insert / update / delete
await ichi.from('posts').insert({'title': 'Hello'});
await ichi.from('posts').update({'title': 'Edited'}).eq('id', 1);
await ichi.from('posts').delete().eq('id', 1);

// One row, or a total count
final one = await ichi.from('posts').select('*').eq('id', 1).single();
final counted = await ichi.from('posts').select('*').count(); // {rows, count}

// RPC (SQL function)
final total = await ichi.rpc('count_posts', args: {'author': userId});
```

## Auth + per-user access

After login, data calls use the user's access token, so your RLS policies and
realtime rules see them.

```dart
await ichi.auth.signup(email: email, password: password);
final login = await ichi.auth.login(email: email, password: password);

await ichi.from('posts').insert({'title': 'mine'}); // runs as the user

final user = await ichi.auth.getUser();
await ichi.auth.logout();

ichi.onAuthStateChange.listen((s) {
  // s.event == AuthEvent.signedIn | signedOut | tokenRefreshed
});
```

### Persisting the session

The session lives in memory by default. Plug in a `SessionStore` to keep users
logged in across restarts (back it with `shared_preferences` or
`flutter_secure_storage`), then hydrate once at startup:

```dart
final ichi = Ichibase.createClient(url, anonKey, store: MySecureStore());
await ichi.auth /* not needed */;
await ichi.loadSession();
```

## Mongo

```dart
await ichi.mongo.collection('orders').insertOne({'total': 42});
final docs = await ichi.mongo.collection('orders').find({'total': {'\$gt': 10}});
```

## Storage

```dart
// Signed read URL for a private file
final signed = await ichi.storage.from('invoices').getUrl('/2026/march.pdf', ttlSeconds: 300);

// Upload
await ichi.storage.from('avatars').upload('/me.png', bytes, contentType: 'image/png');
// Public files: https://cdn.ichibase.net/<project>/public/<path>
```

## Realtime

```dart
final sub = ichi.realtime.subscribe(
  kind: 'postgres',
  table: 'messages',
  events: ['INSERT'],
  onMessage: (msg) => print('${msg['event']} ${msg['record']}'),
);

// Broadcast + presence
final room = ichi.realtime.subscribe(
  kind: 'broadcast',
  channel: 'room:42',
  presence: true,
  onMessage: (msg) => print(msg),
);
room.send('chat', {'text': 'hi'});
room.track({'typing': true});

sub.unsubscribe();
```

## Security

The anon key is **publishable** — access is gated by your **Row-Level Security**
policies (Postgres) and **collection policies** (Mongo), not by hiding the key.
Enable RLS on everything you expose. Never put an `ich_admin_` (service) key in
an app. Full docs: <https://ichibase.com/docs>.

## License

MIT

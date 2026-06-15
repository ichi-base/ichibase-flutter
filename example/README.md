# ichibase Flutter example

A full-featured Flutter app exercising the [`ichibase`](https://pub.dev) Dart
SDK end-to-end: **Auth, Postgres, MongoDB, Realtime, Storage (via Edge
Functions), and Pro features.**

It depends on the SDK by path (`ichibase: { path: ../ }`), so it always builds
against the SDK in this repo.

## What it shows

| Screen          | SDK surface                                                                 |
| --------------- | --------------------------------------------------------------------------- |
| **Config**      | `Ichibase.initialize(url, anonKey)` (global singleton); anon-key validation  |
| **Auth**        | `signup` / `login` / `logout` / `refresh` / `getUser`, email verification (OTP + token), password reset, `onAuthStateChange`, OAuth notes |
| **Database**    | `from('posts').select/insert/update/delete`, filters, `order`, `limit`, `rpc()`, RLS notes |
| **MongoDB**     | `mongo.collection('orders')` `insertOne` / `find` / `updateOne` / `deleteOne` / `count` / `aggregate`, policy notes |
| **Realtime**    | `realtime.subscribe(kind: 'postgres' \| 'mongo', …)`, live event feed, clean `unsubscribe` |
| **Storage**     | public CDN reads, signed private reads, signed uploads — all via the `files` Edge Function |
| **Edge Functions** | generic `functions.invoke(name, body)`                                   |
| **Pro features**   | search (Typesense), Redis, scheduled functions, dual DB, dedicated VPS  |

Persistence is automatic: `Ichibase.initialize()` is called once in `main()`
and the SDK keeps the session across restarts (a file on mobile/desktop,
`localStorage` on web). Every screen reads the client via `Ichibase.instance` —
no `BuildContext`, no prop-drilling. App-level config (slug / anon key / DB
flavor) is the only thing the example stores itself, via `SharedPreferences`.

## Run it

This example ships without platform folders to keep the repo small. Generate
them once, then run:

```bash
cd example
flutter create .      # adds android/ ios/ web/ etc. for your toolchain
flutter pub get
flutter run           # pick a device
```

On first launch, enter:

- **Project slug** — the `<slug>` in `https://<slug>.ichibase.net`.
- **Anon key** — your publishable `ich_pub_…` key (the SDK rejects
  `ich_admin_` service keys).
- **Database flavor** — Postgres, Mongo, or Both (Both requires a Pro plan).

Use **Change project** in the app bar menu to reconfigure.

### Suggested backend setup

- **Database screen** — create the table:

  ```sql
  create table posts (
    id bigint generated always as identity primary key,
    title text not null,
    published boolean not null default false
  );
  ```

  Add an RLS policy (or allow anon) so the screen can read/write. Enable the
  table for **realtime** in the dashboard to see live events.

- **MongoDB screen** — add a collection policy for `orders` (a fresh free Mongo
  project denies access until you do).

- **Storage screen** — deploy the Edge Functions in
  [`edge_functions/`](edge_functions/README.md). The `files` function signs
  read/upload URLs with the service key server-side.

## Edge Functions

See [`edge_functions/README.md`](edge_functions/README.md). The client never
holds the service key or the Typesense key — those live in the functions.

## Verify (no device needed)

```bash
cd example
flutter pub get
flutter analyze       # must be clean
```

---

## Pure-Dart quickstart

You don't need Flutter to use the SDK — here's the same flow from any Dart
program (server, CLI, test):

```dart
import 'package:ichibase/ichibase.dart';

Future<void> main() async {
  final ichi = Ichibase.createClient(
    'https://your-project.ichibase.net',
    'ich_pub_your_anon_key', // publishable (anon) key — safe to ship
  );

  // ── Database (PostgREST) ──────────────────────────────────────────
  final posts =
      await ichi.from('posts').select('*').eq('published', true).limit(20);
  if (posts.ok) {
    print('posts: ${posts.data}');
  } else {
    print('error: ${posts.error}');
  }

  await ichi.from('posts').insert({'title': 'Hello from Dart'});

  // ── Auth ───────────────────────────────────────────────────────────
  final login = await ichi.auth.login(email: 'a@b.com', password: 'secret');
  if (login.ok) {
    // Now runs as the user — RLS sees auth.uid().
    await ichi.from('posts').insert({'title': 'mine'});
    final me = await ichi.auth.getUser();
    print('signed in as: $me');
  }

  // ── Mongo ──────────────────────────────────────────────────────────
  await ichi.mongo.collection('orders').insertOne({'total': 42});
  final orders =
      await ichi.mongo.collection('orders').find({'total': {r'$gt': 10}});
  print('orders: ${orders.data}');

  // ── Realtime ───────────────────────────────────────────────────────
  final sub = ichi.realtime.subscribe(
    kind: 'postgres',
    table: 'messages',
    events: ['INSERT'],
    onMessage: (msg) => print('new message: ${msg['record']}'),
  );
  await Future<void>.delayed(const Duration(seconds: 5));
  sub.unsubscribe();

  ichi.dispose();
}
```

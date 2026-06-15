## 0.2.0

- Automatic session persistence — no `store` needed. The SDK now picks a durable
  default per platform (a file on mobile/desktop/server via `dart:io`,
  `localStorage` on web). Pass `store:` only to override.
- `Ichibase.initialize(url, anonKey)` + `Ichibase.instance` — initialize once at
  startup, then use the client anywhere with no `BuildContext` (Supabase-style).
  `createClient(...)` still available for local instances.
- Example app updated to the singleton + a full feature tour.

## 0.1.0

- Initial release.
- Unified, anon-key-only client: `Ichibase.createClient(url, anonKey)`.
- Postgres query builder (`from().select()/insert()/update()/delete()`, filters,
  order/limit/range, single/maybeSingle/count) + `rpc()`.
- Auth with session management + pluggable persistence (`SessionStore`).
- Storage (signed read/put URLs, upload, list, move, delete).
- Mongo document API (full op set, `asUser`).
- Realtime over WebSocket (postgres/mongo changes, broadcast, presence) with
  auto-reconnect.

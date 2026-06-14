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

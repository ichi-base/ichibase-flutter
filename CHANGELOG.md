## 0.4.0

- 2-step verification on password login: `auth.verifyTwoFactor(email:, code:)` and
  `auth.verifyTwoFactorMagic(token)`. **`login` now returns
  `IchibaseResponse<LoginResult>`** (was `<Session>`): `result.session` on a normal
  login, or `result.twofaRequired == true` + `result.twofaMethods` when the project
  requires 2-step verification (a factor was emailed). Custom SMTP required.
  **Breaking** vs 0.3.0 — update `login` call sites to read `result.session`.
- Code-based password reset: `auth.confirmPasswordResetOtp(email:, code:, newPassword:)`.
- Example: handle the 2-step verification challenge on login; the Mongo screen
  reads documents from the `docs` key in find responses.

## 0.3.0

- Passwordless sign-in: `auth.signInWithOtp(email:)`, `auth.verifyOtp(email:, code:)`,
  and `auth.verifyMagicLink(token)`. Additive to email + password; the project must
  enable it (custom SMTP required). The two verify calls store the session and emit
  `AuthEvent.signedIn`, exactly like `login`.

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

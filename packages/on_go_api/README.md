# on_go_api

The On Go API client, shared by both front ends: the mobile app (Client and
Mechanic) and the admin console (Admin and Moderator). It speaks HTTP for
requests and uses one WebSocket for live events. Each piece implements the same
`package:on_go_shared` interface the local services implement, so screens don't
know which one they hold.

The contract is the deployed API's OpenAPI document (`/docs/json`) together
with *On Go API — Integration Guide for the Front Ends*. Nothing here adds a
route, a field or a behaviour that those two don't define.

## Configuration

One base URL, set at build time. No service writes its own.

| `--dart-define` | Default | Meaning |
|---|---|---|
| `ONGO_API_BASE_URL` | staging (`https://ongo-api-618821603306.asia-southeast1.run.app`) | The server. Production is this flag, not an edit. |
| `ONGO_BACKEND` | `api` | `local` keeps every contract on the device (offline demos, UI work). |
| `ONGO_API_VERIFICATION` | `false` | Use the API for verification requests (Step 5). |
| `ONGO_API_MODERATORS` | `false` | Use the API for moderators and the audit log (Step 6, console). |

Requests time out after 20 s. Staging scales to zero, so the first answer after
a quiet spell takes 2–5 s.

## What is connected

| Route | Dart | Status |
|---|---|---|
| `POST /auth/sign-in`, `/register`, `/refresh`, `/sign-out` | `HttpAuthApi`, `ApiSession` | live |
| `GET /auth/me`, `POST /auth/password` | `HttpAuthApi` | live |
| `POST /auth/password/reset`, `/reset/confirm` | `HttpAuthApi` | live, but staging does not deliver codes yet (Step 8) |
| `GET/PUT /platform/points-policy` + `points_policy.updated` | `HttpPointsPolicyApi` | live |
| `GET /platform/appearance` | `HttpPlatformAppearanceApi.fetch/watch` | live |
| `PUT/DELETE /platform/appearance` | `HttpPlatformAppearanceApi.publish/clearBackground` | answers `501` (Step 7) |
| `POST /payments` | `HttpPlatformRevenueApi.reportCompletedPayment` | live |
| `GET /revenue/summary` | `HttpPlatformRevenueApi.fetchSummary/watchSummary` | live (polled; no event) |
| `/verification-requests/*`, `/moderation/activity` | `HttpAccountVerificationApi` | answers `501` (Step 5), behind a flag |
| `/moderators/*`, `/audit-log` | `HttpModeratorDirectoryApi` | answers `501` (Step 6), behind a flag |
| `/api/v1/events` | `EventSocket` | live; planned events are subscribed to but not sent yet |

The jobs domain is not in the contract. Help requests, quotes, ETA, chat and
reviews stay in the mobile app's own stores. `POST /payments` is the only
job-related call.

## Sessions

`ApiSession` holds the tokens:

- **Access token:** in memory only, sent as `Authorization: Bearer …`, never in
  a URL.
- **Refresh token:**
  - On mobile it lives in a `RefreshTokenStore`; the app backs this with the
    Keychain / Keystore.
  - On the console there is no store. The browser keeps it as the httpOnly
    `ongo_refresh` cookie, and requests go out with credentials.
- **Refresh:**
  - Serialized: however many requests find their token expired together, one
    refresh runs.
  - The new refresh token is stored before it's used.
  - `ApiClient` refreshes once on `401 token_expired` and retries the request
    once.
  - `token_invalid`, `account_inactive`, or a refused refresh ends the session;
    the apps return to Sign In and say why.

## Errors

Every failure is an `ApiException`:

- `code` is the server's `error.code`, which logic switches on.
- `message` is safe to show.
- `details` / `fieldErrors` hold the per-field errors from `validation_failed`.
- `requestId` is logged by each app's logger.

`kind` follows the guide's mapping: 401 → unauthenticated; 403 → forbidden;
400/409/413/423/429 → rejected; 501 → unsupported; 500/503 → unknown; no answer
→ unreachable.

A `501 not_implemented` is an unfinished feature, not a crash. Check
`ApiException.isNotImplemented`.

## Live events

`EventSocket` is one connection per signed-in app:

- **Handshake:** the access token goes in the first frame; `ready` means it's
  authenticated.
- **Dispatch:** events are routed by name.
- **Reconnect:** every close is followed by a reconnect with backoff (1 s, 2 s,
  4 s … 30 s).
- **Expired token:** `token_expired` refreshes, then reconnects.
- **Any other auth error:** the session ends.

`RemoteValue` builds each `watch*`:

- It fetches once and applies matching events.
- It re-fetches on every reconnect, because events aren't queued while
  disconnected.
- It polls where there is no event (the revenue summary).

## Checking a live server

From this package's folder (`Backend/on_go_backend/packages/on_go_api`).
Read-only: no credentials, no accounts, nothing written.

```bash
dart run tool/smoke.dart
```

## Tests

The tests run on `flutter_test` and stay with the mobile app. From `on_go/`:

```bash
flutter test test/api
```

These use a scripted HTTP server and socket, so they need no network.

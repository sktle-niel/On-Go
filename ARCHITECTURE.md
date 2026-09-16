# On Go — architecture

On Go ships as **two front ends** that will meet at **one backend**. They live
in **two repositories**: this one, and `on_go_console` beside it.

```
                        THIS REPOSITORY (On-Go)
   ┌───────────────────────────────┐  ┌───────────────────────────────┐
   │   packages/on_go_shared       │  │    packages/on_go_design      │
   │  models + API contracts       │  │  palettes, theme registry,    │
   │  (pure Dart — no Flutter,     │  │  tokens, ThemeController      │
   │   no HTTP, no database)       │  │  (Flutter)                    │
   └───────────────────────────────┘  └───────────────────────────────┘
          ▲                ▲                 ▲              ▲
          │                └────────┬────────┘              │
          │                         │                       │
   ┌──────┴────────────────────┐   ┌┴───────────────────────┴─────┐
   │  /lib  — MOBILE APP       │   │  On-Go-Console — CONSOLE     │
   │  Flutter · Android + iOS  │   │  Flutter web                 │
   │                           │   │                              │
   │  • Client                 │   │  • Admin                     │
   │  • Mechanic               │   │  • Moderator                 │
   │                           │   │                              │
   │  MobileBackend.instance   │   │  ConsoleBackend.instance     │
   └───────────────┬───────────┘   └──────────────┬───────────────┘
      this repo    │                              │  sibling repo
                   │        ┌──────────────┐      │
                   └───────►│  On Go API   │◄─────┘
                            │  TypeScript  │
                            │  on staging  │
                            └──────────────┘
```

Two shared packages, for two different reasons. `on_go_shared` is what the apps
**say to each other**, and stays pure Dart so the backend can depend on it too.
`on_go_design` is what they **look like**, and necessarily depends on Flutter.

Nothing in `/lib` imports anything from the console, and nothing in the console
imports anything from `/lib`. That is the whole point: they are separate
applications, deployed separately, to different people — which is why they are
now separate repositories too.

### Where the console lives

The console is its own repository, `On-Go-Console`. It depends on the three
shared packages in this repository by **relative path**, so the two checkouts
have to be siblings:

```
Documents/
  On-Go/          this repository — the mobile app, and packages/
    packages/on_go_design   the design system, used by both front ends
    packages/on_go_shared   the API contract (pure Dart), used by both apps
    packages/on_go_api      the API client (pure Dart), used by both apps
  On-Go-Console/  the Admin + Moderator console
    packages/on_go_console_backend
                          the console's backend seam (ConsoleBackend, local services, ConsoleApi)
```

The On Go API itself is a third repository, in TypeScript, and is not checked
out here. It is deployed on staging; its OpenAPI document is the contract these
packages mirror.

An edit to `packages/on_go_design` or `on_go_shared` is picked up by
the console immediately, with no publish step — the same as when it was one
repository. What changed is only that the console's own history, issues and
deploys are its own.

---

## The parts

| Path                          | What it is               | Who uses it            |
| ----------------------------- | ------------------------ | ---------------------- |
| `/lib`                        | Flutter mobile app       | Clients, Mechanics     |
| `../On-Go-Console` (own repo) | Flutter **web** console  | Admins, Moderators     |
| `/packages/on_go_shared`      | Pure-Dart API contract   | Both, and the backend  |
| `/packages/on_go_api`         | Pure-Dart API client     | Both front ends        |
| `/packages/on_go_design`      | The shared design system | Both front ends        |
| The On Go API (own repo)      | The deployed REST API    | Both front ends        |

### `/lib` — the mobile app

Client and Mechanic, unchanged. Sign In still accepts `client`, `demo-client`,
`mechanic` and `demo-mechanic`, plus any account registered in-session.

Typing `admin` or `moderator` now reports that those accounts sign in on the
console website — the app has no admin or moderator UI, and it never gets one
back.

### `on_go_console` — the console (separate repository)

Admin and Moderator, rebuilt for a browser rather than ported screen-for-screen:

- **URLs.** `/admin/moderators`, `/moderator/queue`, and so on. Bookmarkable,
  linkable, and the browser's Back button works. Routing enforces that an admin
  URL is not a moderator's to open.
- **A navigation rail** on a tablet or a desktop, not a bottom bar. It pins
  open on a wide window and collapses to icons on a narrower one. On a *phone*
  it becomes the app's own bottom bar and drawer — see the design package
  below.
- **Tables** where the mobile app had stacks of cards, because an admin scans
  and compares across a roster. A phone gets the cards back.
- **Hover** interactions on the charts, because there is a mouse.
- **The app's own theme system**, from `packages/on_go_design` — see below.

Run it, from the sibling checkout:

```bash
cd ../On-Go-Console && flutter run -d chrome
```

Sign in as `admin` to create the first moderator; moderators then sign in with
the email and password the admin set.

### `/packages/on_go_shared` — the contract

What the two applications say to each other. Pure Dart on purpose — no Flutter,
no `dart:io`, no HTTP client — so the backend can depend on it too.

```
lib/src/models/   DTOs, each with toJson/fromJson
lib/src/api/      abstract interfaces, one per capability
                  + api_endpoints.dart — the agreed REST routes
```

Every enum carries an explicit `wireName`, so renaming a Dart identifier can
never silently change what crosses the network.

### `/packages/on_go_design` — the design system

What the two applications look like. One theme system, not two that resemble
each other:

```
lib/src/app_palette.dart      AppPalette, AppThemeOption, AppThemes — the registry
lib/src/design_tokens.dart    AppRadii, AppBorders, AppElevation, AppShadows
lib/src/theme_controller.dart ThemeController — selection, Dark Mode,
                              Dynamic Themes, Warm Filter, persistence
lib/src/app_colors.dart       AppColors, AppDurations, AppWarmFilter
lib/src/app_chrome.dart       OnGoAppBar, NotificationBell
lib/src/on_go_bottom_nav.dart OnGoBottomNav, OnGoNavItem
```

The last two are widgets rather than tokens, and they are here for the same
reason: on a phone the console shows the *same* app bar and the *same* floating
pill navigation bar the Client and Mechanic shells do. Sharing the widget is
what makes "matches the app exactly" a fact about the code rather than a
promise about pixels.

Both front ends offer the **same six themes** — Default, Dark, Calm Blue, Calm
Blue Dark, Ember Light, Ember — and the same three controls, because both drive
the same `ThemeController`. Adding a theme means appending one `AppThemeOption`
to `AppThemes.all`; both pickers build themselves from that list, so neither
needs touching.

What each app still owns is its **own `ThemeData`**, built from those palettes:

| | Mobile (`lib/theme/app_theme.dart`) | Console (`../On-Go-Console/lib/src/theme/console_theme.dart`) |
| --- | --- | --- |
| Colours | `AppPalette` | the same `AppPalette` |
| Corners | `AppRadii` | the same `AppRadii` |
| Buttons | Pills, full width, 48pt tall | Pills, sized to their label |
| Type | Phone scale | A little tighter |
| States | Tap | Tap **and** hover |

The console keeps its own colour *vocabulary* — `sidebar`, `canvas`, `border` —
because that is how a desktop tool is built, but every one of those names
resolves to a palette role rather than a value of its own. `ConsoleColors.brand`
**is** `AppPalette.primary`; the rail **is** the colour the app paints its app
bars. There is no second set of numbers to drift.

The one role the console adds is `surfaceMuted`, a recessed surface inside a
card. The app has no such thing — nothing on a phone nests two surfaces deep —
so it is mixed from the palette at read time rather than added to all six
palettes for one console detail.

---

## What crosses between the two apps

Five things, and they are the entire integration surface:

| # | Direction         | What                                       | Contract                  |
| - | ----------------- | ------------------------------------------ | ------------------------- |
| 1 | mobile → console  | A mechanic finishes registration           | `AccountVerificationApi.submit` |
| 2 | console → mobile  | A moderator approves / rejects / escalates | `AccountVerificationApi.decide` |
| 3 | mobile → console  | A client payment completed                 | `PlatformRevenueApi.reportCompletedPayment` |
| 4 | console → mobile  | The Sign In / Welcome background photo     | `PlatformAppearanceApi.publishBackground` |
| 5 | both              | Signing in                                 | `AuthApi.signIn`          |

**(1) and (2) are one round trip and the most important pair.** A mechanic
registers on a phone, waits, and a moderator working in a browser decides.
`MechanicAccountStore` files the request and then *watches* it:

```dart
_requestWatch = MobileBackend.instance.verification
    .watchRequest(filed.id)
    .listen(_onRequestChanged);
```

Everything downstream — whether job actions are unlocked, the status banner,
the "Account approved" notification — reads that one record, so none of it
cares whether the verdict arrived from this device or over a socket.

**(5) is enforced, not merely conventional.** `SignInRequest` carries an
`AppSurface`. A console role signing in from the mobile app is refused with
`SignInFailure.wrongSurface`, which is why the app can tell someone to use the
website instead of claiming their password is wrong.

---

## The seam

Each application has exactly one place where a call leaves it:

- Mobile: `lib/services/backend/mobile_backend.dart`
- Console: `../On-Go-Console/packages/on_go_console_backend/lib/console_backend.dart`

Both are a small holder of contract implementations plus a `configure()`. The
HTTP implementations live in `packages/on_go_api`, which both apps share. Each
app installs them at startup: `MobileApi` on mobile, `ConsoleApi` on the console.

```dart
// lib/services/api/mobile_api.dart (called from main)
final api = OnGoApi(
  environment: ApiEnvironment.fromDefines(),   // staging unless ONGO_API_BASE_URL
  surface: AppSurface.mobile,
  refreshTokens: SecureRefreshTokenStore(),     // Keychain / Keystore
);
MobileBackend.configure(
  usesApi: true,
  auth: api.auth,
  pointsPolicy: api.pointsPolicy,
  appearance: api.appearance,
  revenue: api.revenue,
);
```

That is the whole integration. **No screen changes**, because every call site
already awaits a `Future` or listens to a `Stream`. The interfaces were
asynchronous from the start precisely so that latency and failure were never
retrofitted. The only screens that changed are the ones for things the server
now owns: passwords, registration, resets and sessions. They branch on
`MobileBackend.instance.usesApi`.

### What backs them today

| Contract | Mobile | Console |
|---|---|---|
| `AuthApi` | API | API (cookie session) |
| `PointsPolicyApi` | API (read + live) | API (read, update, live) |
| `PlatformRevenueApi` | API (`POST /payments`) | API (`GET /revenue/summary`) |
| `PlatformAppearanceApi` | API (read) | API (publish, remove, live) |
| `AccountVerificationApi` | API behind `ONGO_API_VERIFICATION` | API behind `ONGO_API_VERIFICATION` |
| `ModeratorDirectoryApi` | — | API behind `ONGO_API_MODERATORS` |
| `UrgencyPolicyApi` (additional charge, completion time) | local defaults (not in the API contract) | local, saved in the browser (not in the API contract) |
| `RankPolicyApi` (rank requirements, points multipliers) | local defaults (not in the API contract) | local, saved in the browser (not in the API contract) |
| `LeaderboardConfigApi` (public switch, seasons, scoring, seasonal multipliers, cap) | local defaults — disabled, no seasons (not in the API contract) | local, saved in the browser, every change audited (not in the API contract) |
| `PerformanceReviewApi` (standings, score breakdowns, evaluations, point transactions, flags, adjustments) | — (phones calculate their own with `LeaderboardEngine`) | local and empty: phone records do not reach the console until the jobs domain is on the API |
| `LocationApi` | local — the API serves these routes, the app is not on them yet | — |
| `ServiceRequestApi`, `PointsWalletApi`, `MechanicReviewApi`, chat | local stores — the API serves them, the app is not on them yet | — |

Every API-backed row switches to local with `--dart-define=ONGO_BACKEND=local`.
The two flagged rows are served and their HTTP implementations are written; the
flags exist so a build can be pinned to the in-browser behaviour.

The rows that say "the app is not on them yet" are the real gap: the server owns
those domains, the phone still owns its own copy of them, and the two have to be
reconciled one call site at a time.

The local implementations live in `lib/services/backend/` here, and in
`packages/on_go_console_backend/lib/local/` on the console. They are
**not a fake backend**: each one does only the half of its interface that its
own surface is entitled to, and refuses the rest.

- The mobile app's `LocalVerificationService.decide()` **throws** rather than
  approving. A phone approving its own owner's account would undo the entire
  reason for the split.
- The console's `LocalRevenueService.reportCompletedPayment()` **throws**. The
  console cannot book a peso; only a completed client payment does that.
- The mobile app's `LocalAppearanceService.publishBackground()` **throws**.
  Branding is set in the console.

### Honest consequences

The two apps share accounts, the points rules, the revenue ledger, the
verification queue, the moderator directory and the Sign In background. Nothing
the contract covers answers `501` any more. What is left is narrower, and worth
stating plainly:

- **The jobs domain.** The server owns requests, quotes, accept, the status
  machine, payment, points, cancel, expiry, reviews and chat, and each phone
  still owns its own copy of all of it. Nothing crosses between two devices yet.
  This is the one gap that matters.
- **Payment still settles on the device.** The app takes payment by QR and
  reports it to `POST /payments`, which the server books through a checked
  compatibility window. Moving the app to `POST /service-requests/:id/pay`
  closes that window and makes the server the one that settles a job.
- **Location.** The API keeps a last-known fix per account and answers
  "which open jobs are near this mechanic", and the app still reports into its
  own store. There is also no location event, so a client following a mechanic
  would have to poll.
- **Password reset codes.** The reset screens call the real routes, but staging
  has no mail provider configured, so the code is logged rather than delivered
  and the flow cannot finish there.
- **Mechanic documents.** Registration files only the document names; the
  route that attaches the files themselves to a verification request is not
  wired up.
- **Nothing reaches a closed app.** Every live update arrives on the event
  socket, so it needs the app open. There is no push provider.

---

## Adding an operation

Keep the two apps from drifting by going in this order:

1. Add the DTO in `packages/on_go_shared/lib/src/models/`, with
   `toJson`/`fromJson`.
2. Add the method to the right interface in `.../lib/src/api/`, returning a
   `Future` or `Stream`.
3. Add its route to `ApiEndpoints`.
4. Implement it locally on **each** side — including the refusal, where a
   surface should not be allowed to do it.
5. Call it through `MobileBackend.instance` / `ConsoleBackend.instance`. Never
   reach around them.

---

## The backend

The On Go API is deployed on staging (Google Cloud Run and Neon PostgreSQL, in
Singapore). Its contract is the OpenAPI document at `/docs/json` together with
the integration guide. `ApiEndpoints` mirrors those routes; add nothing to it
that the contract lacks. The location routes are the one marked exception: they
are this app's proposal, and are served. The API is its own TypeScript
repository; it is not checked out beside this one.

To see what a server answers without credentials, run
`dart run tool/smoke.dart` from `packages/on_go_api` (read-only).

Two rules the server owns that the clients cannot be trusted with:

- **Permissions** are re-checked server-side. `ModeratorPermissions` today only
  hides buttons and lets a local service refuse; a permission that only hides a
  button is not a permission.
- **The actor** on a decision comes from the caller's token, not from
  `ModerationDecision.actorName` in the request body. That field exists so the
  pre-backend implementations record the same information.

# On Go — architecture

On Go ships as **two front ends** that will meet at **one backend**. They live
in **two repositories**: this one, and `on_go_console` beside it.

```
                        THIS REPOSITORY (on_go)
   ┌───────────────────────────────┐  ┌───────────────────────────────┐
   │    packages/on_go_shared      │  │    packages/on_go_design      │
   │  models + API contracts       │  │  palettes, theme registry,    │
   │  (pure Dart — no Flutter,     │  │  tokens, ThemeController      │
   │   no HTTP, no database)       │  │  (Flutter)                    │
   └───────────────────────────────┘  └───────────────────────────────┘
          ▲                ▲                 ▲              ▲
          │                └────────┬────────┘              │
          │                         │                       │
   ┌──────┴────────────────────┐   ┌┴───────────────────────┴─────┐
   │  /lib  — MOBILE APP       │   │  on_go_console — CONSOLE     │
   │  Flutter · Android + iOS  │   │  Flutter web                 │
   │                           │   │                              │
   │  • Client                 │   │  • Admin                     │
   │  • Mechanic               │   │  • Moderator                 │
   │                           │   │                              │
   │  MobileBackend.instance   │   │  ConsoleBackend.instance     │
   └───────────────┬───────────┘   └──────────────┬───────────────┘
      this repo    │                              │  sibling repo
                   │        ┌──────────────┐      │
                   └───────►│   /server    │◄─────┘
                            │  NOT BUILT   │
                            │     YET      │
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

The console is its own repository, `on_go_console`. It depends on the two
shared packages in this repository by **relative path**, so the two checkouts
have to be siblings:

```
Flutter/
  on_go/          this repository — the mobile app, and packages/
  on_go_console/  the Admin + Moderator console
```

An edit to `packages/on_go_design` or `packages/on_go_shared` is picked up by
the console immediately, with no publish step — the same as when it was one
repository. What changed is only that the console's own history, issues and
deploys are its own.

---

## The parts

| Path                          | What it is               | Who uses it            |
| ----------------------------- | ------------------------ | ---------------------- |
| `/lib`                        | Flutter mobile app       | Clients, Mechanics     |
| `../on_go_console` (own repo) | Flutter **web** console  | Admins, Moderators     |
| `/packages/on_go_shared`      | Pure-Dart API contract   | Both, and the backend  |
| `/packages/on_go_design`      | The shared design system | Both front ends        |
| `/server`                     | Backend scaffold         | Nothing yet            |

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
cd ../on_go_console && flutter run -d chrome
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

| | Mobile (`lib/theme/app_theme.dart`) | Console (`on_go_console/lib/src/theme/console_theme.dart`) |
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
- Console: `on_go_console/lib/src/backend/console_backend.dart`

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
| `PlatformAppearanceApi` | API (read) | API; publish/remove answer 501 until Step 7 |
| `AccountVerificationApi` | local until Step 5 | local until Step 5 |
| `ModeratorDirectoryApi` | — | local until Step 6 |
| `LocationApi` | local (not in the API contract) | — |

The API-backed rows switch to local with `--dart-define=ONGO_BACKEND=local`.
The local rows switch to the API with `ONGO_API_VERIFICATION` /
`ONGO_API_MODERATORS` once their step is live. Their HTTP implementations are
already written against the contract.

The local implementations live under `backend/local/` on each side. They are
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

The two apps now share accounts, the points rules and the revenue ledger. They
do not yet share what the API still answers `501` for, and neither pretends
otherwise:

- **Verification (Step 5).** A mechanic's verification request is still filed
  on the phone that registered, so no moderator can reach it. A mechanic who
  signs in on a later launch has no request on the device, and the Jobs banner
  says the status isn't available rather than calling it Pending. The
  `demo-mechanic` shortcut (local build) still unlocks the mechanic flows for
  testing.
- **Moderators and the audit log (Step 6).** These stay in the console's browser.
- **The Sign In background (Step 7).** Publishing it from the console fails
  with the server's "not implemented" message. The mobile app paints whatever
  `GET /platform/appearance` returns.
- **Password reset codes (Step 8).** The reset screens call the real routes,
  but staging doesn't deliver the code yet.
- **The jobs domain (Step 10).** Requests, quotes, ETA, chat and reviews aren't
  in the contract, and stay in each phone's stores.

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
are this app's proposal. `/server` in this repository is only a partial
TypeScript scaffold and is not the deployed service.

To see what a server answers without credentials, run
`dart run tool/api/smoke.dart` (read-only).

Two rules the server owns that the clients cannot be trusted with:

- **Permissions** are re-checked server-side. `ModeratorPermissions` today only
  hides buttons and lets a local service refuse; a permission that only hides a
  button is not a permission.
- **The actor** on a decision comes from the caller's token, not from
  `ModerationDecision.actorName` in the request body. That field exists so the
  pre-backend implementations record the same information.

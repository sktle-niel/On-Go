# On Go

Roadside mechanic services. The product ships as **two applications**, in **two
repositories**:

| | | |
| --- | --- | --- |
| **Mobile app** | `/lib`, this repository | Client + Mechanic — Flutter, Android/iOS |
| **Admin console** | `On-Go-Console`, its own repository | Admin + Moderator — Flutter web |

They share no code except `on_go_shared` (in `packages/`, here), which holds the
models and API contracts they exchange. They meet at the On Go API, which
implements those contracts and is deployed on staging.

**Read [ARCHITECTURE.md](ARCHITECTURE.md)** before changing anything that
crosses between them.

## Checking out

The console resolves all three shared packages in this repository by **relative
path**, so the two checkouts have to be siblings:

```
Documents/
  On-Go/          this repository — the mobile app, and packages/
  On-Go-Console/  the admin console
```

## Running

The mobile app, from the repository root:

```bash
flutter run
```

It talks to the On Go API on staging unless `ONGO_API_BASE_URL` says otherwise,
so sign in with a registered email and password, or register in the app. Admin
and Moderator are not in the app — they sign in on the console, and the API
refuses a console role on the mobile surface.

Built with `--dart-define=ONGO_BACKEND=local` nothing leaves the device, and the
sign-in shortcuts `client`, `mechanic`, `demo-client` and `demo-mechanic` work
again (see `LocalAuthService`).

The admin console, from its own checkout beside this one:

```bash
cd ../On-Go-Console && flutter run -d chrome
```

Sign in as `admin` to create the first moderator account. Moderators then sign
in with the email and password their admin set.

## Layout

```
lib/                      Mobile app (Client + Mechanic)
  data/                     On-device stores
  screens/                  Client and Mechanic UI
  services/backend/         ← the seam: every call that leaves the device
  services/api/             ← where the API client is installed
  theme/  widgets/

packages/
  on_go_design/             Design system shared by both front ends
    lib/src/                  Palettes, theme registry, tokens, ThemeController
  on_go_shared/             API contract shared by both — pure Dart
    lib/src/models/           DTOs with toJson/fromJson
    lib/src/api/              Abstract interfaces + the agreed REST routes
  on_go_api/                The HTTP client, sessions and event socket
    tool/smoke.dart           Read-only checks against a live API
```

The console is not in this tree — it is the `On-Go-Console` repository beside
it, and it consumes all three packages above by relative path.

Neither is the backend: it is a separate TypeScript repository
(`sktle-niel/On-Go-WA`), deployed on staging. Its OpenAPI document is the
contract these packages mirror.

## The rules that keep this working

**Neither application imports the other.** Anything one needs from the other
goes through an interface in `on_go_shared`, reached via
`MobileBackend.instance` or `ConsoleBackend.instance` — never around them.

**Neither application defines a colour.** Both read the palettes in
`on_go_design`, so the two look like one product: the same six themes under the
same names, with the same Dark Mode, Dynamic Themes and Warm Filter. Each app
builds its own `ThemeData` from those palettes, because a phone and a desktop
want different densities — but not different colours.

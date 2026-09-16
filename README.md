# On Go

Roadside mechanic services. The product ships as **two applications**, in **two
repositories**:

| | | |
| --- | --- | --- |
| **Mobile app** | `/lib`, this repository | Client + Mechanic — Flutter, Android/iOS |
| **Admin console** | `on_go_console`, its own repository | Admin + Moderator — Flutter web |

They share no code except `on_go_shared` (in `../Backend/on_go_backend/packages`), which holds the models and
API contracts they exchange. They will meet at a backend that implements those
contracts; that backend is not built yet.

**Read [ARCHITECTURE.md](ARCHITECTURE.md)** before changing anything that
crosses between them.

## Checking out

The console resolves the two shared packages in this repository by **relative
path**, so the two checkouts have to be siblings:

```
Flutter/
  on_go/          this repository
  on_go_console/  the admin console
```

## Running

The mobile app, from the repository root:

```bash
flutter run
```

Sign in with `client`, `mechanic`, `demo-client` or `demo-mechanic`, or with an
account registered in that session. Admin and Moderator are not in the app —
they sign in on the console.

The admin console, from its own checkout beside this one:

```bash
cd ../on_go_console && flutter run -d chrome
```

Sign in as `admin` to create the first moderator account. Moderators then sign
in with the email and password their admin set.

## Layout

```
lib/                      Mobile app (Client + Mechanic)
  data/                     In-memory stores
  screens/                  Client and Mechanic UI
  services/backend/         ← everything that will become a network call
  theme/  widgets/

packages/on_go_design/    Design system shared by both
  lib/src/                  Palettes, theme registry, tokens, ThemeController

```

The console is not in this tree — it is the `on_go_console` repository beside
it, and it consumes `packages/on_go_design` above by relative path.

The backend scaffold is not in this tree either: it lives in
`../Backend/on_go_backend` (TypeScript, no routes yet). The API contract and
client both apps use live beside it:

```
../Backend/on_go_backend/packages/
  on_go_shared/             API contract shared by both — pure Dart
    lib/src/models/           DTOs with toJson/fromJson
    lib/src/api/              Abstract interfaces + the agreed REST routes
  on_go_api/                The HTTP client, sessions and event socket
    tool/smoke.dart           Read-only checks against a live API
```

## The rules that keep this working

**Neither application imports the other.** Anything one needs from the other
goes through an interface in `on_go_shared`, reached via
`MobileBackend.instance` or `ConsoleBackend.instance` — never around them.

**Neither application defines a colour.** Both read the palettes in
`on_go_design`, so the two look like one product: the same six themes under the
same names, with the same Dark Mode, Dynamic Themes and Warm Filter. Each app
builds its own `ThemeData` from those palettes, because a phone and a desktop
want different densities — but not different colours.

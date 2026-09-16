# On Go — project state

Where the project actually stands, as distinct from how it is put together.

- **[README.md](README.md)** — what On Go is, and how to run it.
- **[ARCHITECTURE.md](ARCHITECTURE.md)** — how the pieces fit, and the rules
  that keep them apart. Read that before changing anything that crosses
  between the two applications.
- **This file** — what is built, what is deliberately stubbed, what is missing,
  and what is known to be wrong.

Keep it honest. A status document that flatters the project is worse than none,
because the next person plans against it.

---

## In one line

Two Flutter front ends, a shared contract and a deployed API. Accounts, the
points rules, revenue, the verification queue, the moderator directory and the
Sign In background cross between the two applications through the API. The jobs
domain does not: the server owns it, and each phone still runs its own copy.

| Part | State |
| --- | --- |
| `/lib` — mobile app (Client + Mechanic) | Working; accounts on the API, jobs on the device |
| `On-Go-Console` (separate repo) — console (Admin + Moderator) | Working, on the API |
| `/packages/on_go_shared` — API contract | Complete for what exists |
| `/packages/on_go_api` — API client | Auth, points policy, revenue, appearance, verification, moderators |
| `/packages/on_go_design` — design system | Complete, 8 themes in 4 families |
| The On Go API (separate repo) | Deployed on staging; the jobs routes are live but carry no traffic yet |

---

## What works

### Mobile app — Client

Request help (with photos, location and an urgency that sets the completion
deadline), compare mechanic quotes, accept or reject them, follow the job
through to payment by QR, rate the mechanic, and read service history. A bell
covers quote received, job accepted, work started, payment due, and a mechanic
running past their ETA.

Registration files a client account in-session. "Forgot Password?" runs a real
reset: a one-time code, expiry and attempt limits, and a new password written
into the account store that then signs in.

### Mobile app — Mechanic

Browse and quote available jobs — and withdraw a quote the client has not
accepted yet — accept emergencies outright, drive a job through navigation →
arrival → work → completion, take payment, and see earnings and leaderboard
standing. A notification bell covers quote accepted, quote rejected,
rating received, payment received, emergency posted and account approved. The
Emergency filter pulses when unviewed emergency jobs are waiting, with a
per-mechanic toggle in Settings.

Registration is a five-step flow that files an account request for moderation,
including uploads of the Mechanic ID, documents and certifications. The draft
survives the app being killed behind an external picker, so uploading a photo
does not cost the applicant their answers.

### Console — Admin

Overview, moderator roster with per-permission control, Add Moderator, Audit
Log, Notifications (escalations), Points, Income and Settings. The Audit Log
records both roster changes and queue decisions, filters by the role that
performed the action, and opens any entry for its full detail including the
originating IP address. Income and Overview report real completed payments —
no sample data is left in the console.

### Console — Moderator

Verification queue, decision history, accounts, profile and settings, gated by
the permissions their admin granted. The queue shows an applicant's uploaded ID
and credentials; an admin sees them when a moderator escalates the account.

### Shared

Eight themes in four light/dark families (Classic, Calm Blue, Ember, Forest),
with Dark Mode, Dynamic Themes (follows the clock) and a continuous Warm
Filter. Both front ends build their own `ThemeData` from the same palettes.

---

## The domain rules that carry the most weight

Each of these is one definition that several screens read. They are the places
where a change is cheap and a duplicate is expensive.

| Rule | Where | What it decides |
| --- | --- | --- |
| `settledPaymentAmount()` | `lib/data/quote_store.dart` | What a finished job cost, in every history view on both sides |
| `clientTotalPaymentAmount()` | same | What the client pays: the mechanic's amount **plus** the priority fee |
| `jobCompletionWindows` | same | 12h Emergency / 3d Urgent, and **nothing for Normal** — the countdown, the sort, the expiry sweep and the ETA cap all read it |
| `maxEtaFor()` | same | The longest ETA a mechanic may promise: what is left of the job's window, or no limit when it has none |
| `jobCountdown()` | same | Which clock an accepted job is on — its completion deadline, or the quoted arrival when it has no deadline |
| `formatTimeRemaining()` | same | One countdown format app-wide: `4d 23h 59m` at or above a day, `23h 59m 59s` below it |
| `clientCancelLockedByEta()` | same | Whether the client may cancel yet, enforced in the store rather than per screen |
| `PointsPolicyStore.current` | `lib/data/points_policy_store.dart` | Every points rate, so an admin changing one changes all the arithmetic at once |
| `revenueUrgencyColor()` | `On-Go-Console/lib/src/widgets/revenue_charts.dart` | The colour of Normal / Urgent / Emergency in every console chart, ring and key |
| `PlatformRevenueSummary.yearlyTotals` | `on_go_shared/…/platform_revenue.dart` | A year's revenue, always summed from its months rather than stored beside them |

**The priority fee is platform revenue, not payout.** +₱50 Urgent and +₱100
Emergency are charged at checkout, booked as ONGO revenue on a successful
payment, and never reach the mechanic. Urgency still drives dispatch priority
and the completion deadline. The two halves live in separate functions on
purpose — compare `clientTotalPaymentAmount` with `effectivePaymentAmount`.

**The ledger is split by urgency, and Normal earns nothing.** A payment is
reported with its `RevenueUrgency`, so the console's Overview line chart,
Income bars and Income rings all read one breakdown rather than three. Because
Normal jobs carry no priority fee, their **revenue** line legitimately sits at
zero while their **transaction** count is the largest of the three — which is
why the console reports volume and revenue as separate figures instead of
inferring one from the other. Give Normal a base fee and the line lifts on its
own, no chart change required.

**The ETA is a promise, not an estimate.** The mechanic sends a number plus a
unit; the countdown starts when the quote is accepted. While it runs the job is
held for them and the client cannot cancel — refused inside
`clientRevertToPending` and `clientDeleteRequest`, not merely hidden in the UI.
When it passes, the client is notified that cancelling is now available.
Arrival stops the countdown, the lateness notice and the lock together.

**Urgency and the ETA are one system.** Urgent and Emergency keep their
completion windows, and an ETA longer than what is left of one is refused — at
the field and again in the store, since a mechanic still driving when the job
is already due has promised something the job cannot deliver. Normal has no
window at all: its timing *is* the quoted ETA, so nothing caps it, nothing
counts down to a completion deadline, and the expiry sweep passes it over. What
a late Normal job gets is the ETA notice and the client's freedom to cancel.

**A quote can be taken off the table from either end.** The mechanic withdraws
their own (only before it is accepted, and they may quote again afterwards);
the client rejects it (the mechanic is told, and cannot re-quote that job).
Neither deletes the record — `MechanicQuote.isLive` is what the client's list
filters on, and the kept record is what makes a rejection stick.

---

## What is deliberately stubbed

These are **not** bugs. Each is a local implementation refusing work that is
not its surface's to do, and each disappears when `configure()` is handed a
real client. See *The seam* in [ARCHITECTURE.md](ARCHITECTURE.md).

| Refuses | Why |
| --- | --- |
| Mobile `LocalVerificationService.decide()` | A phone must not approve its own owner's account |
| Mobile `LocalPointsPolicyService.update()` | The rates are set in the console |
| Mobile `LocalAppearanceService.publishBackground()` | Branding is set in the console |
| Console `LocalVerificationService.submit()` | Registrations are filed from the app |
| Console `LocalRevenueService.reportCompletedPayment()` | Only a completed client payment books revenue |

These refusals still stand, but they now describe an `ONGO_BACKEND=local` build.
Against the API a registration reaches the moderator queue, a published
background reaches every phone, and the console's lists fill from real rows —
they look empty on staging only because little traffic has gone through it.

---

## What is missing

### The jobs domain is served, and the app is not on it

This replaced "the backend has no routes", which was the entry here for a long
time. The API now serves booking, quotes, accept, the status machine, payment
and points, cancel and expiry, reviews, the leaderboard, locations and chat.

What has not happened is the other half: `quote_store.dart` still runs the whole
job lifecycle on the device, and nothing in `/lib` calls a `/service-requests`
route. Two phones therefore still cannot see the same job, which was the reason
for a server in the first place.

The order is forced by the server, not chosen. `POST /service-requests/:id/pay`
looks the job up by id and answers 404 for one it does not hold, so a job has to
be **booked, quoted, accepted and marked service-complete on the server** before
it can be paid there. Payment is the end of the sequence, not the start of it:

    book → quote → accept → progress → pay

So the first move is booking. Once a job is the server's from the start, the
rest follows it, and `POST /payments` — the compatibility window the server
keeps open for jobs it does not hold — can close.

The contract and the API client are in place as of 2026-09-16:
`ServiceRequestApi` is merged, `HttpServiceRequestApi` implements all of it over
HTTP, and `OnGoApi.serviceRequests` exposes it. What is left is the call sites:
`MobileBackend` does not carry it yet, and no screen reads it.

### Test coverage

- `/lib` and `/packages` — **909 tests**, run with `flutter test` from the
  repository root. They cover the API client, the event socket, the auth and
  platform HTTP implementations, the leaderboard engine, mechanic ranks and
  rankings, job evaluations, urgency policy and its points awards, points
  conversion, notification routing, location, the PSGC place directory, and
  responsive layout across nine screen sizes.
- `On-Go-Console` (separate repo) — 45 tests, covering responsive layout
  classification, the shared theme registry, the admin ranks and urgency pages,
  and the leaderboard pages and services.

This entry used to read "none", and was the largest gap after the backend. The
rules in the table above are the ones worth keeping covered: they break
quietly, and the stores in `lib/data/` are pure Dart singletons with no Flutter
dependency, so they are cheap to test.

### Persistence

The job stores are in memory and die with the process. What survives a restart:

- **The session**, in the Keychain (iOS) or the Keystore-backed store
  (Android): the refresh token, through `SecureRefreshTokenStore`. The access
  token is never written anywhere. So the app reopens signed in, and the
  account itself lives on the server rather than on the device at all.
- **`RecordBox`** (`lib/services/local/record_box.dart`) — records as JSON in
  `shared_preferences`, behind an interface written so an API-backed box can
  replace it without any store or screen changing. Used by the review, job
  evaluation, mechanic performance, point transaction and problem report
  stores.
- **`shared_preferences` directly** — the selected theme, dark mode, dynamic
  themes, the warm filter level, the auth background photo, the mechanic's
  emergency alert toggle, the registration draft, and the urgency, rank and
  leaderboard settings.
- **The app documents directory** — the **bytes** of uploaded credential files.

Note the asymmetry in that last one: the files survive a restart but the
records describing them do not, so the app forgets whose they were. See below.

---

## Known issues

**A brand-coloured "denied" state.** Two places assume the brand colour is red
and use it to mean negative:

- `On-Go-Console/lib/src/widgets/console_widgets.dart:460` — a withheld
  permission draws its disc in `ConsoleColors.brand`. `ConsoleColors.danger`
  already exists a few hundred lines below it.
- `lib/widgets/change_password_dialog.dart:156` — error text uses
  `AppColors.primary`.

Under any theme whose brand is not red — Calm Blue, Ember, Forest — a denied
permission reads as granted and an error reads as neutral. One word each
(`brand` → `danger`, `primary` → `error`).

**Credential metadata is not persisted.** `MechanicCredentialStore` copies
uploads into the app documents directory, so the files outlive the process, but
the records linking them to a mechanic are in memory. After a restart the files
are orphaned on disk. Persisting the index is the fix until the backend owns
the files outright.

**The reset code is shown on screen.** There is no mail server, so
`PasswordResetStore` surfaces the one-time code in the UI, labelled as standing
in for the email. `_issueCode` and `visibleCode` are the only two things that
change when real delivery arrives.

**Moderator activity is recorded twice.** A queue decision writes both a
`ModerationActivity` and an `AuditEntry`. The audit log is what the console now
shows; `ModerationActivity` is still written and still exposed by
`watchActivity()`, but nothing surfaces it. Retiring it is a clean-up, not a
fix.

**`debugSeedRequest`.** `On-Go-Console/packages/on_go_console_backend/lib/local/local_verification_service.dart:56` carries a test-only method to
put a request in the queue, because `submit()` is refused from the console and
there is otherwise no way to exercise `decide()` locally. It is not on the API
interface and no screen calls it. It should go when the backend can supply real
requests.

**Narrow-width overflow.** The mechanic earnings header and the profile
location rows overflow horizontally on small phones. Cosmetic, unfixed.

---

## Conventions worth knowing

**One seam per app.** `MobileBackend.instance` and `ConsoleBackend.instance` are
the only places a call leaves an application. Do not reach around them.

**No screen defines a colour.** Read `AppColors` (mobile) or `ConsoleColors`
(console); both resolve from the palette in `on_go_design`. Adding a theme is
one `AppThemeOption` appended to `AppThemes.all` — the pickers build themselves
from that list, and a family needs exactly one light and one dark member. The
colour tokens are getters rather than constants, so a widget reading one cannot
be `const`.

**Stores are singleton `ChangeNotifier`s.** `Something.instance`, listened to by
screens. Anything persisted follows `ThemeController`'s shape: `load()` before
`runApp`, and a failed read leaves the default rather than blocking startup.

**Subscribe in `initState`, not in `build`.** The console shell swaps
arrangements when the window crosses a breakpoint, which re-inflates the page
body. A `StreamBuilder` built in a `build` that does not re-run will listen
twice to the same stream. `LiveValue` now hands out multi-subscription streams
so this cannot crash, but holding the subscription in state is still correct.

**Deadlines are anchored to stored timestamps, never to when a widget was
built.** `matchedAt` plus the urgency window is what a countdown reads, which is
why it keeps running across rebuilds, navigation and reopening the app instead
of restarting. Screens that count down own a one-second `Timer` and cancel it in
`dispose`.

**A rule the UI enforces, the store enforces too.** The cancellation lock is the
worked example: hiding the button is the courtesy, refusing the call is the
rule.

---

## If you are picking this up

1. Read [ARCHITECTURE.md](ARCHITECTURE.md), particularly *The seam* and
   *Adding an operation*.
2. Run both applications (see [README.md](README.md)). Against the API, sign in
   with a registered account on each side. In an `ONGO_BACKEND=local` build the
   old shortcuts still work: `client` and `demo-mechanic` on the app, `admin` on
   the console to create the first moderator.
3. The highest-value work, in order: **move the app onto the server's jobs
   routes, booking first** — payment can only follow a job the server already
   holds; then **tests for the rules table above** as each rule moves to the
   server; then the known-issue one-liners.

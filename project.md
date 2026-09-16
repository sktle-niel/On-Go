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

Two Flutter front ends and a shared contract are built and working against
in-memory data. The backend that would connect them is scaffolded but has no
routes, so the two applications cannot yet see each other.

| Part | State |
| --- | --- |
| `/lib` — mobile app (Client + Mechanic) | Working, in-memory |
| `on_go_console` (separate repo) — console (Admin + Moderator) | Working, in-memory |
| `../Backend/on_go_backend/packages/on_go_shared` — API contract | Complete for what exists |
| `/packages/on_go_design` — design system | Complete, 8 themes in 4 families |
| `../Backend/on_go_backend` — backend | Schema + infrastructure only, **no routes** |

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
| `revenueUrgencyColor()` | `on_go_console/lib/src/widgets/revenue_charts.dart` | The colour of Normal / Urgent / Emergency in every console chart, ring and key |
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

The visible consequences, all of which are correct for two disconnected apps:

- A registration filed on a phone stays **Pending** — no moderator can reach
  it. `demo-mechanic` is the local shortcut past that.
- The console's queue, accounts list and revenue ledger start **empty**.
- A background photo published in the console lives **in that browser only**.

---

## What is missing

### The backend — the one thing blocking everything else

`../Backend/on_go_backend` (formerly `/server`) has the parts that are hard to
retrofit and none of the part that is merely laborious:

- **Present:** Postgres schema (3 migrations), least-privilege roles, password
  hashing, token issue/verify, connection pool, structured logging, audit
  logging, error types, secret loading.
- **Absent:** every route. `src/routes/` and `src/plugins/` are empty
  directories. Nothing in the backend reads or writes a row yet.

Until routes exist, `on_go_shared` is a contract with two clients and
no server.

### Test coverage

- `on_go_console` (separate repo) — 30 tests (`console_layout_test.dart`, `console_theme_test.dart`)
  covering responsive layout classification and the shared theme registry.
- `/lib` — **none.** `test/` exists and is empty. Features here have been
  verified with throwaway tests deleted once they passed, which proves a change
  once and protects nothing afterwards.
- `/packages` — no tests of their own; the design system is exercised through
  the console's theme tests.

This is the largest gap after the backend, and it has grown: the rules in the
table above are exactly the kind that break quietly. The stores in `lib/data/`
are pure Dart singletons with no Flutter dependency and would be cheap to
cover.

### Persistence

Everything on the mobile side is in memory and dies with the process, except:

- `shared_preferences` — the selected theme, dark mode, dynamic themes, the
  warm filter level, the auth background photo, the mechanic's emergency alert
  toggle, and the mechanic registration draft.
- The app documents directory — the **bytes** of uploaded credential files.

Note the asymmetry in that second one: the files survive a restart but the
records describing them do not, so the app forgets whose they were. See below.

---

## Known issues

**A brand-coloured "denied" state.** Two places assume the brand colour is red
and use it to mean negative:

- `on_go_console/lib/src/widgets/console_widgets.dart:460` — a withheld permission
  draws its disc in `ConsoleColors.brand`.
- `lib/widgets/change_password_dialog.dart:102` — error text uses
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

**`debugSeedRequest`.** `LocalVerificationService` carries a test-only method to
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
2. Run both applications (see [README.md](README.md)). Sign in on the app as
   `client` and `demo-mechanic`; sign in on the console as `admin` and create
   the first moderator.
3. The highest-value work, in order: **routes in `../Backend/on_go_backend`**, then **tests for
   `lib/data/`** starting with the rules table above, then the known-issue
   one-liners.

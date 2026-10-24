# Database contract tests

Apply both migrations, in filename order, to a development Supabase project.
Run `contest_contract.sql` and then `secret_reveal_contract.sql`, each as a complete
script in the SQL editor, or:

```sh
psql "$DATABASE_URL" --set ON_ERROR_STOP=1 --file supabase/tests/contest_contract.sql
psql "$DATABASE_URL" --set ON_ERROR_STOP=1 --file supabase/tests/secret_reveal_contract.sql
```

The suite checks name-only registration, normalized duplicate-name checks, three
distinct votes, no self-votes, one ballot per registered name, phase controls,
owner-only aggregate results, and actual
anonymous/authenticated PostgreSQL role privileges. It rolls back its changes.
Use a development project: the transactional setup temporarily truncates contest
tables and may block requests until the test finishes. The reveal suite additionally
tests masked public titles (including own-name lookup), owner visibility, exact
reveal-time behavior, backward-compatible registration, deletion permissions,
deletion before/after ballots, and both hidden-costume voting guards. Its private
deadline/phase changes and fixture deletions also roll back.

## Optional local PostgreSQL runner

`run_contract.mjs` creates disposable in-memory PostgreSQL using PGlite. No database
extension is needed. It executes all saved migrations and both SQL suites unchanged,
then verifies every fixture was rolled back. Only the Supabase Auth role and
`auth.uid()` integration is stubbed; grants, RLS, functions, and transactions execute
inside PostgreSQL.

From this directory, install the development dependency and run:

```sh
pnpm install --frozen-lockfile --store-dir .pnpm-store --cache-dir .cache
pnpm test
```

The dependency is isolated from the Flutter app and is never deployed. The install
command uses the pinned PGlite 0.5.11 dependency and checked-in `pnpm-lock.yaml`
for reproducible installs.

PGlite provides one database connection. This runner cannot verify races between
concurrent registration, voting, and phase-change transactions. Those checks need
a full PostgreSQL server or a development Supabase project. It also does not test
the hosted Auth service, JWT verification, or the PostgREST HTTP layer.

Validation on 24 October 2026: both migrations and both SQL contract suites passed
against PostgreSQL 18.6 through PGlite 0.5.11. The runner also verified that every
test fixture rolled back. These tests do not connect to the live project.

## Name-only guest contract

- `participant_session(p_username)` returns the registered identity and ballot
  status, or null identity fields and `has_voted: false` for an unused valid name.
- `register_participant(p_username, p_costume, p_hide_until_reveal = false)` rejects
  an existing normalized name. Existing two-argument callers remain supported.
- `submit_ballot(p_username, p_costume_ids)` accepts exactly three distinct other
  costumes once for that registered name.
- Names are 2–32 characters after normalization. Leading/trailing whitespace is
  removed, internal whitespace runs become one ASCII space, and display case is
  preserved. Lowercase normalized names determine equality; there is no fuzzy
  matching. Raw C0/C1 controls, including tabs/newlines, are rejected first.
- Costume names are trimmed and must be 2–80 characters, without control characters.

The identity-confirmation popup is an honor-system acknowledgement, not secure
authentication. Anyone can enter another registered name or register multiple
different names. The backend enforces duplicate-name, self-vote, and repeat-ballot
rules for the selected name; it cannot verify the person entering it. Guests have
no codes, QR links, or passwords. Organizer results still require an authorized
Supabase Auth account and expose aggregate totals only.

## Secret titles and organizer deletion

The deadline is **31 October 2026, 20:00 Europe/Budapest (19:00 UTC)**. Costume
titles marked private return `title: "Secret costume"` and `title_hidden: true`
from the public RPC before that instant. Names remain visible. Reveal is evaluated
against server time when each response is produced; no scheduled job is required.
The public and organizer snapshots include `reveal_at` and `server_time`.
Organizer results contain the actual title and its current `title_hidden` status.
Participant sessions and registration responses contain no costume title at all.

If any title is still hidden, opening voting and submitting ballots are blocked.
If no entries are hidden, voting can open before the deadline when at least four
costumes exist. After the deadline, existing hidden flags require no database edit.

`admin_delete_entry(p_costume_id)` requires an authorized organizer, registration
stage, and zero ballots. It returns `{ "deleted": true }` after removing the
costume and participant, freeing the name for registration again. It never deletes
votes or cascades through ballots. Deleting below four entries is allowed; the
existing minimum of four still prevents voting from opening.

The second migration explicitly drops the old two-argument registration function
before creating its new signature with a defaulted third parameter, avoiding
ambiguous PostgREST overloads. Do not reapply the original migration to upgrade an
existing project; apply only `202610240002_secret_reveal_and_entry_deletion.sql`.

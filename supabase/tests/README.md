# Database contract tests

`contest_contract.sql` is the authoritative integration suite. Run it after applying
the migration to a development Supabase project, using its SQL editor or:

```sh
psql "$DATABASE_URL" --set ON_ERROR_STOP=1 --file supabase/tests/contest_contract.sql
```

The suite checks name-only registration, normalized duplicate-name checks, three
distinct votes, no self-votes, one ballot per registered name, phase controls,
owner-only aggregate results, and actual
anonymous/authenticated PostgreSQL role privileges. It rolls back its changes.
Use a development project: the transactional setup temporarily truncates contest
tables and may block requests until the test finishes.

## Optional local PostgreSQL runner

`run_contract.mjs` creates disposable in-memory PostgreSQL using PGlite. No database
extension is needed. It executes the saved migration and SQL suite unchanged,
then verifies every fixture was rolled back. Only the Supabase Auth role and
`auth.uid()` integration is stubbed; grants, RLS, functions, and transactions execute
inside PostgreSQL.

From this directory, install the development dependency and run:

```sh
pnpm add --save-dev --save-exact @electric-sql/pglite --store-dir .pnpm-store --cache-dir .cache
pnpm test
```

The dependency is isolated from the Flutter app and is never deployed. The install
command pins the resolved package version and creates `pnpm-lock.yaml` for future
reproducible installs. The checked-in manifest uses `latest` only because no
dependency download has been authorized or performed yet; no lockfile is claimed.

PGlite provides one database connection. This runner cannot verify races between
concurrent registration, voting, and phase-change transactions. Those checks need
a full PostgreSQL server or a development Supabase project. It also does not test
the hosted Auth service, JWT verification, or the PostgREST HTTP layer.

Current validation: the runner passes Node's JavaScript syntax check. Neither the
SQL suite nor the PGlite runner has been executed in this workspace because the
required PostgreSQL runtime/dependency is not installed.

## Name-only guest contract

- `participant_session(p_username)` returns the registered identity and ballot
  status, or null identity fields and `has_voted: false` for an unused valid name.
- `register_participant(p_username, p_costume)` rejects an existing normalized name.
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

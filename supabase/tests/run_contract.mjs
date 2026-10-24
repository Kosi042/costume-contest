import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

// A disposable in-memory PostgreSQL build; no extension is needed.
// Only Supabase's auth integration is stubbed. The application migration and
// rollback SQL suite below are executed as saved, without rewriting their SQL.
// PGlite has one connection: this does not exercise simultaneous transactions.
const db = await PGlite.create({
  dataDir: 'memory://',
  onNotice: (notice) => {
    if (notice.message?.startsWith('PASS:')) console.log(notice.message);
  },
});

try {
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin bypassrls;
    create schema auth;
    create table auth.users (id uuid primary key, email text);
    create function auth.uid()
    returns uuid language sql stable set search_path = '' as $$
      select coalesce(
        nullif(current_setting('request.jwt.claim.sub', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
      )::uuid;
    $$;
    grant usage on schema auth to anon, authenticated, service_role;
    grant execute on function auth.uid() to anon, authenticated, service_role;
    grant usage on schema public to anon, authenticated, service_role;
    revoke create on schema public from public;
  `);

  const version = await db.query('select version() as version');
  console.log(`Test engine: ${version.rows[0].version}`);

  const migration = await readFile(
    new URL('../migrations/202610240001_costume_contest.sql', import.meta.url),
    'utf8',
  );
  await db.exec(migration);
  console.log('PASS: application migration executed unchanged.');

  const contract = await readFile(new URL('./contest_contract.sql', import.meta.url), 'utf8');
  await db.exec(contract);

  // The suite must actually roll back, including its test user and organizer.
  const rollback = await db.query(`
    select
      (select count(*)::integer from auth.users) as users,
      (select count(*)::integer from contest_private.owners) as owners,
      (select count(*)::integer from contest_private.participants) as participants,
      (select count(*)::integer from contest_private.ballots) as ballots,
      (select count(*)::integer from contest_private.votes) as votes,
      (select stage from contest_private.contest) as stage
  `);
  assert.deepEqual(rollback.rows[0], {
    users: 0, owners: 0, participants: 0, ballots: 0, votes: 0, stage: 'registration',
  });
  console.log('PASS: rollback removed every contract-test fixture.');
  console.log('All database contract tests passed. Concurrent transaction behavior requires a full PostgreSQL/Supabase run.');
} catch (error) {
  console.error('FAIL:', error.message);
  if (error.detail) console.error('Detail:', error.detail);
  if (error.where) console.error('Context:', error.where);
  if (error.position) console.error('SQL position:', error.position);
  process.exitCode = 1;
} finally {
  await db.close();
}

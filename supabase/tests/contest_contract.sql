-- Integration/security contract test for an already migrated Supabase database.
-- Run on a fresh development project in the SQL editor, or:
-- psql "$DATABASE_URL" --set ON_ERROR_STOP=1 --file supabase/tests/contest_contract.sql
-- Guest name confirmation is an honor system, not secure authentication.
-- All fixtures, owner claims, and test changes are rolled back. Existing contest
-- data is temporarily hidden by transactional truncation: do not run during an event.
begin;

truncate contest_private.votes, contest_private.ballots, contest_private.costumes,
  contest_private.participants;
update contest_private.contest set title = 'Contract test', stage = 'registration';

create function pg_temp.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'FAILED: %', p_message;
  end if;
end;
$$;

create function pg_temp.expect_error(p_query text, p_message text)
returns void language plpgsql as $$
declare
  v_failed boolean := false;
begin
  begin
    execute p_query;
  exception when others then
    if position(p_message in sqlerrm) = 0 then
      raise exception 'FAILED: expected message containing %, got %', p_message, sqlerrm;
    end if;
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'FAILED: query unexpectedly succeeded: %', p_query;
  end if;
end;
$$;

do $$
declare
  v_owner uuid := gen_random_uuid();
  v_other_user uuid := gen_random_uuid();
  v_names text[] := array['Alex Smith', 'Bea', 'Cam', 'Drew', 'Eve'];
  v_a jsonb;
  v_b jsonb;
  v_c jsonb;
  v_d jsonb;
  v_snapshot jsonb;
  v_public jsonb;
  v_ballot uuid[];
  v_attempt uuid[];
  v_function record;
  v_table record;
begin
  insert into auth.users(id, email) values (v_owner, 'contest-contract-test@example.invalid');
  insert into contest_private.owners(user_id) values (v_owner);
  perform set_config('contest_test.owner_id', v_owner::text, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_owner, 'role', 'authenticated')::text, true);

  perform pg_temp.assert_true(auth.uid() = v_owner, 'Test owner claim is active');
  perform pg_temp.assert_true(public.admin_snapshot()->>'stage' = 'registration', 'Initial registration stage');
  perform pg_temp.expect_error('select public.admin_set_stage(''voting'')', 'At least four');
  perform pg_temp.expect_error('select public.admin_set_stage(''invalid'')', 'Choose registration');
  perform pg_temp.expect_error('select public.admin_set_stage(null)', 'Choose registration');
  perform pg_temp.expect_error('select public.admin_set_title('' '')', 'event title');
  perform pg_temp.assert_true(public.admin_set_title('  Costume Party  ')->>'title' = 'Costume Party', 'Trim title');

  perform pg_temp.assert_true(public.participant_session('Alex Smith') =
    '{"participant_id":null,"username":null,"costume_id":null,"has_voted":false}'::jsonb,
    'Unknown valid name can enter registration');
  perform pg_temp.expect_error('select public.participant_session(null)', 'name of 2 to 32');
  perform pg_temp.expect_error('select public.participant_session('' '')', 'name of 2 to 32');
  perform pg_temp.expect_error('select public.participant_session(''A'')', 'name of 2 to 32');
  perform pg_temp.expect_error(format('select public.participant_session(%L)', repeat('a', 33)), 'name of 2 to 32');
  perform pg_temp.expect_error(format('select public.participant_session(%L)', 'Alex' || chr(9) || 'Smith'), 'name of 2 to 32');
  perform pg_temp.expect_error(format('select public.participant_session(%L)', 'Alex' || chr(10) || 'Smith'), 'name of 2 to 32');
  perform pg_temp.expect_error(format('select public.participant_session(%L)', 'Alex' || chr(1)), 'name of 2 to 32');
  perform pg_temp.expect_error(format('select public.participant_session(%L)', 'Alex' || chr(133)), 'name of 2 to 32');
  v_a := public.register_participant('  Alex   Smith  ', 'Moon Witch');
  perform pg_temp.assert_true(v_a->>'username' = 'Alex Smith' and v_a->>'participant_id' is not null
    and v_a->>'costume_id' is not null and v_a->>'has_voted' = 'false', 'Registration normalizes spacing and preserves case');
  perform pg_temp.expect_error('select public.register_participant('' alex smith '', ''Space Knight'')', 'name is already registered');
  perform pg_temp.expect_error('select public.register_participant(''ALEX  SMITH'', ''Space Knight'')', 'name is already registered');
  perform pg_temp.assert_true((select count(*) = 1 from contest_private.participants), 'Duplicate names create no extra participant');
  perform pg_temp.assert_true(public.participant_session(' aLeX  smITH ') = v_a, 'Case and spacing variants resolve the existing name');
  perform pg_temp.assert_true(public.participant_session(U&'Alex\00A0\2003Smith') = v_a, 'Unicode spaces collapse consistently');
  perform pg_temp.assert_true(public.participant_session('Alex Smyth')->>'participant_id' is null, 'No fuzzy name matching');
  perform pg_temp.expect_error('select public.register_participant(''B'', ''Space Knight'')', 'name of 2 to 32');
  perform pg_temp.expect_error('select public.register_participant(''Bea'', '''')', 'costume name of 2 to 80');
  v_b := public.register_participant(' Bea ', ' Space Knight ');
  v_c := public.register_participant('Cam', 'Forest Sprite');
  perform pg_temp.expect_error('select public.admin_set_stage(''voting'')', 'At least four');
  v_d := public.register_participant('Drew', 'Clockwork Owl');
  perform pg_temp.assert_true(public.participant_session('BEA') = v_b, 'Name lookup is case insensitive');

  v_ballot := array[(v_b->>'costume_id')::uuid, (v_c->>'costume_id')::uuid, (v_d->>'costume_id')::uuid];
  perform pg_temp.expect_error(format('select public.submit_ballot(%L, %L::uuid[])', v_names[1], v_ballot), 'Voting is not open');
  perform public.admin_set_stage('voting');
  perform pg_temp.expect_error('select public.register_participant(''Eve'', ''Silver Fox'')', 'Registration is closed');
  perform pg_temp.expect_error(format('select public.submit_ballot(%L, %L::uuid[])', v_names[5], v_ballot), 'Register your name');
  perform pg_temp.expect_error(format('select public.submit_ballot(%L, null)', v_names[1]), 'exactly three');
  v_attempt := array[(v_b->>'costume_id')::uuid, (v_c->>'costume_id')::uuid];
  perform pg_temp.expect_error(format('select public.submit_ballot(%L, %L::uuid[])', v_names[1], v_attempt), 'exactly three');
  v_attempt := array[(v_b->>'costume_id')::uuid, (v_b->>'costume_id')::uuid, (v_d->>'costume_id')::uuid];
  perform pg_temp.expect_error(format('select public.submit_ballot(%L, %L::uuid[])', v_names[1], v_attempt), 'exactly three');
  v_attempt := array[(v_b->>'costume_id')::uuid, (v_c->>'costume_id')::uuid, null];
  perform pg_temp.expect_error(format('select public.submit_ballot(%L, %L::uuid[])', v_names[1], v_attempt), 'exactly three');
  v_attempt := array[(v_a->>'costume_id')::uuid, (v_c->>'costume_id')::uuid, (v_d->>'costume_id')::uuid];
  perform pg_temp.expect_error(format('select public.submit_ballot(%L, %L::uuid[])', v_names[1], v_attempt), 'your own costume');
  v_attempt := array[(v_b->>'costume_id')::uuid, (v_c->>'costume_id')::uuid, gen_random_uuid()];
  perform pg_temp.expect_error(format('select public.submit_ballot(%L, %L::uuid[])', v_names[1], v_attempt), 'unavailable');
  perform pg_temp.assert_true((select count(*) = 0 from contest_private.ballots), 'Invalid ballots leave no ballot');
  perform pg_temp.assert_true((select count(*) = 0 from contest_private.votes), 'Invalid ballots leave no choices');
  -- A name is intentionally all that is needed: UI confirmation is not identity proof.
  perform pg_temp.assert_true(public.submit_ballot(' aLEX   SMITH ', v_ballot) = '{"accepted":true}'::jsonb, 'Name-only ballot accepted after normalization');
  perform pg_temp.assert_true(public.participant_session(v_names[1])->>'has_voted' = 'true', 'Session reports submitted ballot');
  perform pg_temp.expect_error(format('select public.submit_ballot(%L, %L::uuid[])', v_names[1], v_ballot), 'already been submitted');
  perform pg_temp.assert_true((select count(*) = 3 from contest_private.votes), 'One ballot creates exactly three choices');
  perform pg_temp.expect_error(format('insert into contest_private.votes(participant_id, costume_id, costume_owner_id) values (%L::uuid, %L::uuid, %L::uuid)',
    v_a->>'participant_id', v_a->>'costume_id', v_a->>'participant_id'), 'check constraint');
  perform pg_temp.expect_error('select public.admin_set_stage(''registration'')', 'cannot reopen');

  v_public := public.contest_public();
  perform pg_temp.assert_true(v_public->>'votes_per_person' = '3' and v_public->>'stage' = 'voting', 'Public settings contract');
  perform pg_temp.assert_true(jsonb_array_length(v_public->'costumes') = 4, 'Public contestant list');
  perform pg_temp.assert_true(not (v_public ? 'results') and not (v_public ? 'ballot_count'), 'Public response has no results');
  perform pg_temp.assert_true((select bool_and(not (item ? 'votes') and not (item ? 'participant_id')
    ) from jsonb_array_elements(v_public->'costumes') as t(item)), 'Public cards expose no vote counts');

  v_snapshot := public.admin_snapshot();
  perform pg_temp.assert_true(v_snapshot->>'registered_count' = '4'
    and v_snapshot->>'ballot_count' = '1', 'Owner aggregate counts');
  perform pg_temp.assert_true((select sum((item->>'votes')::integer) = 3
    from jsonb_array_elements(v_snapshot->'results') as t(item)), 'Owner vote totals sum to three');
  perform pg_temp.assert_true((select item->>'votes' = '0' from jsonb_array_elements(v_snapshot->'results') as t(item)
    where item->>'id' = v_a->>'costume_id'), 'Own costume received no self vote');
  perform pg_temp.assert_true((select bool_and(not (item ? 'voter_id') and not (item ? 'participant_id')
    and not (item ? 'choices')) from jsonb_array_elements(v_snapshot->'results') as t(item)), 'Owner receives no individual choices');

  perform public.admin_set_stage('closed');
  v_attempt := array[(v_a->>'costume_id')::uuid, (v_c->>'costume_id')::uuid, (v_d->>'costume_id')::uuid];
  perform pg_temp.expect_error(format('select public.submit_ballot(%L, %L::uuid[])', v_names[2], v_attempt), 'Voting is not open');
  perform public.admin_set_stage('voting');
  perform pg_temp.assert_true(public.submit_ballot(v_names[2], v_attempt)->>'accepted' = 'true', 'Organizer can resume voting');

  -- A signed-in non-owner has no owner powers, even though authenticated has RPC execute.
  perform set_config('request.jwt.claim.sub', v_other_user::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_other_user, 'role', 'authenticated')::text, true);
  perform pg_temp.expect_error('select public.admin_snapshot()', 'Organizer access required');
  perform pg_temp.expect_error('select public.admin_set_stage(''closed'')', 'Organizer access required');
  perform pg_temp.expect_error('select public.admin_set_title(''Hijacked'')', 'Organizer access required');

  -- Check actual grants, not just the intended function behavior.
  perform pg_temp.assert_true(not has_schema_privilege('anon', 'contest_private', 'USAGE'), 'Anonymous cannot access private schema');
  perform pg_temp.assert_true(not has_schema_privilege('authenticated', 'contest_private', 'USAGE'), 'Signed-in cannot access private schema');
  for v_table in select c.oid, c.relname, c.relrowsecurity from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'contest_private' and c.relkind = 'r' loop
    perform pg_temp.assert_true(v_table.relrowsecurity, 'RLS enabled on ' || v_table.relname);
    perform pg_temp.assert_true(not has_table_privilege('anon', v_table.oid, 'SELECT,INSERT,UPDATE,DELETE'), 'Anonymous denied raw table ' || v_table.relname);
    perform pg_temp.assert_true(not has_table_privilege('authenticated', v_table.oid, 'SELECT,INSERT,UPDATE,DELETE'), 'Signed-in denied raw table ' || v_table.relname);
  end loop;
  for v_function in select p.oid, p.proname, p.proconfig from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('contest_public', 'participant_session', 'register_participant',
      'submit_ballot', 'admin_snapshot', 'admin_set_stage', 'admin_set_title') loop
    perform pg_temp.assert_true(v_function.proconfig @> array['search_path=""'], 'Fixed search path for ' || v_function.proname);
    if v_function.proname like 'admin_%' then
      perform pg_temp.assert_true(not has_function_privilege('anon', v_function.oid, 'EXECUTE'), 'Anonymous denied ' || v_function.proname);
      perform pg_temp.assert_true(has_function_privilege('authenticated', v_function.oid, 'EXECUTE'), 'Signed-in can reach owner check ' || v_function.proname);
    else
      perform pg_temp.assert_true(has_function_privilege('anon', v_function.oid, 'EXECUTE'), 'Anonymous can call ' || v_function.proname);
    end if;
  end loop;
  raise notice 'PASS: name normalization, duplicate checks, ballot rules, phase controls, aggregate privacy, and privilege assertions.';
end;
$$;

-- Perform real calls as the browser roles. Ownership guards above were checked
-- separately, so neither a grant nor a permissive owner guard can mask the other.
set local role anon;
do $$
begin
  perform public.contest_public();
  if public.participant_session('Alex Smith')->>'has_voted' is distinct from 'true' then
    raise exception 'FAILED: anonymous cannot use name-only lookup';
  end if;
  begin
    perform public.admin_snapshot();
    raise exception 'FAILED: anonymous could call admin_snapshot';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from contest_private.votes;
    raise exception 'FAILED: anonymous could read raw votes';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

set local role authenticated;
do $$
begin
  perform public.contest_public();
  begin
    perform public.admin_snapshot();
    raise exception 'FAILED: non-owner authenticated user could read results';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from contest_private.votes;
    raise exception 'FAILED: authenticated user could read raw votes';
  exception when insufficient_privilege then null;
  end;
  perform set_config('request.jwt.claim.sub', current_setting('contest_test.owner_id'), true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', current_setting('contest_test.owner_id'), 'role', 'authenticated')::text, true);
  if public.admin_snapshot()->>'ballot_count' <> '2' then
    raise exception 'FAILED: actual authenticated owner could not read aggregate results';
  end if;
  begin
    perform 1 from contest_private.votes;
    raise exception 'FAILED: authenticated owner could read raw votes';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: actual anonymous and authenticated role access checks.';
end;
$$;
reset role;

rollback;

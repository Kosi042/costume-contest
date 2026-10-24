-- Run after both migrations, as postgres, on a development/empty contest.
-- The entire script is one transaction and rolls back all fixtures and deadline
-- changes. Its temporary TRUNCATE locks contest data: do not run during an event.
begin;

truncate contest_private.votes, contest_private.ballots,
  contest_private.costumes, contest_private.participants;
update contest_private.contest
  set stage = 'registration', reveal_at = statement_timestamp() + interval '1 day';

create function pg_temp.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
  if p_condition is not true then raise exception 'FAILED: %', p_message; end if;
end;
$$;

create function pg_temp.expect_error(p_query text, p_message text)
returns void language plpgsql as $$
declare v_failed boolean := false;
begin
  begin
    execute p_query;
  exception when others then
    if position(p_message in sqlerrm) = 0 then
      raise exception 'FAILED: expected %, got %', p_message, sqlerrm;
    end if;
    v_failed := true;
  end;
  if not v_failed then raise exception 'FAILED: query unexpectedly succeeded: %', p_query; end if;
end;
$$;

do $$
declare
  v_owner uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_secret jsonb;
  v_one jsonb;
  v_two jsonb;
  v_three jsonb;
  v_removable jsonb;
  v_replacement jsonb;
  v_public jsonb;
  v_admin jsonb;
  v_card jsonb;
  v_choices uuid[];
begin
  insert into auth.users(id, email)
    values (v_owner, 'secret-reveal-contract-test@example.invalid');
  insert into contest_private.owners(user_id) values (v_owner);
  perform set_config('reveal_test.owner_id', v_owner::text, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_owner, 'role', 'authenticated')::text, true);

  perform pg_temp.assert_true((select count(*) = 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'register_participant'),
    'There is exactly one registration overload for PostgREST');
  perform pg_temp.assert_true((select p.pronargs = 3 and p.pronargdefaults = 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'register_participant'),
    'Three-argument registration retains its optional boolean');
  perform pg_temp.assert_true(has_function_privilege('anon',
    'public.register_participant(text,text,boolean)', 'EXECUTE'), 'Guest registration grant');
  perform pg_temp.assert_true(not has_function_privilege('anon',
    'public.admin_delete_entry(uuid)', 'EXECUTE'), 'Anonymous cannot execute deletion');
  perform pg_temp.assert_true(has_function_privilege('authenticated',
    'public.admin_delete_entry(uuid)', 'EXECUTE'), 'Authenticated deletion reaches owner check');

  v_secret := public.register_participant('Hidden Guest', 'MIDNIGHT_PRIVATE_TITLE', true);
  -- Legacy two-argument clients keep working; their titles are public by default.
  v_one := public.register_participant('Reveal One', 'Visible Witch');
  v_two := public.register_participant('Reveal Two', 'Visible Owl', false);
  v_three := public.register_participant('Reveal Three', 'Visible Knight', null);
  v_removable := public.register_participant('Removable Guest', 'Visible Sprite');
  perform pg_temp.assert_true(not (v_secret ? 'title') and not (v_secret ? 'costume')
    and position('MIDNIGHT_PRIVATE_TITLE' in v_secret::text) = 0,
    'Registration returns no secret title');
  perform pg_temp.assert_true(public.participant_session(' hidden guest ') = v_secret,
    'Claiming the same name returns identity only');
  perform pg_temp.assert_true(not (public.participant_session('Hidden Guest') ? 'title'),
    'Participant session never exposes titles');

  v_public := public.contest_public();
  perform pg_temp.assert_true((v_public->>'server_time')::timestamptz < (v_public->>'reveal_at')::timestamptz,
    'Public response includes authoritative server time and future deadline');
  perform pg_temp.assert_true(position('MIDNIGHT_PRIVATE_TITLE' in v_public::text) = 0,
    'Entire public payload excludes secret title, even with organizer claims');
  select item into v_card from jsonb_array_elements(v_public->'costumes') as t(item)
    where item->>'id' = v_secret->>'costume_id';
  perform pg_temp.assert_true(v_card->>'username' = 'Hidden Guest'
    and v_card->>'title' = 'Secret costume' and v_card->>'title_hidden' = 'true',
    'Secret entry keeps its visible name and a masked title');
  select item into v_card from jsonb_array_elements(v_public->'costumes') as t(item)
    where item->>'id' = v_one->>'costume_id';
  perform pg_temp.assert_true(v_card->>'title' = 'Visible Witch' and v_card->>'title_hidden' = 'false',
    'Ordinary entries are visible before reveal');
  v_admin := public.admin_snapshot();
  select item into v_card from jsonb_array_elements(v_admin->'results') as t(item)
    where item->>'id' = v_secret->>'costume_id';
  perform pg_temp.assert_true(v_card->>'title' = 'MIDNIGHT_PRIVATE_TITLE'
    and v_card->>'title_hidden' = 'true', 'Owner gets actual title and effective hidden status');
  perform pg_temp.assert_true(v_admin->>'reveal_at' = v_public->>'reveal_at'
    and v_admin->>'server_time' is not null, 'Owner response includes the same deadline and server clock');
  perform pg_temp.expect_error('select public.admin_set_stage(''voting'')', 'secret costumes are hidden');

  perform pg_temp.expect_error('select public.admin_delete_entry(null)', 'no longer exists');
  perform pg_temp.expect_error(format('select public.admin_delete_entry(%L::uuid)', gen_random_uuid()), 'no longer exists');
  perform pg_temp.assert_true(public.admin_delete_entry((v_removable->>'costume_id')::uuid)
    = '{"deleted":true}'::jsonb, 'Owner can delete during registration before ballots');
  perform pg_temp.assert_true(public.participant_session('Removable Guest')->>'participant_id' is null,
    'Deleting an entry removes its participant identity');
  v_replacement := public.register_participant('Removable Guest', 'Replacement Sprite');
  perform pg_temp.assert_true(v_replacement->>'participant_id' <> v_removable->>'participant_id'
    and v_replacement->>'costume_id' <> v_removable->>'costume_id',
    'Deleted name can register again with new IDs');
  perform pg_temp.assert_true((select count(*) = 5 from contest_private.participants),
    'Other registrations survived deletion');

  -- Once the only secret is removed, voting may open before the deadline.
  perform public.admin_delete_entry((v_secret->>'costume_id')::uuid);
  perform public.admin_delete_entry((v_three->>'costume_id')::uuid);
  perform pg_temp.assert_true((select count(*) = 3 from contest_private.costumes),
    'Organizer deletion may leave fewer than four entries');
  perform pg_temp.expect_error('select public.admin_set_stage(''voting'')', 'At least four');
  v_three := public.register_participant('Reveal Three', 'Visible Knight');
  perform public.admin_set_stage('voting');
  perform pg_temp.expect_error(format('select public.admin_delete_entry(%L::uuid)',
    v_one->>'costume_id'), 'only be deleted while registration is open');
  perform public.admin_set_stage('registration');
  v_secret := public.register_participant('Hidden Guest', 'MIDNIGHT_PRIVATE_TITLE', true);
  v_choices := array[(v_two->>'costume_id')::uuid, (v_three->>'costume_id')::uuid,
    (v_replacement->>'costume_id')::uuid];

  -- Simulate a pre-existing voting stage/private deadline change. The submit RPC
  -- must independently refuse all ballots while any costume remains hidden.
  update contest_private.contest set stage = 'voting' where singleton;
  perform pg_temp.expect_error(format('select public.submit_ballot(%L, %L::uuid[])',
    'Reveal One', v_choices), 'paused until secret costumes are revealed');
  perform pg_temp.assert_true((select count(*) = 0 from contest_private.ballots),
    'Hidden-costume rejection creates no ballot');
  perform public.admin_set_stage('closed');
  perform pg_temp.expect_error(format('select public.admin_delete_entry(%L::uuid)',
    v_one->>'costume_id'), 'only be deleted while registration is open');
  perform public.admin_set_stage('registration');

  -- statement_timestamp is constant for this DO command, allowing an exact
  -- boundary assertion rather than a sleep or dependence on the wall clock.
  update contest_private.contest set reveal_at = statement_timestamp() where singleton;
  v_public := public.contest_public();
  select item into v_card from jsonb_array_elements(v_public->'costumes') as t(item)
    where item->>'id' = v_secret->>'costume_id';
  perform pg_temp.assert_true(v_card->>'title' = 'MIDNIGHT_PRIVATE_TITLE'
    and v_card->>'title_hidden' = 'false', 'Title reveals at the exact deadline');
  update contest_private.contest set reveal_at = statement_timestamp() - interval '1 second' where singleton;
  v_public := public.contest_public();
  select item into v_card from jsonb_array_elements(v_public->'costumes') as t(item)
    where item->>'id' = v_secret->>'costume_id';
  perform pg_temp.assert_true(v_card->>'title' = 'MIDNIGHT_PRIVATE_TITLE'
    and v_card->>'title_hidden' = 'false', 'Title stays revealed after the deadline');
  v_admin := public.admin_snapshot();
  select item into v_card from jsonb_array_elements(v_admin->'results') as t(item)
    where item->>'id' = v_secret->>'costume_id';
  perform pg_temp.assert_true(v_card->>'title' = 'MIDNIGHT_PRIVATE_TITLE'
    and v_card->>'title_hidden' = 'false', 'Owner hidden status clears after reveal');
  perform public.admin_set_stage('voting');
  perform pg_temp.assert_true(public.submit_ballot('Reveal One', v_choices)->>'accepted' = 'true',
    'Voting works once secret titles are revealed');

  -- Independently test the zero-ballot guard even if a private maintenance change
  -- incorrectly returns the stage to registration. No partial results may be erased.
  update contest_private.contest set stage = 'registration' where singleton;
  perform pg_temp.expect_error(format('select public.admin_delete_entry(%L::uuid)',
    v_one->>'costume_id'), 'cannot be deleted after a ballot');
  perform pg_temp.assert_true((select count(*) = 1 from contest_private.ballots)
    and (select count(*) = 3 from contest_private.votes), 'Deletion rejection preserves full ballot');

  perform set_config('request.jwt.claim.sub', v_other::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_other, 'role', 'authenticated')::text, true);
  perform pg_temp.expect_error(format('select public.admin_delete_entry(%L::uuid)',
    v_secret->>'costume_id'), 'Organizer access required');
  perform pg_temp.expect_error('select public.admin_snapshot()', 'Organizer access required');

  -- Leave a future deadline for actual anonymous/authenticated role checks below.
  update contest_private.contest set reveal_at = statement_timestamp() + interval '1 day' where singleton;
  perform set_config('reveal_test.secret_costume_id', v_secret->>'costume_id', true);
  raise notice 'PASS: secret-title masking, reveal boundary, legacy registration, voting guards, and deletion constraints.';
end;
$$;

set local role anon;
do $$
begin
  if position('MIDNIGHT_PRIVATE_TITLE' in public.contest_public()::text) <> 0
    or position('MIDNIGHT_PRIVATE_TITLE' in public.participant_session('Hidden Guest')::text) <> 0 then
    raise exception 'FAILED: actual anonymous role received a secret title';
  end if;
  begin
    perform public.admin_delete_entry(current_setting('reveal_test.secret_costume_id')::uuid);
    raise exception 'FAILED: anonymous deletion executed';
  exception when insufficient_privilege then null;
  end;
  begin
    perform title from contest_private.costumes;
    raise exception 'FAILED: anonymous role read private costume titles';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

set local role authenticated;
do $$
begin
  if position('MIDNIGHT_PRIVATE_TITLE' in public.contest_public()::text) <> 0 then
    raise exception 'FAILED: authenticated non-owner received public secret title';
  end if;
  begin
    perform public.admin_delete_entry(current_setting('reveal_test.secret_costume_id')::uuid);
    raise exception 'FAILED: authenticated non-owner deletion executed';
  exception when insufficient_privilege then null;
  end;
  perform set_config('request.jwt.claim.sub', current_setting('reveal_test.owner_id'), true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', current_setting('reveal_test.owner_id'), 'role', 'authenticated')::text, true);
  if position('MIDNIGHT_PRIVATE_TITLE' in public.contest_public()::text) <> 0
    or position('MIDNIGHT_PRIVATE_TITLE' in public.admin_snapshot()::text) = 0 then
    raise exception 'FAILED: owner/public secret-title separation';
  end if;
  begin
    perform public.admin_delete_entry(current_setting('reveal_test.secret_costume_id')::uuid);
    raise exception 'FAILED: owner deleted an entry after a ballot';
  exception when raise_exception then
    if position('cannot be deleted after a ballot' in sqlerrm) = 0 then raise; end if;
  end;
  raise notice 'PASS: actual anonymous, non-owner, and owner role privacy/deletion checks.';
end;
$$;
reset role;

rollback;

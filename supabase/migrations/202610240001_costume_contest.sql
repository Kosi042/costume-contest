-- Run once in the Supabase SQL editor, as the project database owner.
-- Browser clients receive only the public RPCs explicitly granted at the end.
-- Guest identity is a name confirmed in the UI, on the honor system. This is not
-- authentication: anyone can use a known name or register multiple different names.
begin;

create schema contest_private;
revoke all on schema contest_private from public, anon, authenticated;

-- Preserve display case, collapse whitespace (including common Unicode spaces),
-- and trim. Equality checks additionally apply lower(); there is no fuzzy matching.
create function contest_private.normalize_name(p_username text)
returns text language sql immutable strict set search_path = '' as $$
  select btrim(regexp_replace(p_username,
    U&'[[:space:]\00A0\1680\2000-\200A\2028\2029\202F\205F\3000\FEFF]+',
    ' ', 'g'));
$$;

create table contest_private.contest (
  singleton boolean primary key default true check (singleton),
  title text not null default 'Midnight Masquerade'
    check (char_length(title) between 1 and 80 and title !~ '[[:cntrl:]]'),
  stage text not null default 'registration'
    check (stage in ('registration', 'voting', 'closed')),
  votes_per_person integer not null default 3 check (votes_per_person = 3)
);
insert into contest_private.contest (singleton) values (true);

-- Provision this table from the SQL editor. No client can appoint an owner.
create table contest_private.owners (
  user_id uuid primary key references auth.users(id) on delete cascade
);

create table contest_private.participants (
  id uuid primary key default gen_random_uuid(),
  username text not null
    check (username = contest_private.normalize_name(username) and char_length(username) between 2 and 32
      and username !~ U&'[\0001-\001F\007F-\009F]'),
  registered_at timestamptz not null default now()
);
create unique index participants_username_lower_key
  on contest_private.participants (lower(username));

create table contest_private.costumes (
  id uuid primary key default gen_random_uuid(),
  participant_id uuid not null unique references contest_private.participants(id),
  title text not null
    check (title = btrim(title) and char_length(title) between 2 and 80
      and title !~ '[[:cntrl:]]'),
  unique (id, participant_id)
);

create table contest_private.ballots (
  participant_id uuid primary key references contest_private.participants(id),
  submitted_at timestamptz not null default now()
);

create table contest_private.votes (
  participant_id uuid not null references contest_private.ballots(participant_id),
  costume_id uuid not null,
  costume_owner_id uuid not null,
  primary key (participant_id, costume_id),
  foreign key (costume_id, costume_owner_id)
    references contest_private.costumes(id, participant_id),
  check (participant_id <> costume_owner_id)
);
create index votes_costume_id_idx on contest_private.votes(costume_id);

-- Defense in depth: there are no permissive RLS policies, table grants, or views.
alter table contest_private.contest enable row level security;
alter table contest_private.owners enable row level security;
alter table contest_private.participants enable row level security;
alter table contest_private.costumes enable row level security;
alter table contest_private.ballots enable row level security;
alter table contest_private.votes enable row level security;
revoke all on all tables in schema contest_private from public, anon, authenticated;
revoke all on all sequences in schema contest_private from public, anon, authenticated;
alter default privileges in schema contest_private revoke all on tables from public, anon, authenticated;
alter default privileges in schema contest_private revoke execute on functions from public, anon, authenticated;

create function contest_private.require_owner()
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists (
    select 1 from contest_private.owners where user_id = auth.uid()
  ) then
    raise exception using errcode = '42501', message = 'Organizer access required.';
  end if;
end;
$$;

create function contest_private.require_name(p_username text)
returns text language plpgsql immutable set search_path = '' as $$
declare
  v_username text := contest_private.normalize_name(p_username);
begin
  -- Reject raw controls first: tabs/newlines are not accepted as name whitespace.
  -- PostgreSQL text cannot contain U+0000; reject the remaining C0/C1 controls.
  if p_username ~ U&'[\0001-\001F\007F-\009F]'
    or v_username is null or char_length(v_username) not between 2 and 32 then
    raise exception using errcode = 'P0001', message = 'Use a name of 2 to 32 characters.';
  end if;
  return v_username;
end;
$$;

create function public.contest_public()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'title', c.title,
    'stage', c.stage,
    'votes_per_person', c.votes_per_person,
    'costumes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', k.id, 'username', p.username, 'title', k.title
      ) order by lower(p.username), k.id)
      from contest_private.costumes k
      join contest_private.participants p on p.id = k.participant_id
    ), '[]'::jsonb)
  ) from contest_private.contest c where c.singleton;
$$;

create function public.participant_session(p_username text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_username text := contest_private.require_name(p_username);
  v_session jsonb;
begin
  select jsonb_build_object(
    'participant_id', p.id,
    'username', p.username,
    'costume_id', k.id,
    'has_voted', exists (
      select 1 from contest_private.ballots b where b.participant_id = p.id
    )
  ) into v_session
  from contest_private.participants p
  join contest_private.costumes k on k.participant_id = p.id
  where lower(p.username) = lower(v_username);
  return coalesce(v_session, jsonb_build_object(
    'participant_id', null, 'username', null, 'costume_id', null, 'has_voted', false
  ));
end;
$$;

create function public.register_participant(p_username text, p_costume text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_username text := contest_private.require_name(p_username);
  v_costume text := btrim(p_costume);
  v_stage text;
  v_participant_id uuid;
begin
  -- Shared contest lock permits simultaneous entries while making stage changes
  -- wait for in-flight registrations/votes. Lock order is contest, then person.
  select stage into v_stage from contest_private.contest where singleton for share;
  if v_stage <> 'registration' then
    raise exception using errcode = 'P0001', message = 'Registration is closed.';
  end if;
  if v_costume is null or char_length(v_costume) not between 2 and 80
    or v_costume ~ '[[:cntrl:]]' then
    raise exception using errcode = 'P0001', message = 'Use a costume name of 2 to 80 characters.';
  end if;

  begin
    insert into contest_private.participants(username)
      values (v_username) returning id into v_participant_id;
  exception when unique_violation then
    raise exception using errcode = 'P0001', message = 'That name is already registered. Confirm it is yours to continue.';
  end;
  insert into contest_private.costumes(participant_id, title)
    values (v_participant_id, v_costume);
  return public.participant_session(v_username);
end;
$$;

create function public.submit_ballot(p_username text, p_costume_ids uuid[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_username text := contest_private.require_name(p_username);
  v_participant_id uuid;
  v_stage text;
  v_valid_count integer;
begin
  select stage into v_stage from contest_private.contest where singleton for share;
  if v_stage <> 'voting' then
    raise exception using errcode = 'P0001', message = 'Voting is not open.';
  end if;
  -- The UI confirmation is an honor-system acknowledgement, not identity proof.
  -- Lock this normalized name's participant so it can submit only one ballot.
  select id into v_participant_id from contest_private.participants
    where lower(username) = lower(v_username) for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'Register your name and costume first.';
  end if;
  if exists (select 1 from contest_private.ballots where participant_id = v_participant_id) then
    raise exception using errcode = 'P0001', message = 'Your ballot has already been submitted.';
  end if;
  if p_costume_ids is null or cardinality(p_costume_ids) <> 3
    or array_ndims(p_costume_ids) <> 1
    or (select count(distinct id) from unnest(p_costume_ids) as t(id)) <> 3 then
    raise exception using errcode = 'P0001', message = 'Choose exactly three different costumes.';
  end if;
  if exists (
    select 1 from contest_private.costumes
    where id = any(p_costume_ids) and participant_id = v_participant_id
  ) then
    raise exception using errcode = 'P0001', message = 'You cannot vote for your own costume.';
  end if;
  select count(*) into v_valid_count from contest_private.costumes
    where id = any(p_costume_ids) and participant_id <> v_participant_id;
  if v_valid_count <> 3 then
    raise exception using errcode = 'P0001', message = 'One or more costumes are unavailable.';
  end if;

  -- Both inserts are part of the same RPC transaction: no partial ballot survives.
  insert into contest_private.ballots(participant_id) values (v_participant_id);
  insert into contest_private.votes(participant_id, costume_id, costume_owner_id)
    select v_participant_id, id, participant_id from contest_private.costumes
    where id = any(p_costume_ids);
  return jsonb_build_object('accepted', true);
end;
$$;

create function public.admin_snapshot()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_snapshot jsonb;
begin
  perform contest_private.require_owner();
  select jsonb_build_object(
    'title', c.title, 'stage', c.stage, 'votes_per_person', c.votes_per_person,
    'registered_count', (select count(*) from contest_private.participants),
    'ballot_count', (select count(*) from contest_private.ballots),
    'results', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ranked.id, 'username', ranked.username,
        'title', ranked.title, 'votes', ranked.vote_count
      ) order by ranked.vote_count desc, lower(ranked.username), ranked.id)
      from (
        select k.id, p.username, k.title, count(v.costume_id) as vote_count
        from contest_private.costumes k
        join contest_private.participants p on p.id = k.participant_id
        left join contest_private.votes v on v.costume_id = k.id
        group by k.id, p.username, k.title
      ) ranked
    ), '[]'::jsonb)
  ) into v_snapshot from contest_private.contest c where c.singleton;
  return v_snapshot;
end;
$$;

create function public.admin_set_stage(p_stage text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_stage text;
begin
  perform contest_private.require_owner();
  if p_stage is null or p_stage not in ('registration', 'voting', 'closed') then
    raise exception using errcode = 'P0001', message = 'Choose registration, voting, or closed.';
  end if;
  select stage into v_stage from contest_private.contest where singleton for update;
  -- Before any ballot, registration may be reopened to correct event setup.
  -- Once ballots exist, entrants are frozen; voting can be closed or resumed.
  if p_stage = 'registration' and exists (select 1 from contest_private.ballots) then
    raise exception using errcode = 'P0001', message = 'Registration cannot reopen after a ballot is submitted.';
  end if;
  if p_stage = 'voting' and (select count(*) from contest_private.costumes) < 4 then
    raise exception using errcode = 'P0001', message = 'At least four costumes are needed for three votes each.';
  end if;
  update contest_private.contest set stage = p_stage where singleton;
  return jsonb_build_object('stage', p_stage);
end;
$$;

create function public.admin_set_title(p_title text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_title text := btrim(p_title);
begin
  perform contest_private.require_owner();
  if v_title is null or char_length(v_title) not between 1 and 80
    or v_title ~ '[[:cntrl:]]' then
    raise exception using errcode = 'P0001', message = 'Use an event title of 1 to 80 characters.';
  end if;
  update contest_private.contest set title = v_title where singleton;
  return jsonb_build_object('title', v_title);
end;
$$;

-- SECURITY DEFINER bypasses RLS deliberately, only through the checked RPCs.
-- Remove PUBLIC's automatic function execute privilege before narrow grants.
revoke all on all functions in schema contest_private from public, anon, authenticated;
revoke all on function public.contest_public() from public, anon, authenticated;
revoke all on function public.participant_session(text) from public, anon, authenticated;
revoke all on function public.register_participant(text, text) from public, anon, authenticated;
revoke all on function public.submit_ballot(text, uuid[]) from public, anon, authenticated;
revoke all on function public.admin_snapshot() from public, anon, authenticated;
revoke all on function public.admin_set_stage(text) from public, anon, authenticated;
revoke all on function public.admin_set_title(text) from public, anon, authenticated;

grant execute on function public.contest_public() to anon, authenticated;
grant execute on function public.participant_session(text) to anon, authenticated;
grant execute on function public.register_participant(text, text) to anon, authenticated;
grant execute on function public.submit_ballot(text, uuid[]) to anon, authenticated;
grant execute on function public.admin_snapshot() to authenticated;
grant execute on function public.admin_set_stage(text) to authenticated;
grant execute on function public.admin_set_title(text) to authenticated;

commit;

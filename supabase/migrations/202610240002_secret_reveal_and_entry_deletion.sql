-- Apply after 202610240001_costume_contest.sql, as the database project owner.
-- 31 October 2026, 20:00 Europe/Budapest (CET) is 19:00 UTC.
-- Titles reveal when read after this instant; no scheduled job is required.
begin;

alter table contest_private.contest
  add column reveal_at timestamptz not null
    default timestamptz '2026-10-31 19:00:00+00';

alter table contest_private.costumes
  add column hide_until_reveal boolean not null default false;

create or replace function public.contest_public()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'title', c.title,
    'stage', c.stage,
    'votes_per_person', c.votes_per_person,
    'reveal_at', c.reveal_at,
    'server_time', statement_timestamp(),
    'costumes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', k.id,
        'username', p.username,
        -- Name-only identity cannot prove ownership. Mask for every public caller,
        -- including a caller using the entrant's name or an organizer's JWT.
        'title', case when k.hide_until_reveal and statement_timestamp() < c.reveal_at
          then 'Secret costume' else k.title end,
        'title_hidden', k.hide_until_reveal and statement_timestamp() < c.reveal_at
      ) order by lower(p.username), k.id)
      from contest_private.costumes k
      join contest_private.participants p on p.id = k.participant_id
    ), '[]'::jsonb)
  ) from contest_private.contest c where c.singleton;
$$;

-- Remove the old overload explicitly. The new default keeps old two-argument
-- clients working while exposing exactly one registration signature to PostgREST.
drop function public.register_participant(text, text);
create function public.register_participant(
  p_username text,
  p_costume text,
  p_hide_until_reveal boolean default false
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_username text := contest_private.require_name(p_username);
  v_costume text := btrim(p_costume);
  v_stage text;
  v_participant_id uuid;
begin
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
  insert into contest_private.costumes(participant_id, title, hide_until_reveal)
    values (v_participant_id, v_costume, coalesce(p_hide_until_reveal, false));

  -- participant_session returns only IDs, name, and ballot status: never a title.
  return public.participant_session(v_username);
end;
$$;

create or replace function public.admin_snapshot()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_snapshot jsonb;
begin
  perform contest_private.require_owner();
  select jsonb_build_object(
    'title', c.title, 'stage', c.stage, 'votes_per_person', c.votes_per_person,
    'reveal_at', c.reveal_at, 'server_time', statement_timestamp(),
    'registered_count', (select count(*) from contest_private.participants),
    'ballot_count', (select count(*) from contest_private.ballots),
    'results', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ranked.id, 'username', ranked.username,
        'title', ranked.title, 'votes', ranked.vote_count,
        'title_hidden', ranked.hide_until_reveal and statement_timestamp() < c.reveal_at
      ) order by ranked.vote_count desc, lower(ranked.username), ranked.id)
      from (
        select k.id, p.username, k.title, k.hide_until_reveal, count(v.costume_id) as vote_count
        from contest_private.costumes k
        join contest_private.participants p on p.id = k.participant_id
        left join contest_private.votes v on v.costume_id = k.id
        group by k.id, p.username, k.title, k.hide_until_reveal
      ) ranked
    ), '[]'::jsonb)
  ) into v_snapshot from contest_private.contest c where c.singleton;
  return v_snapshot;
end;
$$;

create or replace function public.admin_set_stage(p_stage text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_stage text;
  v_reveal_at timestamptz;
begin
  perform contest_private.require_owner();
  if p_stage is null or p_stage not in ('registration', 'voting', 'closed') then
    raise exception using errcode = 'P0001', message = 'Choose registration, voting, or closed.';
  end if;
  select stage, reveal_at into v_stage, v_reveal_at
    from contest_private.contest where singleton for update;
  if p_stage = 'registration' and exists (select 1 from contest_private.ballots) then
    raise exception using errcode = 'P0001', message = 'Registration cannot reopen after a ballot is submitted.';
  end if;
  if p_stage = 'voting' and (select count(*) from contest_private.costumes) < 4 then
    raise exception using errcode = 'P0001', message = 'At least four costumes are needed for three votes each.';
  end if;
  if p_stage = 'voting' and statement_timestamp() < v_reveal_at
    and exists (select 1 from contest_private.costumes where hide_until_reveal) then
    raise exception using errcode = 'P0001', message = 'Voting cannot open while secret costumes are hidden.';
  end if;
  update contest_private.contest set stage = p_stage where singleton;
  return jsonb_build_object('stage', p_stage);
end;
$$;

create or replace function public.submit_ballot(p_username text, p_costume_ids uuid[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_username text := contest_private.require_name(p_username);
  v_participant_id uuid;
  v_stage text;
  v_reveal_at timestamptz;
  v_valid_count integer;
begin
  select stage, reveal_at into v_stage, v_reveal_at
    from contest_private.contest where singleton for share;
  if v_stage <> 'voting' then
    raise exception using errcode = 'P0001', message = 'Voting is not open.';
  end if;
  -- Also protect a voting stage created before a private deadline/flag change.
  if statement_timestamp() < v_reveal_at
    and exists (select 1 from contest_private.costumes where hide_until_reveal) then
    raise exception using errcode = 'P0001', message = 'Voting is paused until secret costumes are revealed.';
  end if;
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
  insert into contest_private.ballots(participant_id) values (v_participant_id);
  insert into contest_private.votes(participant_id, costume_id, costume_owner_id)
    select v_participant_id, id, participant_id from contest_private.costumes
    where id = any(p_costume_ids);
  return jsonb_build_object('accepted', true);
end;
$$;

create function public.admin_delete_entry(p_costume_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_stage text;
  v_participant_id uuid;
begin
  perform contest_private.require_owner();
  -- Exclusive contest lock serializes deletion with registrations, ballots,
  -- and phase changes. No cascade or partial-ballot cleanup is allowed here.
  select stage into v_stage from contest_private.contest where singleton for update;
  if v_stage <> 'registration' then
    raise exception using errcode = 'P0001', message = 'Entries can only be deleted while registration is open.';
  end if;
  if exists (select 1 from contest_private.ballots) then
    raise exception using errcode = 'P0001', message = 'Entries cannot be deleted after a ballot has been submitted.';
  end if;
  select participant_id into v_participant_id from contest_private.costumes
    where id = p_costume_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'That entry no longer exists.';
  end if;
  delete from contest_private.costumes where id = p_costume_id;
  delete from contest_private.participants where id = v_participant_id;
  return jsonb_build_object('deleted', true);
end;
$$;

-- CREATE OR REPLACE preserves prior grants, but state every new/changed API grant
-- explicitly. The new registration signature and deletion start with no PUBLIC access.
revoke all on function public.contest_public() from public, anon, authenticated;
revoke all on function public.register_participant(text, text, boolean) from public, anon, authenticated;
revoke all on function public.admin_snapshot() from public, anon, authenticated;
revoke all on function public.admin_set_stage(text) from public, anon, authenticated;
revoke all on function public.submit_ballot(text, uuid[]) from public, anon, authenticated;
revoke all on function public.admin_delete_entry(uuid) from public, anon, authenticated;
grant execute on function public.contest_public() to anon, authenticated;
grant execute on function public.register_participant(text, text, boolean) to anon, authenticated;
grant execute on function public.submit_ballot(text, uuid[]) to anon, authenticated;
grant execute on function public.admin_snapshot() to authenticated;
grant execute on function public.admin_set_stage(text) to authenticated;
grant execute on function public.admin_delete_entry(uuid) to authenticated;

notify pgrst, 'reload schema';
commit;

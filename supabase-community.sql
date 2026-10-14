-- MEDIA STORAGE FIX:
-- If poll tables already exist but image/video uploads fail, copy this whole
-- block into the Supabase SQL Editor and run it. It is safe to run again.
begin;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'community-poll-media',
  'community-poll-media',
  true,
  52428800,
  array[
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
    'video/mp4',
    'video/webm',
    'video/quicktime'
  ]
)
on conflict (id) do update
set name = excluded.name,
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Anyone can view community poll media"
  on storage.objects;
create policy "Anyone can view community poll media"
  on storage.objects for select
  to public
  using (bucket_id = 'community-poll-media');

drop policy if exists "Users can upload their own poll media"
  on storage.objects;
create policy "Users can upload their own poll media"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'community-poll-media'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Users can remove their own poll media"
  on storage.objects;
create policy "Users can remove their own poll media"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'community-poll-media'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

commit;

-- Confirm the bucket exists after running the block above.
select id, name, public, file_size_limit
from storage.buckets
where id = 'community-poll-media';

begin;

create or replace function public.valid_community_poll_options(p_options jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when pg_catalog.jsonb_typeof(p_options) <> 'array' then false
    else
      pg_catalog.jsonb_array_length(p_options) between 2 and 6
      and not exists (
        select 1
        from pg_catalog.jsonb_array_elements(p_options) as answer(value)
        where pg_catalog.jsonb_typeof(answer.value) <> 'string'
          or pg_catalog.char_length(pg_catalog.btrim(answer.value #>> '{}')) not between 1 and 80
      )
      and (
        select pg_catalog.count(distinct pg_catalog.lower(pg_catalog.btrim(answer.value #>> '{}')))
        from pg_catalog.jsonb_array_elements(p_options) as answer(value)
      ) = pg_catalog.jsonb_array_length(p_options)
  end;
$$;

revoke all on function public.valid_community_poll_options(jsonb) from public;
grant execute on function public.valid_community_poll_options(jsonb) to authenticated;

create table if not exists public.community_nickname_counter (
  id boolean primary key default true check (id),
  next_number bigint not null check (next_number > 0)
);
alter table public.community_nickname_counter enable row level security;
revoke all on table public.community_nickname_counter
  from public, anon, authenticated;

create table if not exists public.community_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null unique,
  is_avenger boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.community_profiles enable row level security;
revoke all on table public.community_profiles from public, anon, authenticated;
drop policy if exists "Users can read their own fan nickname"
  on public.community_profiles;
create policy "Users can read their own fan nickname"
  on public.community_profiles for select
  to authenticated
  using (user_id = (select auth.uid()));

grant select (user_id, nickname, is_avenger)
  on public.community_profiles to authenticated;

insert into public.community_nickname_counter as counter (id, next_number)
select true, count(*) + 1 from auth.users
on conflict (id) do update
set next_number = greatest(
  counter.next_number,
  excluded.next_number
);

create or replace function public.make_community_nickname(
  p_account_number bigint
)
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  heroes text[] := array[
    'Hulk',
    'Thor',
    'IronMan',
    'CaptainAmerica',
    'BlackWidow',
    'Hawkeye'
  ];
  adjectives text[] := array[
    'Cosmic',
    'Mighty',
    'Stellar',
    'Fearless',
    'Quantum',
    'Radiant',
    'Vibrant',
    'Valiant',
    'Amazing',
    'Galactic'
  ];
  companions text[] := array[
    'Panda',
    'Comet',
    'Raccoon',
    'Phoenix',
    'Meteor',
    'Tiger',
    'Dragon',
    'Falcon',
    'Star',
    'Rocket'
  ];
  account_tag text := pg_catalog.lpad(p_account_number::text, 4, '0');
begin
  if p_account_number % 20 = 0 then
    return heroes[1 + pg_catalog.floor(pg_catalog.random() * pg_catalog.array_length(heroes, 1))::integer]
      || '-' || account_tag;
  end if;

  return adjectives[1 + pg_catalog.floor(pg_catalog.random() * pg_catalog.array_length(adjectives, 1))::integer]
    || companions[1 + pg_catalog.floor(pg_catalog.random() * pg_catalog.array_length(companions, 1))::integer]
    || '-' || account_tag;
end;
$$;

revoke all on function public.make_community_nickname(bigint) from public;

with numbered_users as (
  select
    id,
    pg_catalog.row_number() over (order by created_at, id) as account_number
  from auth.users
)
insert into public.community_profiles (user_id, nickname, is_avenger)
select
  id,
  public.make_community_nickname(account_number),
  account_number % 20 = 0
from numbered_users
on conflict (user_id) do nothing;

create or replace function public.assign_community_nickname()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  account_number bigint;
begin
  update public.community_nickname_counter
    set next_number = next_number + 1
    where id = true
    returning next_number - 1 into account_number;

  if account_number is null then
    raise exception 'Could not assign a community nickname';
  end if;

  insert into public.community_profiles (user_id, nickname, is_avenger)
  values (
    new.id,
    public.make_community_nickname(account_number),
    account_number % 20 = 0
  );
  return new;
end;
$$;

revoke all on function public.assign_community_nickname() from public;
drop trigger if exists assign_community_nickname on auth.users;
create trigger assign_community_nickname
  after insert on auth.users
  for each row execute function public.assign_community_nickname();

create table if not exists public.community_polls (
  id uuid primary key default gen_random_uuid(),
  question text not null check (char_length(btrim(question)) between 5 and 200),
  options jsonb not null check (public.valid_community_poll_options(options)),
  poll_type text not null default 'community',
  created_by uuid not null references auth.users(id) on delete cascade,
  author_nickname text not null default 'Marvel Fan',
  media_path text,
  media_type text check (media_type is null or media_type in ('image', 'video')),
  created_at timestamptz not null default now(),
  constraint community_polls_media_pair check (
    (media_path is null and media_type is null)
    or (media_path is not null and media_type is not null)
  ),
  constraint community_polls_type_check check (poll_type in ('war', 'community')),
  constraint community_polls_war_options_check check (
    poll_type <> 'war' or jsonb_array_length(options) = 2
  )
);

alter table public.community_polls
  add column if not exists author_nickname text not null default 'Marvel Fan';
alter table public.community_polls
  add column if not exists poll_type text not null default 'community';

do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.community_polls'::regclass
      and conname = 'community_polls_type_check'
  ) then
    alter table public.community_polls
      add constraint community_polls_type_check
      check (poll_type in ('war', 'community'));
  end if;
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.community_polls'::regclass
      and conname = 'community_polls_war_options_check'
  ) then
    alter table public.community_polls
      add constraint community_polls_war_options_check
      check (poll_type <> 'war' or jsonb_array_length(options) = 2);
  end if;
end;
$$;

update public.community_polls as polls
set author_nickname = profiles.nickname
from public.community_profiles as profiles
where polls.created_by = profiles.user_id
  and polls.author_nickname = 'Marvel Fan';

create or replace function public.set_community_poll_author()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select profiles.nickname
    into new.author_nickname
    from public.community_profiles as profiles
    where profiles.user_id = new.created_by;

  if new.author_nickname is null then
    raise exception 'Could not find the poll author nickname';
  end if;

  return new;
end;
$$;

revoke all on function public.set_community_poll_author() from public;
drop trigger if exists set_community_poll_author on public.community_polls;
create trigger set_community_poll_author
  before insert on public.community_polls
  for each row execute function public.set_community_poll_author();

create table if not exists public.community_poll_votes (
  poll_id uuid not null references public.community_polls(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  option_index smallint not null check (option_index >= 0),
  created_at timestamptz not null default now(),
  primary key (poll_id, user_id)
);

create table if not exists public.community_poll_reports (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.community_polls(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check (
    reason in ('inappropriate_media', 'harassment', 'spam', 'other')
  ),
  details text check (details is null or char_length(details) <= 500),
  created_at timestamptz not null default now(),
  unique (poll_id, reporter_id)
);

create index if not exists community_polls_created_at_idx
  on public.community_polls (created_at desc);

create or replace function public.validate_community_poll_vote()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  option_count integer;
begin
  select pg_catalog.jsonb_array_length(p.options)
    into option_count
    from public.community_polls as p
    where p.id = new.poll_id;

  if option_count is null or new.option_index >= option_count then
    raise exception 'Selected poll option does not exist';
  end if;

  return new;
end;
$$;

drop trigger if exists community_poll_vote_option_check
  on public.community_poll_votes;
create trigger community_poll_vote_option_check
  before insert on public.community_poll_votes
  for each row execute function public.validate_community_poll_vote();
revoke all on function public.validate_community_poll_vote() from public;

alter table public.community_polls enable row level security;
alter table public.community_poll_votes enable row level security;
alter table public.community_poll_reports enable row level security;
revoke all on table public.community_polls, public.community_poll_votes, public.community_poll_reports
  from public, anon, authenticated;

drop policy if exists "Anyone can read community polls"
  on public.community_polls;
create policy "Anyone can read community polls"
  on public.community_polls for select
  to anon, authenticated
  using (true);

drop policy if exists "Signed-in users can create polls"
  on public.community_polls;
create policy "Signed-in users can create polls"
  on public.community_polls for insert
  to authenticated
  with check (created_by = (select auth.uid()));

drop policy if exists "Signed-in users can cast one vote"
  on public.community_poll_votes;
create policy "Signed-in users can cast one vote"
  on public.community_poll_votes for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Signed-in users can report polls"
  on public.community_poll_reports;
create policy "Signed-in users can report polls"
  on public.community_poll_reports for insert
  to authenticated
  with check (reporter_id = (select auth.uid()));

grant select (id, question, options, poll_type, author_nickname, media_path, media_type, created_at)
  on public.community_polls to anon, authenticated;
grant insert (question, options, poll_type, created_by, media_path, media_type)
  on public.community_polls to authenticated;
grant insert (poll_id, user_id, option_index)
  on public.community_poll_votes to authenticated;
grant insert (poll_id, reporter_id, reason, details)
  on public.community_poll_reports to authenticated;

create or replace function public.get_community_poll_results(p_poll_ids uuid[])
returns table (
  poll_id uuid,
  option_index integer,
  vote_count bigint,
  viewer_option_index integer
)
language sql
stable
security definer
set search_path = ''
as $$
  with poll_options as (
    select p.id as poll_id, answer.option_index::integer as option_index
    from public.community_polls as p
    cross join lateral pg_catalog.generate_series(
      0,
      pg_catalog.jsonb_array_length(p.options) - 1
    ) as answer(option_index)
    where p.id = any(coalesce(p_poll_ids, '{}'::uuid[]))
  ),
  vote_counts as (
    select options.poll_id, options.option_index, count(votes.poll_id)::bigint as vote_count
    from poll_options as options
    left join public.community_poll_votes as votes
      on votes.poll_id = options.poll_id
      and votes.option_index = options.option_index
    group by options.poll_id, options.option_index
  ),
  viewer_votes as (
    select votes.poll_id, votes.option_index::integer as option_index
    from public.community_poll_votes as votes
    where votes.user_id = auth.uid()
      and votes.poll_id = any(coalesce(p_poll_ids, '{}'::uuid[]))
  )
  select counts.poll_id, counts.option_index, counts.vote_count, viewer.option_index
  from vote_counts as counts
  left join viewer_votes as viewer on viewer.poll_id = counts.poll_id
  order by counts.poll_id, counts.option_index;
$$;

revoke all on function public.get_community_poll_results(uuid[]) from public;
grant execute on function public.get_community_poll_results(uuid[])
  to anon, authenticated;

commit;

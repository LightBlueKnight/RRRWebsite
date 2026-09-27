-- ============================================================
-- Red Rock Robotics — Supabase schema (plan/review stage)
-- Run this in Supabase: Project → SQL Editor → New query → Run
--
-- ACCOUNTS ARE USERNAME + PASSWORD + CODE ONLY.
-- Supabase Auth requires an email internally — the sign-up page
-- will silently generate one like "username@members.redrockrobotics.local"
-- so the user never sees or types an email themselves.
-- ============================================================

create extension if not exists pgcrypto;   -- needed to hash the signup codes

-- 1. PROFILES — extends Supabase's built-in auth.users with a role
create table profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  username    text unique not null,
  role        text not null default 'pending',  -- 'pending' | 'member' | 'admin' | 'parent'
  created_at  timestamptz not null default now()
);

alter table profiles add constraint profiles_role_check
  check (role in ('pending','member','admin','parent'));

-- auto-create a bare profile row whenever an auth account is created
-- (username + role get filled in right after, by finalize_signup below)
create function handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, username)
  values (new.id, new.id::text);  -- pending placeholder, replaced by a validated signup/access function
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();


-- 1b. SIGNUP_CODES — the member code and admin code, stored hashed.
-- Only ever touched by the two functions below (SECURITY DEFINER),
-- never directly readable by client code — set/rotate these yourself
-- from the Supabase table editor.
create table signup_codes (
  id         uuid primary key default gen_random_uuid(),
  role       text not null check (role in ('member','admin')),
  code_hash  text not null,
  label      text,
  created_at timestamptz not null default now()
);

-- no RLS policies granted on signup_codes at all = nobody can
-- select/insert/update it via the client API, by default-deny.
alter table signup_codes enable row level security;

-- helper to insert a new code — run manually in the SQL editor, e.g.:
--   select set_signup_code('member', 'rr-member-2026');
--   select set_signup_code('admin',  'rr-admin-2026');
create function set_signup_code(p_role text, p_plain_code text)
returns void as $$
begin
  if auth.uid() is not null then
    -- This function is intended for trusted SQL-editor/service-role use.
    raise exception 'operator-only function';
  end if;
  if p_role not in ('member','admin','parent') then
    raise exception 'invalid signup role';
  end if;
  if p_plain_code is null or length(trim(p_plain_code)) < 8 then
    raise exception 'signup code must be at least 8 characters';
  end if;

  delete from signup_codes where role = p_role;  -- one active code per role
  insert into signup_codes (role, code_hash, label)
  values (p_role, crypt(p_plain_code, gen_salt('bf')), p_role || ' code');
end;
$$ language plpgsql security definer set search_path = public;

-- This is an operator/setup function. It must never be callable through the
-- public Supabase API, or a client could rotate its own access codes.
revoke all on function set_signup_code(text, text) from public;


-- validate_signup_code: callable by anyone (even logged-out), BEFORE
-- an account is created, just to confirm the code is real and tell
-- the sign-up form which role it grants. Does not touch profiles.
create function validate_signup_code(p_code text)
returns text as $$
declare
  matched_role text;
begin
  select role into matched_role
  from signup_codes
  where code_hash = crypt(p_code, code_hash)
  limit 1;

  if matched_role is null then
    raise exception 'invalid code';
  end if;

  return matched_role;
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function validate_signup_code(text) to anon, authenticated;


-- finalize_signup: called right after auth.signUp succeeds (client is
-- now authenticated as the brand-new user). Re-checks the code and
-- sets username + role on that user's own profile row only.
create function finalize_signup(p_username text, p_code text)
returns text as $$
declare
  matched_role text;
begin
  if (select coalesce(is_anonymous, false) from auth.users where id = auth.uid()) then
    raise exception 'permanent account required';
  end if;

  select role into matched_role
  from signup_codes
  where code_hash = crypt(p_code, code_hash)
  limit 1;

  if matched_role is null then
    raise exception 'invalid code';
  end if;

  update profiles
  set username = p_username, role = matched_role
  where id = auth.uid();

  return matched_role;
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function finalize_signup(text, text) to authenticated;


-- 1c. PARENT ACCESS — lighter than member/admin: no username/password,
-- just a code that starts an anonymous session tagged role='parent'.
-- (Client calls supabase.auth.signInAnonymously() first, THEN this.)
create function grant_parent_access(p_code text)
returns text as $$
declare
  matched_role text;
  is_anon boolean;
begin
  select coalesce(is_anonymous, false) into is_anon
  from auth.users
  where id = auth.uid();

  if auth.uid() is null or not is_anon then
    raise exception 'anonymous parent session required';
  end if;

  select role into matched_role
  from signup_codes
  where role = 'parent' and code_hash = crypt(p_code, code_hash)
  limit 1;

  if matched_role is null then
    raise exception 'invalid code';
  end if;

  update profiles set role = 'parent' where id = auth.uid();
  return matched_role;
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function grant_parent_access(text) to anon, authenticated;

-- set the parent code the same way as the others, e.g.:
--   select set_signup_code('parent', 'rr-parent-2026');
-- (signup_codes.role check already allows 'member' | 'admin' — extend it:)
alter table signup_codes drop constraint signup_codes_role_check;
alter table signup_codes add constraint signup_codes_role_check
  check (role in ('member','admin','parent'));


-- 2. TUTORIALS — the editor-created pages (video + text + code)
create table tutorials (
  id          uuid primary key default gen_random_uuid(),
  slug        text unique not null,          -- used in the URL, e.g. "autonomous-basics"
  subteam     text not null,                 -- 'software' | 'hardware' | 'electrical' | 'strategy' | 'hpr'
  title       text not null,
  summary     text,
  video_url   text,                          -- YouTube embed URL
  body        text,                          -- prose / overview section
  code_blocks jsonb not null default '[]',   -- [{ "filename": "...", "language": "...", "code": "..." }]
  published   boolean not null default false,
  created_by  uuid references profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);


-- 3. DOC_LINKS — simple external-link cards (Team Manual, part catalogs, etc.)
create table doc_links (
  id          uuid primary key default gen_random_uuid(),
  subteam     text not null,
  title       text not null,
  description text,
  url         text not null,
  locked      boolean not null default false, -- true = members/admins only (e.g. Team Drive)
  created_by  uuid references profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);


-- 4. MEAL_SIGNUPS — the parent food-volunteer calendar.
-- One row per claimed day; "event_date unique" is what makes an
-- already-claimed day show as full instead of letting a second
-- parent double-book it.
create table meal_signups (
  id               uuid primary key default gen_random_uuid(),
  event_date       date unique not null,
  parent_name      text not null,
  food_description text not null,
  vegetarian       boolean not null default false,
  created_by       uuid references profiles(id) on delete set null,
  created_at       timestamptz not null default now()
);

-- ============================================================
-- AUTHORIZATION HELPERS
-- ============================================================
-- Anonymous Supabase Auth users use the PostgreSQL 'authenticated' role too.
-- Never use auth.role() alone as a proxy for application membership.
create function current_app_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;
revoke all on function current_app_role() from public;
grant execute on function current_app_role() to anon, authenticated;

-- ============================================================
-- ROW LEVEL SECURITY — makes "admin-only editing" actually real,
-- not just hidden in the UI.
-- ============================================================

alter table profiles enable row level security;
alter table tutorials enable row level security;
alter table doc_links enable row level security;
alter table meal_signups enable row level security;

-- profiles: anyone signed in can read (needed to show usernames, check admin
-- status, etc). Nobody can write to profiles directly through the client —
-- username + role are only ever set by finalize_signup() above, so an
-- account can't forge its own admin status by editing its row.
create policy "read own profile or all profiles as admin"
  on profiles for select
  using (id = auth.uid() or current_app_role() = 'admin');

-- tutorials: signed-in users read published ones; admins read/write everything
create policy "read published tutorials"
  on tutorials for select
  using (published = true or current_app_role() in ('member','admin'));

create policy "admins insert tutorials"
  on tutorials for insert
  with check (
    exists (select 1 from profiles where id = auth.uid() and role = 'admin')
  );

create policy "admins update tutorials"
  on tutorials for update
  using (
    exists (select 1 from profiles where id = auth.uid() and role = 'admin')
  );

create policy "admins delete tutorials"
  on tutorials for delete
  using (
    exists (select 1 from profiles where id = auth.uid() and role = 'admin')
  );

-- doc_links: same pattern
create policy "members and admins read doc links"
  on doc_links for select
  using (current_app_role() in ('member','admin'));

create policy "admins manage doc links"
  on doc_links for all
  using (
    exists (select 1 from profiles where id = auth.uid() and role = 'admin')
  );

-- meal_signups: anyone signed in (member/parent/admin) can view the
-- calendar. Only parents/admins can claim a day. A parent can edit or
-- remove their own signup; admins can edit/remove any.
create policy "read meal signups when signed in"
  on meal_signups for select
  using (current_app_role() in ('member','admin','parent'));

create policy "parents and admins claim a day"
  on meal_signups for insert
  with check (
    exists (select 1 from profiles where id = auth.uid() and role in ('parent','admin'))
  );

create policy "creator or admin edits a signup"
  on meal_signups for update
  using (
    created_by = auth.uid()
    or exists (select 1 from profiles where id = auth.uid() and role = 'admin')
  );

create policy "creator or admin removes a signup"
  on meal_signups for delete
  using (
    created_by = auth.uid()
    or exists (select 1 from profiles where id = auth.uid() and role = 'admin')
  );

-- ============================================================
-- SETUP CHECKLIST (run once, in this order):
--
-- 1. Run this whole file in the SQL editor.
-- 2. Set your three real codes (pick your own values):
--      select set_signup_code('member', 'rr-member-2026');
--      select set_signup_code('admin',  'rr-admin-2026');
--      select set_signup_code('parent', 'rr-parent-2026');
-- 3. Sign up through the site once, using the admin code —
--    that account is now an admin automatically, no manual
--    promotion step needed.
-- 4. Rotate any code any time by re-running set_signup_code —
--    it replaces the old one, old codes stop working immediately.
-- ============================================================


-- ============================================================
-- Red Rock Robotics — Migration 2
-- ------------------------------------------------------------
-- Run this ONCE in Supabase → SQL Editor, on your EXISTING
-- project. It only ADDS new tables/policies — nothing from
-- schema.sql is touched or re-run, so your current accounts,
-- tutorials, and meal signups are untouched.
-- ============================================================

-- ============================================================
-- 1. ASSIGNMENTS (software section) + FILE SUBMISSIONS
-- ============================================================

create table assignments (
  id          uuid primary key default gen_random_uuid(),
  subteam     text not null default 'software',
  title       text not null,
  description text,
  due_date    date,
  created_by  uuid references profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);

alter table assignments enable row level security;

create policy "members and admins read assignments"
  on assignments for select
  using (current_app_role() in ('member','admin'));

create policy "admins manage assignments"
  on assignments for all
  using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));


create table assignment_submissions (
  id            uuid primary key default gen_random_uuid(),
  assignment_id uuid references assignments(id) on delete cascade,
  member_id     uuid references profiles(id) on delete cascade,
  file_path     text not null,   -- path inside the 'assignment-submissions' storage bucket
  file_name     text not null,
  submitted_at  timestamptz not null default now(),
  unique (assignment_id, member_id)  -- one active submission per member per assignment (resubmitting replaces it)
);

alter table assignment_submissions enable row level security;

create policy "members read own submissions, admins read all"
  on assignment_submissions for select
  using (
    member_id = auth.uid()
    or exists (select 1 from profiles where id = auth.uid() and role = 'admin')
  );

create policy "members submit their own work"
  on assignment_submissions for insert
  with check (member_id = auth.uid() and current_app_role() in ('member','admin'));

create policy "members replace their own submission"
  on assignment_submissions for update
  using (member_id = auth.uid() and current_app_role() in ('member','admin'))
  with check (member_id = auth.uid() and current_app_role() in ('member','admin'));

create policy "member or admin deletes a submission"
  on assignment_submissions for delete
  using (
    current_app_role() in ('member','admin')
    and (
      member_id = auth.uid()
      or current_app_role() = 'admin'
    )
  );

-- Storage bucket for uploaded files (private — not publicly browsable).
-- File path convention used by the site: {user_id}/{assignment_id}/{filename}
insert into storage.buckets (id, name, public)
values ('assignment-submissions', 'assignment-submissions', false)
on conflict (id) do nothing;

create policy "members upload into their own folder"
  on storage.objects for insert
  with check (
    bucket_id = 'assignment-submissions'
    and current_app_role() in ('member','admin')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "members replace their own files"
  on storage.objects for update
  using (
    bucket_id = 'assignment-submissions'
    and current_app_role() in ('member','admin')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "owner or admin reads submission files"
  on storage.objects for select
  using (
    bucket_id = 'assignment-submissions'
    and current_app_role() in ('member','admin')
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or exists (select 1 from profiles where id = auth.uid() and role = 'admin')
    )
  );

create policy "owner or admin deletes submission files"
  on storage.objects for delete
  using (
    bucket_id = 'assignment-submissions'
    and current_app_role() in ('member','admin')
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or exists (select 1 from profiles where id = auth.uid() and role = 'admin')
    )
  );


-- ============================================================
-- 2. QUIZZES — embedded Google Forms (not a built quiz engine;
-- Google collects/scores responses on its end, this table just
-- stores which form belongs to which subteam)
-- ============================================================

create table quizzes (
  id          uuid primary key default gen_random_uuid(),
  subteam     text not null default 'software',
  title       text not null,
  description text,
  embed_url   text not null,
  created_by  uuid references profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);

alter table quizzes enable row level security;

create policy "members and admins read quizzes"
  on quizzes for select
  using (current_app_role() in ('member','admin'));

create policy "admins manage quizzes"
  on quizzes for all
  using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));


-- ============================================================
-- 3. PARENT DAY-STACKING — a day can now have a food signup
-- AND any number of "resource requests" (things the team needs
-- that day), each with its own volunteer slots.
-- ============================================================

create table day_resource_requests (
  id           uuid primary key default gen_random_uuid(),
  event_date   date not null,
  title        text not null,
  description  text,
  slots_needed int not null default 1,
  created_by   uuid references profiles(id),
  created_at   timestamptz not null default now()
);

alter table day_resource_requests enable row level security;

create policy "read resource requests when signed in"
  on day_resource_requests for select
  using (current_app_role() in ('member','admin','parent'));

create policy "admins manage resource requests"
  on day_resource_requests for all
  using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));


create table day_resource_volunteers (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid references day_resource_requests(id) on delete cascade,
  parent_name text not null,
  created_by  uuid references profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  unique (request_id, created_by)  -- one signup per parent session per request
);

alter table day_resource_volunteers enable row level security;

create policy "read volunteers when signed in"
  on day_resource_volunteers for select
  using (current_app_role() in ('member','admin','parent'));

create policy "parents and admins volunteer"
  on day_resource_volunteers for insert
  with check (
    exists (select 1 from profiles where id = auth.uid() and role in ('parent','admin'))
  );

create policy "creator or admin removes a volunteer signup"
  on day_resource_volunteers for delete
  using (
    created_by = auth.uid()
    or exists (select 1 from profiles where id = auth.uid() and role = 'admin')
  );


-- ============================================================
-- 4. ADMIN: delete an account
-- (Deletes from auth.users; profiles row cascades automatically
-- since profiles.id references auth.users(id) on delete cascade.)
-- ============================================================

create function admin_delete_account(p_user_id uuid)
returns void as $$
begin
  if not exists (select 1 from profiles where id = auth.uid() and role = 'admin') then
    raise exception 'not authorized';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'cannot delete your own account from here';
  end if;
  delete from auth.users where id = p_user_id;
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function admin_delete_account(uuid) to authenticated;

-- ============================================================
-- SETUP CHECKLIST for this migration:
-- 1. Run this whole file once in the SQL editor.
-- 2. Storage → confirm a bucket named "assignment-submissions"
--    now exists (created automatically by this script) and is
--    marked Private.
-- 3. Nothing else to configure — the site's existing anon key
--    and login flow work unchanged.
-- ============================================================

-- ============================================================
-- Red Rock Robotics — Migration 3
-- ------------------------------------------------------------
-- Run this ONCE, on top of schema.sql + schema-migration-2.sql.
-- Adds:
--   1. day_events        — simple text notes shown on a day
--   2. volunteer_days    — which days parents are allowed to
--                          volunteer on (admin toggles with
--                          shift + right-click on the calendar)
--   3. Tightens meal_signups / day_resource_volunteers so a
--      parent can only claim/volunteer on a day that's open —
--      enforced in the database, not just hidden in the UI.
-- ============================================================

-- ---------- DAY EVENTS ----------
create table day_events (
  id          uuid primary key default gen_random_uuid(),
  event_date  date not null,
  text        text not null,
  created_by  uuid references profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);

alter table day_events enable row level security;

create policy "read day events when signed in"
  on day_events for select
  using (current_app_role() in ('member','admin','parent'));

create policy "admins manage day events"
  on day_events for all
  using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));


-- ---------- VOLUNTEER-OPEN DAYS ----------
-- Presence of a row for a date = parents can volunteer that day.
create table volunteer_days (
  event_date  date primary key,
  created_by  uuid references profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);

alter table volunteer_days enable row level security;

create policy "read volunteer days when signed in"
  on volunteer_days for select
  using (current_app_role() in ('member','admin','parent'));

create policy "admins manage volunteer days"
  on volunteer_days for all
  using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));


-- ---------- TIGHTEN volunteering to open days only ----------
drop policy if exists "parents and admins claim a day" on meal_signups;
create policy "parents and admins claim a day"
  on meal_signups for insert
  with check (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'admin')
    or (
      exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'parent')
      and exists (select 1 from volunteer_days vd where vd.event_date = event_date)
    )
  );

drop policy if exists "parents and admins volunteer" on day_resource_volunteers;
create policy "parents and admins volunteer"
  on day_resource_volunteers for insert
  with check (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'admin')
    or (
      exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'parent')
      and exists (
        select 1 from day_resource_requests r
        join volunteer_days vd on vd.event_date = r.event_date
        where r.id = request_id
      )
    )
  );

-- ============================================================
-- Red Rock Robotics — Migration 4
-- ------------------------------------------------------------
-- Adds a "category" column to assignments, quizzes, and
-- tutorials, so each can be grouped/filtered with a dropdown
-- instead of scrolling through one long list.
-- Run this once, on top of migrations 1-3.
-- ============================================================

alter table assignments add column category text not null default 'General';
alter table quizzes add column category text not null default 'General';
alter table tutorials add column category text not null default 'General';
-- ============================================================
-- Red Rock Robotics — Migration 5
-- ------------------------------------------------------------
-- Adds admin-managed parent announcements with rich HTML content,
-- inline images, and downloadable file attachments.
-- Run once in Supabase SQL Editor after migrations 1–4.
-- ============================================================

-- ---------- ANNOUNCEMENTS ----------
create table announcements (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  body         text not null default '',
  published    boolean not null default false,
  published_at timestamptz,
  created_by   uuid references profiles(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index announcements_published_idx
  on announcements (published, published_at desc, created_at desc);

alter table announcements enable row level security;

create policy "parents and admins read published announcements"
  on announcements for select
  using (
    (published = true and current_app_role() in ('parent','admin'))
    or current_app_role() = 'admin'
  );

create policy "admins manage announcements"
  on announcements for all
  using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'))
  with check (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));


-- ---------- ANNOUNCEMENT ATTACHMENTS ----------
create table announcement_attachments (
  id              uuid primary key default gen_random_uuid(),
  announcement_id uuid not null references announcements(id) on delete cascade,
  storage_path    text not null unique,
  file_name       text not null,
  mime_type       text,
  file_size       bigint,
  is_image        boolean not null default false,
  created_at      timestamptz not null default now()
);

create index announcement_attachments_announcement_idx
  on announcement_attachments (announcement_id, created_at);

alter table announcement_attachments enable row level security;

create policy "read attachments for visible announcements"
  on announcement_attachments for select
  using (
    exists (
      select 1
      from announcements a
      where a.id = announcement_id
        and a.published = true
        and current_app_role() in ('parent','admin')
    )
  );

create policy "admins manage announcement attachments"
  on announcement_attachments for all
  using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'))
  with check (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));


-- ---------- PRIVATE STORAGE BUCKET ----------
-- Announcement images/files are private. Parent/member browsers receive
-- short-lived signed URLs after their authenticated parent session has been
-- granted access.
insert into storage.buckets (id, name, public)
values ('announcement-files', 'announcement-files', false)
on conflict (id) do nothing;

create policy "admins upload announcement files"
  on storage.objects for insert
  with check (
    bucket_id = 'announcement-files'
    and exists (select 1 from profiles where id = auth.uid() and role = 'admin')
  );

create policy "parents and admins read published announcement files"
  on storage.objects for select
  using (
    bucket_id = 'announcement-files'
    and (
      current_app_role() = 'admin'
      or (
        current_app_role() = 'parent'
        and exists (
          select 1
          from public.announcement_attachments aa
          join public.announcements a on a.id = aa.announcement_id
          where aa.storage_path = name
            and a.published = true
        )
      )
    )
  );

create policy "admins update announcement files"
  on storage.objects for update
  using (
    bucket_id = 'announcement-files'
    and exists (select 1 from profiles where id = auth.uid() and role = 'admin')
  )
  with check (
    bucket_id = 'announcement-files'
    and exists (select 1 from profiles where id = auth.uid() and role = 'admin')
  );

create policy "admins delete announcement files"
  on storage.objects for delete
  using (
    bucket_id = 'announcement-files'
    and exists (select 1 from profiles where id = auth.uid() and role = 'admin')
  );

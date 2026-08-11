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
  created_by  uuid references profiles(id),
  created_at  timestamptz not null default now()
);

alter table assignments enable row level security;

create policy "read assignments when signed in"
  on assignments for select
  using (auth.role() = 'authenticated');

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
  with check (member_id = auth.uid());

create policy "members replace their own submission"
  on assignment_submissions for update
  using (member_id = auth.uid());

create policy "member or admin deletes a submission"
  on assignment_submissions for delete
  using (
    member_id = auth.uid()
    or exists (select 1 from profiles where id = auth.uid() and role = 'admin')
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
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "members replace their own files"
  on storage.objects for update
  using (
    bucket_id = 'assignment-submissions'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "owner or admin reads submission files"
  on storage.objects for select
  using (
    bucket_id = 'assignment-submissions'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or exists (select 1 from profiles where id = auth.uid() and role = 'admin')
    )
  );

create policy "owner or admin deletes submission files"
  on storage.objects for delete
  using (
    bucket_id = 'assignment-submissions'
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
  created_by  uuid references profiles(id),
  created_at  timestamptz not null default now()
);

alter table quizzes enable row level security;

create policy "read quizzes when signed in"
  on quizzes for select
  using (auth.role() = 'authenticated');

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
  using (auth.role() = 'authenticated');

create policy "admins manage resource requests"
  on day_resource_requests for all
  using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));


create table day_resource_volunteers (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid references day_resource_requests(id) on delete cascade,
  parent_name text not null,
  created_by  uuid references profiles(id),
  created_at  timestamptz not null default now(),
  unique (request_id, created_by)  -- one signup per parent session per request
);

alter table day_resource_volunteers enable row level security;

create policy "read volunteers when signed in"
  on day_resource_volunteers for select
  using (auth.role() = 'authenticated');

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
$$ language plpgsql security definer;

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

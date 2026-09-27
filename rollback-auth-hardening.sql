-- ============================================================
-- Red Rock Robotics — Rollback: restore original auth/signup behavior
-- ------------------------------------------------------------
-- USE THIS ONLY ON THE EXISTING DATABASE AFTER MIGRATIONS 1-5.
-- It rolls back the changes introduced by migrations 6-7 while
-- PRESERVING the announcement feature from migration 5.
--
-- It restores the original username/password/code signup flow:
--   member/admin signup -> validate code -> auth.signUp -> finalize
--   parent access -> anonymous sign-in -> grant_parent_access
--
-- Before running, make a Supabase database backup if this project
-- contains important production data.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. Restore the original profile role model.
-- ------------------------------------------------------------
-- Remove anonymous/pending profiles created by the hardened system
-- before restoring the original default. This prevents stale anonymous
-- users from becoming member accounts when the original auth guard is
-- restored.
delete from auth.users u
using public.profiles p
where p.id = u.id
  and p.role = 'pending'
  and coalesce(u.is_anonymous, false) = true;

-- Any remaining pending permanent account was created by the hardened
-- signup flow but never finalized. The original system had no pending
-- state, so restore those accounts to the original default member role.
update public.profiles
set role = 'member'
where role = 'pending';

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('member','admin','parent'));
alter table public.profiles alter column role set default 'member';

-- ------------------------------------------------------------
-- 2. Restore the original signup functions.
-- ------------------------------------------------------------
-- pgcrypto is used by the original code. The search_path includes both
-- public and extensions so this works whether Supabase installed pgcrypto
-- in public or in the extensions schema.
create extension if not exists pgcrypto;

create or replace function public.set_signup_code(
  p_role text,
  p_plain_code text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  delete from public.signup_codes where role = p_role;
  insert into public.signup_codes (role, code_hash, label)
  values (
    p_role,
    crypt(p_plain_code, gen_salt('bf')),
    p_role || ' code'
  );
end;
$$;

grant execute on function public.set_signup_code(text, text) to public;

create or replace function public.validate_signup_code(p_code text)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  matched_role text;
begin
  select role into matched_role
  from public.signup_codes
  where code_hash = crypt(p_code, code_hash)
  limit 1;

  if matched_role is null then
    raise exception 'invalid code';
  end if;

  return matched_role;
end;
$$;

grant execute on function public.validate_signup_code(text) to anon, authenticated;

create or replace function public.finalize_signup(
  p_username text,
  p_code text
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  matched_role text;
begin
  select role into matched_role
  from public.signup_codes
  where code_hash = crypt(p_code, code_hash)
  limit 1;

  if matched_role is null then
    raise exception 'invalid code';
  end if;

  update public.profiles
  set username = p_username,
      role = matched_role
  where id = auth.uid();

  return matched_role;
end;
$$;

grant execute on function public.finalize_signup(text, text) to authenticated;

create or replace function public.grant_parent_access(p_code text)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  matched_role text;
begin
  select role into matched_role
  from public.signup_codes
  where role = 'parent'
    and code_hash = crypt(p_code, code_hash)
  limit 1;

  if matched_role is null then
    raise exception 'invalid code';
  end if;

  update public.profiles
  set role = 'parent'
  where id = auth.uid();

  return matched_role;
end;
$$;

grant execute on function public.grant_parent_access(text) to anon, authenticated;

-- Keep signup_codes inaccessible directly. The original system exposed it
-- only through the SECURITY DEFINER functions above.
revoke all on table public.signup_codes from anon, authenticated;

-- The hardened helper is no longer needed once the original policies are
-- restored below.

-- ------------------------------------------------------------
-- 3. Restore the original table policies changed by migrations 6-7.
-- ------------------------------------------------------------

-- PROFILES
 drop policy if exists "read own profile or all profiles as admin" on public.profiles;
 drop policy if exists "read profiles when signed in" on public.profiles;
 create policy "read profiles when signed in"
   on public.profiles for select
   using (auth.role() = 'authenticated');

-- TUTORIALS
 drop policy if exists "read published tutorials" on public.tutorials;
 create policy "read published tutorials"
   on public.tutorials for select
   using (published = true or auth.role() = 'authenticated');

-- DOC LINKS
 drop policy if exists "members and admins read doc links" on public.doc_links;
 drop policy if exists "read doc links when signed in" on public.doc_links;
 create policy "read doc links when signed in"
   on public.doc_links for select
   using (auth.role() = 'authenticated');

-- MEAL SIGNUPS (read policy only; migration 3's volunteer-open-day insert
-- restriction remains intact.)
 drop policy if exists "parents members and admins read meal signups" on public.meal_signups;
 drop policy if exists "read meal signups when signed in" on public.meal_signups;
 create policy "read meal signups when signed in"
   on public.meal_signups for select
   using (auth.role() = 'authenticated');

-- ASSIGNMENTS
 drop policy if exists "members and admins read assignments" on public.assignments;
 drop policy if exists "read assignments when signed in" on public.assignments;
 create policy "read assignments when signed in"
   on public.assignments for select
   using (auth.role() = 'authenticated');

-- QUIZZES
 drop policy if exists "members and admins read quizzes" on public.quizzes;
 drop policy if exists "read quizzes when signed in" on public.quizzes;
 create policy "read quizzes when signed in"
   on public.quizzes for select
   using (auth.role() = 'authenticated');

-- DAY RESOURCE REQUESTS
 drop policy if exists "parents members and admins read resource requests" on public.day_resource_requests;
 drop policy if exists "read resource requests when signed in" on public.day_resource_requests;
 create policy "read resource requests when signed in"
   on public.day_resource_requests for select
   using (auth.role() = 'authenticated');

-- DAY RESOURCE VOLUNTEERS
 drop policy if exists "parents members and admins read volunteers" on public.day_resource_volunteers;
 drop policy if exists "read volunteers when signed in" on public.day_resource_volunteers;
 create policy "read volunteers when signed in"
   on public.day_resource_volunteers for select
   using (auth.role() = 'authenticated');

-- DAY EVENTS
 drop policy if exists "parents members and admins read day events" on public.day_events;
 drop policy if exists "read day events when signed in" on public.day_events;
 create policy "read day events when signed in"
   on public.day_events for select
   using (auth.role() = 'authenticated');

-- VOLUNTEER DAYS
 drop policy if exists "parents members and admins read volunteer days" on public.volunteer_days;
 drop policy if exists "read volunteer days when signed in" on public.volunteer_days;
 create policy "read volunteer days when signed in"
   on public.volunteer_days for select
   using (auth.role() = 'authenticated');

-- ANNOUNCEMENTS: restore migration-5 behavior. The announcements feature
-- remains installed; only migration-6's role restriction is removed.
 drop policy if exists "parents and admins read published announcements" on public.announcements;
 drop policy if exists "parents read published announcements" on public.announcements;
 create policy "parents read published announcements"
   on public.announcements for select
   using (
     published = true
     or exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
   );

-- ANNOUNCEMENT ATTACHMENTS
 drop policy if exists "read attachments for visible announcements" on public.announcement_attachments;
 create policy "read attachments for visible announcements"
   on public.announcement_attachments for select
   using (
     exists (
       select 1
       from public.announcements a
       where a.id = announcement_id
         and (
           a.published = true
           or exists (
             select 1 from public.profiles
             where id = auth.uid() and role = 'admin'
           )
         )
     )
   );

-- ASSIGNMENT SUBMISSIONS
 drop policy if exists "members submit their own work" on public.assignment_submissions;
 create policy "members submit their own work"
   on public.assignment_submissions for insert
   with check (member_id = auth.uid());

 drop policy if exists "members replace their own submission" on public.assignment_submissions;
 create policy "members replace their own submission"
   on public.assignment_submissions for update
   using (member_id = auth.uid());

 drop policy if exists "member or admin deletes a submission" on public.assignment_submissions;
 create policy "member or admin deletes a submission"
   on public.assignment_submissions for delete
   using (
     member_id = auth.uid()
     or exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
   );

-- ------------------------------------------------------------
-- 4. Restore original storage policies.
-- ------------------------------------------------------------

-- Announcement storage
 drop policy if exists "parents and admins read published announcement files" on storage.objects;
 drop policy if exists "authenticated users read announcement files" on storage.objects;
 create policy "authenticated users read announcement files"
   on storage.objects for select
   using (
     bucket_id = 'announcement-files'
     and auth.role() = 'authenticated'
   );

-- Assignment-submission storage
 drop policy if exists "members upload into their own folder" on storage.objects;
 create policy "members upload into their own folder"
   on storage.objects for insert
   with check (
     bucket_id = 'assignment-submissions'
     and (storage.foldername(name))[1] = auth.uid()::text
   );

 drop policy if exists "members replace their own files" on storage.objects;
 create policy "members replace their own files"
   on storage.objects for update
   using (
     bucket_id = 'assignment-submissions'
     and (storage.foldername(name))[1] = auth.uid()::text
   );

 drop policy if exists "owner or admin reads submission files" on storage.objects;
 create policy "owner or admin reads submission files"
   on storage.objects for select
   using (
     bucket_id = 'assignment-submissions'
     and (
       (storage.foldername(name))[1] = auth.uid()::text
       or exists (
         select 1 from public.profiles
         where id = auth.uid() and role = 'admin'
       )
     )
   );

 drop policy if exists "owner or admin deletes submission files" on storage.objects;
 create policy "owner or admin deletes submission files"
   on storage.objects for delete
   using (
     bucket_id = 'assignment-submissions'
     and (
       (storage.foldername(name))[1] = auth.uid()::text
       or exists (
         select 1 from public.profiles
         where id = auth.uid() and role = 'admin'
       )
     )
   );

-- ------------------------------------------------------------
-- 5. Restore the original created_by foreign-key behavior.
--    (Default PostgreSQL behavior = NO ACTION.)
-- ------------------------------------------------------------

alter table public.tutorials drop constraint if exists tutorials_created_by_fkey;
alter table public.tutorials add constraint tutorials_created_by_fkey
  foreign key (created_by) references public.profiles(id);

alter table public.doc_links drop constraint if exists doc_links_created_by_fkey;
alter table public.doc_links add constraint doc_links_created_by_fkey
  foreign key (created_by) references public.profiles(id);

alter table public.meal_signups drop constraint if exists meal_signups_created_by_fkey;
alter table public.meal_signups add constraint meal_signups_created_by_fkey
  foreign key (created_by) references public.profiles(id);

alter table public.assignments drop constraint if exists assignments_created_by_fkey;
alter table public.assignments add constraint assignments_created_by_fkey
  foreign key (created_by) references public.profiles(id);

alter table public.quizzes drop constraint if exists quizzes_created_by_fkey;
alter table public.quizzes add constraint quizzes_created_by_fkey
  foreign key (created_by) references public.profiles(id);

alter table public.day_resource_requests drop constraint if exists day_resource_requests_created_by_fkey;
alter table public.day_resource_requests add constraint day_resource_requests_created_by_fkey
  foreign key (created_by) references public.profiles(id);

alter table public.day_resource_volunteers drop constraint if exists day_resource_volunteers_created_by_fkey;
alter table public.day_resource_volunteers add constraint day_resource_volunteers_created_by_fkey
  foreign key (created_by) references public.profiles(id);

alter table public.day_events drop constraint if exists day_events_created_by_fkey;
alter table public.day_events add constraint day_events_created_by_fkey
  foreign key (created_by) references public.profiles(id);

alter table public.volunteer_days drop constraint if exists volunteer_days_created_by_fkey;
alter table public.volunteer_days add constraint volunteer_days_created_by_fkey
  foreign key (created_by) references public.profiles(id);

alter table public.announcements drop constraint if exists announcements_created_by_fkey;
alter table public.announcements add constraint announcements_created_by_fkey
  foreign key (created_by) references public.profiles(id);

-- ------------------------------------------------------------
-- 6. Remove the hardened role helper.
-- ------------------------------------------------------------
drop function if exists public.current_app_role();

commit;

-- ============================================================
-- AFTER RUNNING THIS SQL
-- ------------------------------------------------------------
-- Supabase Dashboard → Authentication:
--   • Email provider: ON
--   • Confirm email: OFF
--   • Anonymous sign-ins: ON
--
-- Then set the three codes from SQL Editor:
--   select public.set_signup_code('member', 'your-member-code');
--   select public.set_signup_code('admin',  'your-admin-code');
--   select public.set_signup_code('parent', 'your-parent-code');
--
-- Test them:
--   select public.validate_signup_code('your-member-code');
--   select public.validate_signup_code('your-admin-code');
--   select public.validate_signup_code('your-parent-code');
-- ============================================================

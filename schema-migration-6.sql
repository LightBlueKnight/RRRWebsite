-- ============================================================
-- Red Rock Robotics — Migration 6: security + storage hygiene
-- ------------------------------------------------------------
-- Run once after migrations 1–5 on an existing Supabase project.
-- This migration does NOT add new end-user features. It hardens the
-- existing parent/member/admin access model and cleans up storage rules.
-- ============================================================

-- 1. Existing anonymous-auth sessions must never start with the
--    application role 'member'. New Auth users begin as pending until a
--    validated signup/access RPC assigns their final role.
alter table public.profiles alter column role set default 'pending';
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('pending','member','admin','parent'));

-- 2. Central role helper. SECURITY DEFINER prevents the profiles RLS policy
--    from recursively querying itself when checking roles.
create or replace function public.current_app_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;
revoke all on function public.current_app_role() from public;
grant execute on function public.current_app_role() to anon, authenticated;

-- 3. Signup-code management is an operator-only function. It is intentionally
--    NOT executable through the public API.
create or replace function public.set_signup_code(p_role text, p_plain_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null then
    raise exception 'operator-only function';
  end if;
  if p_role not in ('member','admin','parent') then
    raise exception 'invalid signup role';
  end if;
  if p_plain_code is null or length(trim(p_plain_code)) < 8 then
    raise exception 'signup code must be at least 8 characters';
  end if;
  delete from public.signup_codes where role = p_role;
  insert into public.signup_codes (role, code_hash, label)
  values (p_role, crypt(p_plain_code, gen_salt('bf')), p_role || ' code');
end;
$$;
revoke all on function public.set_signup_code(text, text) from public;

-- 4. Final account signup must be a permanent Auth user, never an anonymous
--    session that has managed to obtain a member/admin code.
create or replace function public.finalize_signup(p_username text, p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  matched_role text;
  is_anon boolean;
begin
  select coalesce(is_anonymous, false) into is_anon
  from auth.users where id = auth.uid();

  if auth.uid() is null or is_anon then
    raise exception 'permanent account required';
  end if;
  if p_username is null or length(trim(p_username)) < 2 then
    raise exception 'username is required';
  end if;

  select role into matched_role
  from public.signup_codes
  where code_hash = crypt(p_code, code_hash)
  limit 1;

  if matched_role is null then
    raise exception 'invalid code';
  end if;

  update public.profiles
  set username = trim(p_username), role = matched_role
  where id = auth.uid();

  return matched_role;
end;
$$;
grant execute on function public.finalize_signup(text, text) to authenticated;

-- 5. Parent access may only be granted to an anonymous Auth user.
create or replace function public.grant_parent_access(p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  matched_role text;
  is_anon boolean;
begin
  select coalesce(is_anonymous, false) into is_anon
  from auth.users where id = auth.uid();
  if auth.uid() is null or not is_anon then
    raise exception 'anonymous parent session required';
  end if;

  select role into matched_role
  from public.signup_codes
  where role = 'parent' and code_hash = crypt(p_code, code_hash)
  limit 1;
  if matched_role is null then
    raise exception 'invalid code';
  end if;

  update public.profiles set role = 'parent' where id = auth.uid();
  return matched_role;
end;
$$;
revoke all on function public.grant_parent_access(text) from anon, authenticated;
grant execute on function public.grant_parent_access(text) to anon, authenticated;

-- Existing creator links should not prevent administrators from deleting a
-- permanent account. Keep the content and clear the optional creator field.
alter table public.tutorials drop constraint if exists tutorials_created_by_fkey;
alter table public.tutorials add constraint tutorials_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.doc_links drop constraint if exists doc_links_created_by_fkey;
alter table public.doc_links add constraint doc_links_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.meal_signups drop constraint if exists meal_signups_created_by_fkey;
alter table public.meal_signups add constraint meal_signups_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.assignments drop constraint if exists assignments_created_by_fkey;
alter table public.assignments add constraint assignments_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.quizzes drop constraint if exists quizzes_created_by_fkey;
alter table public.quizzes add constraint quizzes_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.day_resource_requests drop constraint if exists day_resource_requests_created_by_fkey;
alter table public.day_resource_requests add constraint day_resource_requests_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.day_resource_volunteers drop constraint if exists day_resource_volunteers_created_by_fkey;
alter table public.day_resource_volunteers add constraint day_resource_volunteers_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.day_events drop constraint if exists day_events_created_by_fkey;
alter table public.day_events add constraint day_events_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.volunteer_days drop constraint if exists volunteer_days_created_by_fkey;
alter table public.volunteer_days add constraint volunteer_days_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.announcements drop constraint if exists announcements_created_by_fkey;
alter table public.announcements add constraint announcements_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;

-- 6. Tighten table reads. Anonymous Supabase users use the authenticated
--    PostgreSQL role, so auth.role() alone is not sufficient authorization.
drop policy if exists "read profiles when signed in" on public.profiles;
drop policy if exists "read own profile or all profiles as admin" on public.profiles;
create policy "read own profile or all profiles as admin"
  on public.profiles for select
  using (id = auth.uid() or public.current_app_role() = 'admin');

drop policy if exists "read tutorials when signed in" on public.tutorials;
drop policy if exists "read published tutorials" on public.tutorials;
create policy "read published tutorials"
  on public.tutorials for select
  using (published = true or public.current_app_role() in ('member','admin'));

drop policy if exists "read doc links when signed in" on public.doc_links;
drop policy if exists "members and admins read doc links" on public.doc_links;
create policy "members and admins read doc links"
  on public.doc_links for select
  using (public.current_app_role() in ('member','admin'));

drop policy if exists "read meal signups when signed in" on public.meal_signups;
create policy "parents members and admins read meal signups"
  on public.meal_signups for select
  using (public.current_app_role() in ('member','parent','admin'));

drop policy if exists "read assignments when signed in" on public.assignments;
drop policy if exists "members and admins read assignments" on public.assignments;
create policy "members and admins read assignments"
  on public.assignments for select
  using (public.current_app_role() in ('member','admin'));

drop policy if exists "read quizzes when signed in" on public.quizzes;
drop policy if exists "members and admins read quizzes" on public.quizzes;
create policy "members and admins read quizzes"
  on public.quizzes for select
  using (public.current_app_role() in ('member','admin'));

drop policy if exists "read resource requests when signed in" on public.day_resource_requests;
create policy "parents members and admins read resource requests"
  on public.day_resource_requests for select
  using (public.current_app_role() in ('member','parent','admin'));

drop policy if exists "read volunteers when signed in" on public.day_resource_volunteers;
create policy "parents members and admins read volunteers"
  on public.day_resource_volunteers for select
  using (public.current_app_role() in ('member','parent','admin'));

drop policy if exists "read day events when signed in" on public.day_events;
create policy "parents members and admins read day events"
  on public.day_events for select
  using (public.current_app_role() in ('member','parent','admin'));

drop policy if exists "read volunteer days when signed in" on public.volunteer_days;
create policy "parents members and admins read volunteer days"
  on public.volunteer_days for select
  using (public.current_app_role() in ('member','parent','admin'));


-- Announcement database rows are parent/admin-only too; published status alone
-- is not public access.
drop policy if exists "parents read published announcements" on public.announcements;
drop policy if exists "parents and admins read published announcements" on public.announcements;
create policy "parents and admins read published announcements"
  on public.announcements for select
  using (
    (published = true and public.current_app_role() in ('parent','admin'))
    or public.current_app_role() = 'admin'
  );

drop policy if exists "read attachments for visible announcements" on public.announcement_attachments;
create policy "read attachments for visible announcements"
  on public.announcement_attachments for select
  using (
    exists (
      select 1
      from public.announcements a
      where a.id = announcement_id
        and a.published = true
        and public.current_app_role() in ('parent','admin')
    )
  );


-- Anonymous/pending users must not be able to create or modify assignment
-- submission rows simply by knowing their own Auth UUID.
drop policy if exists "members submit their own work" on public.assignment_submissions;
create policy "members submit their own work"
  on public.assignment_submissions for insert
  with check (member_id = auth.uid() and public.current_app_role() in ('member','admin'));

drop policy if exists "members replace their own submission" on public.assignment_submissions;
create policy "members replace their own submission"
  on public.assignment_submissions for update
  using (member_id = auth.uid() and public.current_app_role() in ('member','admin'))
  with check (member_id = auth.uid() and public.current_app_role() in ('member','admin'));

drop policy if exists "member or admin deletes a submission" on public.assignment_submissions;
create policy "member or admin deletes a submission"
  on public.assignment_submissions for delete
  using (
    public.current_app_role() in ('member','admin')
    and (member_id = auth.uid() or public.current_app_role() = 'admin')
  );

-- 7. Storage: announcement files are visible only when tied to a published
--    announcement (or to an admin), not merely because the caller is signed in.
drop policy if exists "authenticated users read announcement files" on storage.objects;
drop policy if exists "parents and admins read published announcement files" on storage.objects;
create policy "parents and admins read published announcement files"
  on storage.objects for select
  using (
    bucket_id = 'announcement-files'
    and (
      public.current_app_role() = 'admin'
      or (
        public.current_app_role() = 'parent'
        and exists (
          select 1
          from public.announcement_attachments aa
          join public.announcements a on a.id = aa.announcement_id
          where aa.storage_path = name and a.published = true
        )
      )
    )
  );

-- 8. Storage: member submission files require an actual member/admin role.
drop policy if exists "members upload into their own folder" on storage.objects;
create policy "members upload into their own folder"
  on storage.objects for insert
  with check (
    bucket_id = 'assignment-submissions'
    and public.current_app_role() in ('member','admin')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "members replace their own files" on storage.objects;
create policy "members replace their own files"
  on storage.objects for update
  using (
    bucket_id = 'assignment-submissions'
    and public.current_app_role() in ('member','admin')
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'assignment-submissions'
    and public.current_app_role() in ('member','admin')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "owner or admin reads submission files" on storage.objects;
create policy "owner or admin reads submission files"
  on storage.objects for select
  using (
    bucket_id = 'assignment-submissions'
    and public.current_app_role() in ('member','admin')
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.current_app_role() = 'admin'
    )
  );

drop policy if exists "owner or admin deletes submission files" on storage.objects;
create policy "owner or admin deletes submission files"
  on storage.objects for delete
  using (
    bucket_id = 'assignment-submissions'
    and public.current_app_role() in ('member','admin')
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.current_app_role() = 'admin'
    )
  );

-- 9. Existing assignment files are client-managed on replacement/deletion.
--    New client code uses unique paths and removes the old path after a
--    successful database upsert. Existing orphaned objects are not deleted
--    automatically by this migration because their ownership/content cannot
--    be inferred safely. Administrators can audit them in Storage.

-- 10. Anonymous Auth users are persistent rows. Supabase recommends periodic
--     cleanup of stale anonymous users; run this manually in SQL Editor when
--     appropriate, e.g. users older than 30 days.
-- delete from auth.users
-- where is_anonymous is true and created_at < now() - interval '30 days';

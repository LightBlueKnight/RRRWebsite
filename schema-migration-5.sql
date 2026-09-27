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

create policy "parents read published announcements"
  on announcements for select
  using (
    published = true
    or exists (select 1 from profiles where id = auth.uid() and role = 'admin')
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
        and (
          a.published = true
          or exists (select 1 from profiles where id = auth.uid() and role = 'admin')
        )
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

create policy "authenticated users read announcement files"
  on storage.objects for select
  using (
    bucket_id = 'announcement-files'
    and auth.role() = 'authenticated'
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

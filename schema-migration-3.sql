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
  created_by  uuid references profiles(id),
  created_at  timestamptz not null default now()
);

alter table day_events enable row level security;

create policy "read day events when signed in"
  on day_events for select
  using (auth.role() = 'authenticated');

create policy "admins manage day events"
  on day_events for all
  using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));


-- ---------- VOLUNTEER-OPEN DAYS ----------
-- Presence of a row for a date = parents can volunteer that day.
create table volunteer_days (
  event_date  date primary key,
  created_by  uuid references profiles(id),
  created_at  timestamptz not null default now()
);

alter table volunteer_days enable row level security;

create policy "read volunteer days when signed in"
  on volunteer_days for select
  using (auth.role() = 'authenticated');

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

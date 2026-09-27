# Setup — Team Hub, Admin System, and Parents Page

This adds a login-gated team hub, an admin content system, and a
parents page to your existing site. It's still a static site (no
build step) — Supabase provides the backend.

## 1. Create a Supabase project

1. Go to supabase.com → New project (free tier is enough).
2. Once it's ready: **Project Settings → API** → copy the **Project URL**
   and the **anon / public key**.

## 2. Set up the database

1. In Supabase: **SQL Editor → New query**.
2. Paste in the entire contents of `schema.sql` (in this folder) and run it.
3. Set your three access codes (pick your own real values):
   ```sql
   select set_signup_code('member', 'your-member-code-here');
   select set_signup_code('admin',  'your-admin-code-here');
   select set_signup_code('parent', 'your-parent-code-here');
   ```
4. **Authentication → Providers**: make sure **Email** is enabled (it is
   by default) — this is what powers the username-based login even
   though users never see an email field.
5. **Authentication → Settings**: turn **off** "Confirm email" (since
   these are fake internal addresses, nobody can click a confirmation
   link sent to them).
6. **Authentication → Providers → Anonymous sign-ins**: turn this **on**
   — it's what lets parents access the calendar with just a code,
   no account.
7. **If you already had the database set up from an earlier version:**
   run the migration files you are missing in order. A database that
   already has Assignments, Quizzes, parent calendar resource requests,
   and categories needs migrations 2–5 in order, followed by
   `schema-migration-6.sql`. A much older database may need migrations
   2–6 in order. A fresh install can use `schema.sql`
   by itself; it now includes the announcement system as well.

## 3. Connect the site to your project

Open `js/supabase-config.js` and replace the two placeholder values:

```js
const SUPABASE_URL = "https://your-project-ref.supabase.co";
const SUPABASE_ANON_KEY = "your-anon-public-key";
```

That's it — every page (`hub/`, `parents.html`) reads from this one file.

## 4. Create your own admin account

1. Deploy the site (or run it locally — see below).
2. Go to `hub/index.html` → "Create an account" → sign up using your
   **admin code**. That account is an admin immediately.

## 5. Try it locally before deploying

From this folder:
```
python3 -m http.server 8000
```
Then visit `http://localhost:8000`.

## 6. Deploy

Since this is still a static site, deploying to Vercel works exactly
like before — push to your repo and Vercel will pick it up. No new
build settings needed.

---

### What's where

- `hub/index.html` — sign in / sign up (username + password, code
  required to sign up)
- `hub/home.html` — subteam links (only reachable once signed in)
- `hub/subteams/*.html` — pulls that subteam's tutorials, doc links,
  assignments, and quizzes live from the database (assignments and
  quizzes currently only shown on the Software page)
- `hub/tutorial.html?slug=...` — renders one tutorial (video + text +
  code blocks)
- `hub/admin/dashboard.html` — admin home: icon links out to every
  admin tool below
- `hub/admin/tutorials.html` — admin-only: search, publish, edit,
  delete tutorials and doc links
- `hub/admin/editor.html` — admin-only: create/edit a tutorial
- `hub/admin/assignments.html` — admin-only: post assignments, review
  and download member submissions
- `hub/admin/quizzes.html` — admin-only: embed a Google Form as a quiz
- `hub/admin/parents.html` — admin-only: day-by-day calendar — delete
  food signups, add/delete resource requests, see who volunteered
- `hub/admin/accounts.html` — admin-only: view and delete accounts
- `parents.html` — parent-code gate, latest announcements, and the meal +
  resource-request calendar (parents can also volunteer for team resource
  requests, not just bring food)
- `announcement-catalog.html` — parent-code-gated full announcement catalog
- `hub/admin/announcements.html` — admin-only announcement editor/catalog
  with publishing, inline pictures, downloadable files, editing, and delete
- `schema.sql` — the full current database structure and security
  rules (use this for a brand-new Supabase project)
- `schema-migration-2.sql` — only the newest additions (Assignments,
  Quizzes, resource requests, account deletion) — use this instead
  if your database already existed before this update

### Announcement system

Run `schema-migration-5.sql` once after migrations 1–4 to add announcements. Then run `schema-migration-6.sql` to apply the current security/RLS/storage hardening and account/file cleanup fixes.

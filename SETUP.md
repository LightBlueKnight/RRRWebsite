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
- `hub/subteams/*.html` — pulls that subteam's tutorials + doc links
  live from the database
- `hub/tutorial.html?slug=...` — renders one tutorial (video + text +
  code blocks)
- `hub/admin/dashboard.html` — admin-only: list/delete tutorials and
  doc links
- `hub/admin/editor.html` — admin-only: create/edit a tutorial
- `parents.html` — parent-code gate, scouting/community links, and
  the meal-volunteer calendar
- `schema.sql` — the whole database structure and security rules

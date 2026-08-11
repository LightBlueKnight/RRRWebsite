/* ============================================================
   Red Rock Robotics — Supabase client
   Loaded after supabase-config.js and the Supabase CDN script
   on every hub / parents page. Exposes a single shared client
   as `window.rrClient`.
   ============================================================ */

const rrClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
window.rrClient = rrClient;

function usernameToEmail(username) {
  return username.trim().toLowerCase() + "@" + USERNAME_EMAIL_DOMAIN;
}

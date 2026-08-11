/* ============================================================
   Red Rock Robotics — Supabase client for parents.html ONLY
   ------------------------------------------------------------
   Uses sessionStorage instead of localStorage, so the parent's
   session is automatically cleared when they close the tab or
   browser — matching "just a parent code, not a real account."
   This also keeps it fully isolated from any member/admin
   session that might be active in the hub (different storage
   area entirely, even on the same site).
   ============================================================ */

const rrClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    storage: window.sessionStorage,
    persistSession: true,
    autoRefreshToken: true,
  },
});
window.rrClient = rrClient;

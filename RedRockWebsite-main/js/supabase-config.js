/* ============================================================
   Red Rock Robotics — Supabase connection config
   ------------------------------------------------------------
   REPLACE both values below with your real Supabase project's
   URL and anon/public key (Project Settings → API in Supabase).
   The anon key is SAFE to expose in client code — that's how
   Supabase is designed to work; real protection comes from the
   Row Level Security policies in schema.sql, not from hiding
   this key.

   Nothing on the site will work until this file is filled in.
   ============================================================ */

const SUPABASE_URL = "https://zufordybodxupodhmhsb.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_qxTWe7tTxnhFensLCKIO4A_5aW8OO40";

// Domain used to build the hidden internal "email" for username-based
// accounts. Doesn't need to be a real domain — just needs to stay
// consistent so logins keep matching the accounts that were created.
const USERNAME_EMAIL_DOMAIN = "members.redrockrobotics.local";

/* ============================================================
   Red Rock Robotics — auth helpers
   Shared by hub/index.html, hub/home.html, subteam pages,
   admin pages, and tutorial.html.
   ============================================================ */

/** Sign up a brand-new username/password/code account. */
async function rrSignUp(username, password, code) {
  // Do not let a temporary parent session become entangled with a new
  // permanent team account in the same browser.
  const { data: { session: existingSession } } = await rrClient.auth.getSession();
  if (existingSession?.user?.is_anonymous) {
    await rrClient.auth.signOut({ scope: "local" });
  }

  // 1. Check the code BEFORE creating any account, so a wrong code
  //    never leaves behind a junk auth user.
  const { error: codeErr } = await rrClient.rpc("validate_signup_code", { p_code: code });
  if (codeErr) throw new Error("That code isn't valid.");

  // 2. Create the auth account behind a synthetic email.
  const email = usernameToEmail(username);
  const { data, error } = await rrClient.auth.signUp({ email, password });
  if (error) {
    if (error.message.toLowerCase().includes("already")) {
      throw new Error("That username is already taken.");
    }
    throw error;
  }

  // 3. Now that we're authenticated as the new user, apply the code
  //    for real (sets username + role on the profile row).
  const { error: finalizeErr } = await rrClient.rpc("finalize_signup", {
    p_username: username.trim(),
    p_code: code,
  });
  if (finalizeErr) throw new Error("Account created, but the code failed to apply. Contact an admin.");

  return data;
}

/** Log in an existing username/password account. */
async function rrLogIn(username, password) {
  const email = usernameToEmail(username);
  const { data, error } = await rrClient.auth.signInWithPassword({ email, password });
  if (error) throw new Error("Incorrect username or password.");
  return data;
}

/** Signs out and sends the browser to the given page, replacing the
 *  current history entry (so "back" can't return to a signed-in page). */
async function rrLogOut(redirectTo = "index.html") {
  await rrClient.auth.signOut({ scope: "global" }); // revokes the session everywhere, not just this tab
  window.location.replace(redirectTo);
}

/** Fetch the signed-in user's profile row (username + role), or null. */
async function rrGetProfile() {
  const { data: { session } } = await rrClient.auth.getSession();
  const user = session?.user;
  if (!user) return null;
  const { data, error } = await rrClient
    .from("profiles")
    .select("username, role")
    .eq("id", user.id)
    .single();
  if (error) return null;
  return data;
}

/**
 * Page guard: call at the top of any hub page.
 * Redirects to the login page if nobody's signed in, or if
 * `requireAdmin` is true and the signed-in user isn't an admin.
 * Returns the profile ({username, role}) on success.
 */
async function rrRequireSession({ requireAdmin = false, loginPath = "index.html" } = {}) {
  const profile = await rrGetProfile();

  // Only permanent hub accounts (member/admin) belong here. Anonymous
  // Supabase users must never be treated as signed-in team members.
  const { data: { session } } = await rrClient.auth.getSession();
  const isAnonymous = !!session?.user?.is_anonymous;
  const validRole = !isAnonymous && profile && (profile.role === "member" || profile.role === "admin");
  if (!validRole) {
    if (profile) await rrClient.auth.signOut({ scope: "global" });
    window.location.replace(loginPath);
    return null;
  }
  if (requireAdmin && profile.role !== "admin") {
    window.location.replace(loginPath.replace("index.html", "home.html"));
    return null;
  }
  return profile;
}

// If the browser restores a page from its back/forward cache (bfcache)
// instead of actually reloading it, no JS re-runs — so a page you were
// signed into could still visually appear signed in for a moment after
// you've logged out and hit Back/Forward. Force a real reload so
// rrRequireSession() (or the login-page redirect) always re-checks.
window.addEventListener("pageshow", (event) => {
  if (event.persisted) window.location.reload();
});

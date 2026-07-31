/* ============================================================
   Red Rock Robotics — parents page logic
   Handles the parent-code gate (anonymous session + role check)
   and the food-volunteer calendar (claim / edit / cancel a day).
   ============================================================ */

let currentMonth = new Date();
currentMonth.setDate(1);
let myUserId = null;

// If the browser restores this page from its back/forward cache
// (bfcache) instead of actually reloading it, none of our JS re-runs —
// which could show a stale "already inside" state after the session
// storage has changed. Force a real reload in that case.
window.addEventListener("pageshow", (event) => {
  if (event.persisted) window.location.reload();
});

/** Gate: get or start an anonymous session tagged role='parent'. */
async function rrParentGate(code) {
  let { data: { user } } = await rrClient.auth.getUser();
  if (!user) {
    const { data, error } = await rrClient.auth.signInAnonymously();
    if (error) throw new Error("Could not start a session. Try again.");
    user = data.user;
  }
  const { error: grantErr } = await rrClient.rpc("grant_parent_access", { p_code: code });
  if (grantErr) throw new Error("That code isn't valid.");
  myUserId = user.id;
  return true;
}

async function rrParentAlreadyGated() {
  const { data: { session } } = await rrClient.auth.getSession();
  const user = session?.user;
  if (!user) return false;
  const { data, error } = await rrClient
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .single();
  if (error || !data) return false;
  myUserId = user.id;
  return data.role === "parent" || data.role === "admin";
}

function fmtDate(d) {
  const y = d.getFullYear(), m = String(d.getMonth() + 1).padStart(2, "0"), day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

async function rrRenderCalendar(gridEl, headEl) {
  const year = currentMonth.getFullYear();
  const month = currentMonth.getMonth();
  headEl.textContent = currentMonth.toLocaleString("default", { month: "long", year: "numeric" });

  const firstDay = new Date(year, month, 1);
  const startOffset = firstDay.getDay();
  const daysInMonth = new Date(year, month + 1, 0).getDate();

  const rangeStart = fmtDate(new Date(year, month, 1));
  const rangeEnd = fmtDate(new Date(year, month + 1, 0));

  const { data: signups } = await rrClient
    .from("meal_signups")
    .select("*")
    .gte("event_date", rangeStart)
    .lte("event_date", rangeEnd);

  const byDate = {};
  (signups || []).forEach((s) => { byDate[s.event_date] = s; });

  gridEl.innerHTML = "";
  ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"].forEach(d => {
    const el = document.createElement("div");
    el.className = "cal-dow";
    el.textContent = d;
    gridEl.appendChild(el);
  });

  for (let i = 0; i < startOffset; i++) {
    const el = document.createElement("div");
    el.className = "cal-day empty-cell";
    gridEl.appendChild(el);
  }

  for (let day = 1; day <= daysInMonth; day++) {
    const dateStr = fmtDate(new Date(year, month, day));
    const signup = byDate[dateStr];
    const cell = document.createElement("div");
    cell.className = "cal-day" + (signup ? " claimed" : "");

    if (signup) {
      const mine = signup.created_by === myUserId;
      cell.innerHTML = `
        <div class="cd-num">${day}</div>
        <div class="cd-parent">${escHtml(signup.parent_name)}</div>
        <div class="cd-food">${escHtml(signup.food_description)}</div>
        ${signup.vegetarian ? '<div class="cd-veg">VEGETARIAN OPTION</div>' : ''}
        ${mine ? '<div class="cd-mine">Your signup — click to edit</div>' : ''}
      `;
      if (mine) {
        cell.addEventListener("click", () => window.rrOpenDayModal(dateStr, signup));
      }
    } else {
      cell.innerHTML = `<div class="cd-num">${day}</div>`;
      cell.addEventListener("click", () => window.rrOpenDayModal(dateStr, null));
      cell.addEventListener("contextmenu", (e) => { e.preventDefault(); window.rrOpenDayModal(dateStr, null); });
    }
    gridEl.appendChild(cell);
  }
}

function escHtml(str) {
  const div = document.createElement("div");
  div.textContent = str || "";
  return div.innerHTML;
}

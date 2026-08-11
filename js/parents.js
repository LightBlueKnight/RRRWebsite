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


async function rrRenderCalendar(gridEl, headEl) {
  const year = currentMonth.getFullYear();
  const month = currentMonth.getMonth();
  headEl.textContent = currentMonth.toLocaleString("default", { month: "long", year: "numeric" });

  const firstDay = new Date(year, month, 1);
  const startOffset = firstDay.getDay();
  const daysInMonth = new Date(year, month + 1, 0).getDate();

  const rangeStart = fmtDate(new Date(year, month, 1));
  const rangeEnd = fmtDate(new Date(year, month + 1, 0));

  const [{ data: signups }, { data: requests }, { data: events }, { data: openDays }] = await Promise.all([
    rrClient.from("meal_signups").select("*").gte("event_date", rangeStart).lte("event_date", rangeEnd),
    rrClient.from("day_resource_requests").select("*, day_resource_volunteers(*)").gte("event_date", rangeStart).lte("event_date", rangeEnd),
    rrClient.from("day_events").select("*").gte("event_date", rangeStart).lte("event_date", rangeEnd),
    rrClient.from("volunteer_days").select("event_date").gte("event_date", rangeStart).lte("event_date", rangeEnd),
  ]);

  const byDate = {};
  const ensure = (d) => { byDate[d] = byDate[d] || { food: null, requests: [], events: [], open: false }; return byDate[d]; };
  (signups || []).forEach((s) => { ensure(s.event_date).food = s; });
  (requests || []).forEach((r) => { ensure(r.event_date).requests.push(r); });
  (events || []).forEach((e) => { ensure(e.event_date).events.push(e); });
  (openDays || []).forEach((o) => { ensure(o.event_date).open = true; });

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
    const dayData = byDate[dateStr] || { food: null, requests: [], events: [], open: false };
    const cell = document.createElement("div");
    cell.className = "cal-day"
      + ((dayData.food || dayData.requests.length || dayData.events.length) ? " claimed" : "")
      + (dayData.open ? " volunteer-open" : "");
    cell.innerHTML = `
      <div class="cd-num">${day}</div>
      ${dayData.food ? `<div class="cd-parent">${escHtml(dayData.food.parent_name)}</div>` : ""}
      ${dayData.events.length ? `<div class="cd-event">${escHtml(dayData.events[0].text)}</div>` : ""}
      <div class="cd-indicators">
        ${dayData.food ? '<span class="cd-dot food" title="Food signup"></span>' : ""}
        ${dayData.requests.length ? '<span class="cd-dot resource" title="Resource requests"></span>' : ""}
        ${dayData.open ? '<span class="cd-dot open" title="Open for volunteering"></span>' : ""}
      </div>
    `;
    // Every day is clickable now — the day-detail view shows food
    // status AND any resource requests, whichever apply.
    cell.addEventListener("click", () => window.rrOpenDayModal(dateStr, dayData));
    gridEl.appendChild(cell);
  }
}


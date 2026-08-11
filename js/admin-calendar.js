/* ============================================================
   Red Rock Robotics — admin calendar (day-stacking)
   Renders a month view where each day can have a food signup
   AND any number of resource requests (each with volunteers).
   Calls window.rrOpenAdminDayModal(dateStr, dayData) on click —
   defined by the page itself (hub/admin/parents.html).
   ============================================================ */

let adminCalMonth = new Date();
adminCalMonth.setDate(1);


async function rrRenderAdminCalendar(gridEl, headEl) {
  const year = adminCalMonth.getFullYear();
  const month = adminCalMonth.getMonth();
  headEl.textContent = adminCalMonth.toLocaleString("default", { month: "long", year: "numeric" });

  const firstDay = new Date(year, month, 1);
  const startOffset = firstDay.getDay();
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const rangeStart = rrFmtDate(new Date(year, month, 1));
  const rangeEnd = rrFmtDate(new Date(year, month + 1, 0));

  const [{ data: signups }, { data: requests }, { data: events }, { data: openDays }] = await Promise.all([
    rrClient.from("meal_signups").select("*").gte("event_date", rangeStart).lte("event_date", rangeEnd),
    rrClient.from("day_resource_requests").select("*, day_resource_volunteers(*)").gte("event_date", rangeStart).lte("event_date", rangeEnd),
    rrClient.from("day_events").select("*").gte("event_date", rangeStart).lte("event_date", rangeEnd),
    rrClient.from("volunteer_days").select("event_date").gte("event_date", rangeStart).lte("event_date", rangeEnd),
  ]);

  const byDate = {};
  const ensure = (d) => { byDate[d] = byDate[d] || { food: null, requests: [], events: [], open: false }; return byDate[d]; };
  (signups || []).forEach(s => { ensure(s.event_date).food = s; });
  (requests || []).forEach(r => { ensure(r.event_date).requests.push(r); });
  (events || []).forEach(e => { ensure(e.event_date).events.push(e); });
  (openDays || []).forEach(o => { ensure(o.event_date).open = true; });

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
    const dateStr = rrFmtDate(new Date(year, month, day));
    const dayData = byDate[dateStr] || { food: null, requests: [], events: [], open: false };
    const cell = document.createElement("div");
    cell.className = "cal-day"
      + ((dayData.food || dayData.requests.length || dayData.events.length) ? " claimed" : "")
      + (dayData.open ? " volunteer-open" : "");
    cell.innerHTML = `
      <div class="cd-num">${day}</div>
      ${dayData.food ? `<div class="cd-parent">${escAdmin(dayData.food.parent_name)}</div>` : ""}
      ${dayData.events.length ? `<div class="cd-event">${escAdmin(dayData.events[0].text)}</div>` : ""}
      <div class="cd-indicators">
        ${dayData.food ? '<span class="cd-dot food" title="Food signup"></span>' : ""}
        ${dayData.requests.length ? '<span class="cd-dot resource" title="Resource requests"></span>' : ""}
        ${dayData.open ? '<span class="cd-dot open" title="Open for volunteering"></span>' : ""}
      </div>
    `;
    cell.addEventListener("click", () => window.rrOpenAdminDayModal(dateStr, dayData));
    cell.addEventListener("contextmenu", async (e) => {
      if (!e.shiftKey) return; // plain right-click keeps the normal browser menu
      e.preventDefault();
      if (dayData.open) {
        await rrClient.from("volunteer_days").delete().eq("event_date", dateStr);
      } else {
        const { data: { user } } = await rrClient.auth.getUser();
        await rrClient.from("volunteer_days").insert({ event_date: dateStr, created_by: user.id });
      }
      await rrRenderAdminCalendar(gridEl, headEl);
    });
    gridEl.appendChild(cell);
  }
}


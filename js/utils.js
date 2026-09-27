/* ============================================================
   Red Rock Robotics — shared utilities
   ------------------------------------------------------------
   Canonical escaping/formatting helpers used across the whole
   site. Previously these were copy-pasted under different names
   in ~10 files (escapeHtml, esc, escAdmin, rrEsc, fmtDate...) —
   consolidated here so a future fix only has to happen once.

   Aliases are kept so existing call sites don't need to change:
   any file can call escapeHtml(), esc(), rrEsc(), etc. and get
   the same function. New code should prefer rrEsc / rrEscAttr /
   rrFmtDate going forward.

   Include this BEFORE any other site script that uses these.
   ============================================================ */

function rrEsc(str) {
  const div = document.createElement("div");
  div.textContent = str || "";
  return div.innerHTML;
}

function rrEscAttr(str) {
  return (str || "").replace(/"/g, "&quot;");
}

/** Formats a Date as YYYY-MM-DD (used by the calendar views). */
function rrFmtDate(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

// Backward-compatible aliases — same functions, old names.
const escapeHtml = rrEsc;
const esc = rrEsc;
const escAdmin = rrEsc;
const escapeAttr = rrEscAttr;
const fmtDate = rrFmtDate;


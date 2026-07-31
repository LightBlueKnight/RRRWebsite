/* ============================================================
   Red Rock Robotics — subteam page content loader
   Fetches this subteam's tutorials + doc links from Supabase
   and renders them into the page. Used by all 5 subteam pages.
   ============================================================ */

async function rrLoadSubteamContent(subteam, { tutorialsEl, docsEl }) {
  const [{ data: tutorials, error: tErr }, { data: docs, error: dErr }] = await Promise.all([
    rrClient
      .from("tutorials")
      .select("slug, title, summary")
      .eq("subteam", subteam)
      .eq("published", true)
      .order("created_at", { ascending: false }),
    rrClient
      .from("doc_links")
      .select("title, description, url, locked")
      .eq("subteam", subteam)
      .order("created_at", { ascending: false }),
  ]);

  if (tutorialsEl) {
    tutorialsEl.innerHTML = "";
    if (tErr || !tutorials || tutorials.length === 0) {
      tutorialsEl.innerHTML = `<p style="color:var(--muted); font-size:13px;">No tutorials posted yet.</p>`;
    } else {
      tutorials.forEach((t) => {
        const card = document.createElement("a");
        card.className = "card";
        card.style.textDecoration = "none";
        card.href = `../tutorial.html?slug=${encodeURIComponent(t.slug)}`;
        card.innerHTML = `
          <div class="card-icon">＋</div>
          <h3>${escapeHtml(t.title)}</h3>
          <p>${escapeHtml(t.summary || "")}</p>
          <span class="card-link">Open tutorial →</span>
        `;
        tutorialsEl.appendChild(card);
      });
    }
  }

  if (docsEl) {
    docsEl.innerHTML = "";
    if (dErr || !docs || docs.length === 0) {
      docsEl.innerHTML = `<p style="color:var(--muted); font-size:13px;">No linked docs yet.</p>`;
    } else {
      docs.forEach((d) => {
        const row = document.createElement("div");
        row.className = "list-row";
        row.innerHTML = `
          <div>
            <div class="lr-name">${escapeHtml(d.title)}${d.locked ? ' 🔒' : ''}</div>
            <div class="lr-desc">${escapeHtml(d.description || "")}</div>
          </div>
          <a href="${escapeAttr(d.url)}" target="_blank" rel="noopener">View →</a>
        `;
        docsEl.appendChild(row);
      });
    }
  }
}

function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str || "";
  return div.innerHTML;
}
function escapeAttr(str) {
  return (str || "").replace(/"/g, "&quot;");
}

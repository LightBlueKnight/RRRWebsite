/* ============================================================
   Red Rock Robotics — subteam page content loader
   Fetches this subteam's tutorials + doc links from Supabase
   and renders them into the page. Used by all 5 subteam pages.
   ============================================================ */

async function rrLoadSubteamContent(subteam, { tutorialsEl, docsEl, tutorialsFilterEl }) {
  const [{ data: tutorials, error: tErr }, { data: docs, error: dErr }] = await Promise.all([
    rrClient
      .from("tutorials")
      .select("slug, title, summary, category")
      .eq("subteam", subteam)
      .eq("published", true)
      .order("created_at", { ascending: false }),
    rrClient
      .from("doc_links")
      .select("title, description, url, locked")
      .eq("subteam", subteam)
      .order("created_at", { ascending: false }),
  ]);

  function renderTutorials(list){
    tutorialsEl.innerHTML = "";
    if (!list || list.length === 0) {
      tutorialsEl.innerHTML = `<p style="color:var(--muted); font-size:13px;">No tutorials in this category.</p>`;
      return;
    }
    list.forEach((t) => {
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

  if (tutorialsEl) {
    if (tErr || !tutorials || tutorials.length === 0) {
      tutorialsEl.innerHTML = `<p style="color:var(--muted); font-size:13px;">No tutorials posted yet.</p>`;
      if (tutorialsFilterEl) tutorialsFilterEl.style.display = "none";
    } else {
      if (tutorialsFilterEl) {
        rrWireCategoryFilter(tutorialsFilterEl, tutorials, (category) => {
          renderTutorials(category ? tutorials.filter(t => t.category === category) : tutorials);
        });
      }
      renderTutorials(tutorials);
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


/* ============================================================
   Red Rock Robotics — quizzes (member-facing)
   Renders embedded Google Forms for a subteam. Google collects
   and scores the actual responses — this just stores which form
   belongs to which subteam and shows it on the page.
   NOTE: expects rrEsc() to already be defined (loaded via
   assignments.js before this file).
   ============================================================ */

async function rrLoadQuizzes(subteam, containerEl, filterEl) {
  containerEl.innerHTML = `<p style="color:var(--muted); font-size:13px;">Loading…</p>`;

  const { data: quizzes, error } = await rrClient
    .from("quizzes")
    .select("*")
    .eq("subteam", subteam)
    .order("created_at", { ascending: false });

  if (error || !quizzes || quizzes.length === 0) {
    containerEl.innerHTML = `<p style="color:var(--muted); font-size:13px;">No quizzes posted yet.</p>`;
    if (filterEl) filterEl.style.display = "none";
    return;
  }

  function render(list){
    containerEl.innerHTML = "";
    if (list.length === 0) {
      containerEl.innerHTML = `<p style="color:var(--muted); font-size:13px;">No quizzes in this category.</p>`;
      return;
    }
    list.forEach(q => {
      const block = document.createElement("div");
      block.className = "docs-block";
      block.innerHTML = `
        <span class="db-label">Quiz</span>
        <h2>${rrEsc(q.title)}</h2>
        ${q.description ? `<p class="prose" style="margin-bottom:10px;">${rrEsc(q.description)}</p>` : ""}
        <div class="video-frame" style="aspect-ratio:auto; height:640px;">
          <iframe src="${rrEscAttr(q.embed_url)}" title="${rrEscAttr(q.title)}">Loading form…</iframe>
        </div>
        <p style="font-size:12px; color:var(--muted); margin-top:8px;">
          Form not loading above?
          <a href="${rrEscAttr(q.embed_url.replace('embedded=true','').replace(/[?&]$/,''))}" target="_blank" rel="noopener" style="color:var(--light);">Open it in a new tab instead ↗</a>
        </p>
      `;
      containerEl.appendChild(block);
    });
  }

  if (filterEl) {
    rrWireCategoryFilter(filterEl, quizzes, (category) => {
      render(category ? quizzes.filter(q => q.category === category) : quizzes);
    });
  }
  render(quizzes);
}


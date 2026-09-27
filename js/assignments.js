/* ============================================================
   Red Rock Robotics — assignments (member-facing)
   rrLoadAssignments()       — summary list on the subteam page,
                                 links out to assignment.html
   rrLoadAssignmentDetail()  — the full assignment page itself
   rrSubmitAssignment()      — shared upload logic
   ============================================================ */

async function rrLoadAssignments(subteam, containerEl, filterEl) {
  containerEl.innerHTML = `<p style="color:var(--muted); font-size:13px;">Loading…</p>`;

  const { data: { session } } = await rrClient.auth.getSession();
  const user = session?.user;

  const [{ data: assignments, error: aErr }, { data: mySubs }] = await Promise.all([
    rrClient.from("assignments").select("*").eq("subteam", subteam).order("due_date", { ascending: true }),
    user ? rrClient.from("assignment_submissions").select("assignment_id").eq("member_id", user.id) : Promise.resolve({ data: [] }),
  ]);

  if (aErr || !assignments || assignments.length === 0) {
    containerEl.innerHTML = `<p style="color:var(--muted); font-size:13px;">No assignments posted yet.</p>`;
    if (filterEl) filterEl.style.display = "none";
    return;
  }

  const submittedIds = new Set((mySubs || []).map(s => s.assignment_id));

  function render(list){
    containerEl.innerHTML = "";
    if (list.length === 0) {
      containerEl.innerHTML = `<p style="color:var(--muted); font-size:13px;">No assignments in this category.</p>`;
      return;
    }
    list.forEach(a => {
      const submitted = submittedIds.has(a.id);
      const card = document.createElement("a");
      card.className = "card";
      card.style.textDecoration = "none";
      card.href = `../assignment.html?id=${a.id}`;
      card.innerHTML = `
        <div class="card-icon">📄</div>
        <h3>${rrEsc(a.title)}</h3>
        <p>${rrEsc(a.description || "")}</p>
        ${a.due_date ? `<p style="font-family:var(--mono); font-size:11px; color:var(--muted);">Due ${rrEsc(a.due_date)}</p>` : ""}
        <div class="assignment-upload">
          <span class="status-pill ${submitted ? 'published' : 'draft'}">${submitted ? 'Submitted' : 'Not submitted'}</span>
          <span class="card-link">View assignment →</span>
        </div>
      `;
      containerEl.appendChild(card);
    });
  }

  if (filterEl) {
    rrWireCategoryFilter(filterEl, assignments, (category) => {
      render(category ? assignments.filter(a => a.category === category) : assignments);
    });
  }
  render(assignments);
}

/** Renders the full assignment page: title/description/due date +
 *  the upload widget + current submission status. */
async function rrLoadAssignmentDetail(assignmentId, containerEl) {
  containerEl.innerHTML = `<p style="color:var(--muted); font-size:13px;">Loading…</p>`;

  const { data: { user } } = await rrClient.auth.getUser();

  const [{ data: a, error: aErr }, { data: existing }] = await Promise.all([
    rrClient.from("assignments").select("*").eq("id", assignmentId).single(),
    rrClient.from("assignment_submissions").select("*").eq("assignment_id", assignmentId).eq("member_id", user.id).maybeSingle(),
  ]);

  if (aErr || !a) {
    containerEl.innerHTML = `<p style="color:var(--muted); font-size:13px;">Assignment not found.</p>`;
    return null;
  }

  containerEl.innerHTML = `
    <div class="docs-hero" style="padding:0 0 20px;">
      <div class="crumb"><a href="subteams/${rrEscAttr(a.subteam)}.html">${rrEsc(a.subteam[0].toUpperCase() + a.subteam.slice(1))}</a> / ${rrEsc(a.title)}</div>
      <h1>${rrEsc(a.title)}</h1>
      ${a.due_date ? `<p style="font-family:var(--mono); font-size:12px; color:var(--muted); margin-top:6px;">Due ${rrEsc(a.due_date)}</p>` : ""}
    </div>
    <div class="docs-block">
      <span class="db-label">Description</span>
      <div class="prose">${(a.description || "No description provided.").split("\n\n").map(p => `<p>${rrEsc(p)}</p>`).join("")}</div>
    </div>
    <div class="docs-block">
      <span class="db-label">Your submission</span>
      <div class="editor-block">
        <div class="assignment-status" id="assignStatus" style="margin-bottom:12px;">
          ${existing ? `Submitted: <strong>${rrEsc(existing.file_name)}</strong> on ${new Date(existing.submitted_at).toLocaleString()}` : "You haven't submitted this yet."}
        </div>
        <input type="file" id="assignFileInput" style="display:none;">
        <button class="btn btn-primary" id="assignPickBtn" type="button">
          ${existing ? "Replace file" : "Choose file to submit"}
        </button>
      </div>
    </div>
  `;

  const fileInput = document.getElementById('assignFileInput');
  const pickBtn = document.getElementById('assignPickBtn');
  const statusEl = document.getElementById('assignStatus');

  pickBtn.addEventListener("click", () => fileInput.click());
  fileInput.addEventListener("change", async () => {
    const file = fileInput.files[0];
    if (!file) return;
    statusEl.textContent = "Uploading…";
    try {
      await rrSubmitAssignment(assignmentId, file);
      statusEl.innerHTML = `Submitted: <strong>${rrEsc(file.name)}</strong> just now`;
      pickBtn.textContent = "Replace file";
    } catch (err) {
      statusEl.textContent = "Upload failed — try again.";
      console.error(err);
    }
  });

  return a;
}

async function rrSubmitAssignment(assignmentId, file) {
  const { data: { user } } = await rrClient.auth.getUser();
  if (!user || user.is_anonymous) throw new Error("Not signed in.");
  if (!(file instanceof File)) throw new Error("No file selected.");
  const MAX_FILE_SIZE = 25 * 1024 * 1024;
  if (file.size > MAX_FILE_SIZE) throw new Error("Files must be 25 MB or smaller.");

  const { data: existing, error: existingErr } = await rrClient
    .from("assignment_submissions")
    .select("file_path")
    .eq("assignment_id", assignmentId)
    .eq("member_id", user.id)
    .maybeSingle();
  if (existingErr) throw existingErr;

  // Normalize the filename so storage paths cannot contain control chars or
  // path separators. The database preserves the original display name.
  const safeName = file.name.replace(/[^a-zA-Z0-9._ -]/g, "_").replace(/[\/]+/g, "_").slice(0, 160) || "submission";
  const path = `${user.id}/${assignmentId}/${crypto.randomUUID()}-${safeName}`;
  const { error: uploadErr } = await rrClient.storage
    .from("assignment-submissions")
    .upload(path, file, { upsert: false });
  if (uploadErr) throw uploadErr;

  const { error: dbErr } = await rrClient
    .from("assignment_submissions")
    .upsert(
      { assignment_id: assignmentId, member_id: user.id, file_path: path, file_name: file.name, submitted_at: new Date().toISOString() },
      { onConflict: "assignment_id,member_id" }
    );
  if (dbErr) {
    await rrClient.storage.from("assignment-submissions").remove([path]);
    throw dbErr;
  }

  if (existing?.file_path && existing.file_path !== path) {
    await rrClient.storage.from("assignment-submissions").remove([existing.file_path]);
  }
}


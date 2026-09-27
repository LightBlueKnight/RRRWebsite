/* ============================================================
   Red Rock Robotics — announcements
   Shared parent-facing announcement helpers and safe rendering.
   Announcement content is authored by admins as HTML, so we still
   sanitize it before inserting it into the DOM.
   ============================================================ */

const RR_ANNOUNCEMENT_BUCKET = "announcement-files";
const RR_ANNOUNCEMENT_URL_TTL = 60 * 60;

function rrFormatAnnouncementDate(value){
  if(!value) return "";
  const d = new Date(value);
  if(Number.isNaN(d.getTime())) return "";
  return d.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric"
  });
}

function rrFormatAnnouncementDateTime(value){
  if(!value) return "";
  const d = new Date(value);
  if(Number.isNaN(d.getTime())) return "";
  return d.toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit"
  });
}

function rrFormatFileSize(bytes){
  const n = Number(bytes);
  if(!Number.isFinite(n) || n < 0) return "";
  if(n < 1024) return `${n} B`;
  if(n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  if(n < 1024 * 1024 * 1024) return `${(n / (1024 * 1024)).toFixed(1)} MB`;
  return `${(n / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

/**
 * Returns only the HTML constructs the announcement editor can reasonably
 * create. The editor is admin-only, but sanitizing again on read prevents a
 * malformed row from becoming executable markup in a parent browser.
 */
function rrSanitizeAnnouncementHtml(html){
  const parser = new DOMParser();
  const doc = parser.parseFromString(String(html || ""), "text/html");

  const blocked = new Set([
    "SCRIPT", "STYLE", "IFRAME", "OBJECT", "EMBED", "FORM",
    "LINK", "META", "BASE", "NOSCRIPT", "TEMPLATE", "SVG"
  ]);

  doc.body.querySelectorAll("*").forEach(el => {
    if(blocked.has(el.tagName)){
      el.remove();
      return;
    }

    [...el.attributes].forEach(attr => {
      const name = attr.name.toLowerCase();
      const value = attr.value.trim();

      if(name.startsWith("on") || name === "style" || name === "srcdoc"){
        el.removeAttribute(attr.name);
        return;
      }

      if(name === "href"){
        const ok = /^(https?:|mailto:|tel:)/i.test(value);
        if(!ok) el.removeAttribute(attr.name);
        return;
      }

      if(name === "src"){
        const isHttp = /^https?:/i.test(value);
        const isDataImage = /^data:image\//i.test(value);
        if(!isHttp && !isDataImage) el.removeAttribute(attr.name);
        return;
      }

      const allowed = new Set([
        "href", "src", "alt", "target", "rel",
        "data-rr-storage-path", "data-rr-upload-id",
        "colspan", "rowspan"
      ]);
      if(!allowed.has(name)) el.removeAttribute(attr.name);
    });

    if(el.tagName === "A"){
      const href = el.getAttribute("href") || "";
      if(href && !/^(https?:|mailto:|tel:)/i.test(href)) el.removeAttribute("href");
      el.setAttribute("rel", "noopener noreferrer");
      if(/^https?:/i.test(href)) el.setAttribute("target", "_blank");
    }

    if(el.tagName === "IMG"){
      if(!el.dataset.rrStoragePath && !(el.getAttribute("src") || "").match(/^https?:/i)){
        el.remove();
      }
    }
  });

  return doc.body.innerHTML;
}

/** Convert an editor DOM into stable HTML before it is written to Supabase. */
function rrSerializeAnnouncementEditor(editorEl){
  const html = rrSanitizeAnnouncementHtml(editorEl?.innerHTML || "");
  const parser = new DOMParser();
  const doc = parser.parseFromString(html, "text/html");

  doc.body.querySelectorAll("img[data-rr-storage-path]").forEach(img => {
    img.removeAttribute("src");
  });

  // Pending image uploads are resolved by the admin editor before this
  // function is called. Remove any unresolved placeholder rather than storing
  // a blob/data URL that will not work for other users.
  doc.body.querySelectorAll("img[data-rr-upload-id]").forEach(img => img.remove());

  return doc.body.innerHTML.trim();
}

async function rrCreateAnnouncementSignedUrl(path, expiresIn = RR_ANNOUNCEMENT_URL_TTL){
  if(!path) return null;
  const { data, error } = await rrClient
    .storage
    .from(RR_ANNOUNCEMENT_BUCKET)
    .createSignedUrl(path, expiresIn);
  if(error) return null;
  return data?.signedUrl || null;
}

/**
 * Sanitizes and mounts announcement HTML. Uploaded images use a stable
 * storage path in data-rr-storage-path, and get a fresh signed URL at render
 * time so the database never contains an expiring URL.
 */
async function rrRenderAnnouncementBody(container, html){
  container.innerHTML = rrSanitizeAnnouncementHtml(html);

  const imageEls = [...container.querySelectorAll("img[data-rr-storage-path]")];
  await Promise.all(imageEls.map(async img => {
    const path = img.dataset.rrStoragePath;
    const url = await rrCreateAnnouncementSignedUrl(path);
    if(url){
      img.src = url;
      img.removeAttribute("data-rr-upload-id");
    } else {
      img.remove();
    }
  }));

  container.querySelectorAll("img").forEach(img => {
    img.loading = "lazy";
    img.decoding = "async";
  });

  return container;
}

function rrAnnouncementText(html){
  const parser = new DOMParser();
  const doc = parser.parseFromString(rrSanitizeAnnouncementHtml(html), "text/html");
  return (doc.body.textContent || "").replace(/\s+/g, " ").trim();
}

async function rrRenderAnnouncementAttachments(container, attachments, { compact = false } = {}){
  container.innerHTML = "";
  if(!attachments || attachments.length === 0) return;

  for(const attachment of attachments){
    const row = document.createElement("a");
    row.className = "announcement-attachment" + (compact ? " compact" : "");
    row.href = "#";
    row.target = "_blank";
    row.rel = "noopener noreferrer";

    const left = document.createElement("span");
    left.className = "announcement-attachment-main";
    const icon = document.createElement("span");
    icon.className = "announcement-attachment-icon";
    icon.textContent = attachment.is_image ? "IMG" : "FILE";
    const name = document.createElement("span");
    name.className = "announcement-attachment-name";
    name.textContent = attachment.file_name || "Attachment";
    left.append(icon, name);

    const meta = document.createElement("span");
    meta.className = "announcement-attachment-meta";
    meta.textContent = rrFormatFileSize(attachment.file_size);

    row.append(left, meta);
    row.addEventListener("click", async e => {
      e.preventDefault();
      const url = await rrCreateAnnouncementSignedUrl(attachment.storage_path);
      if(url) window.open(url, "_blank", "noopener");
      else if(window.rrAlert) await rrAlert("That attachment could not be opened.");
    });
    container.appendChild(row);
  }
}

async function rrFetchPublishedAnnouncements(limit = null){
  let query = rrClient
    .from("announcements")
    .select("*")
    .eq("published", true)
    .order("published_at", { ascending: false })
    .order("created_at", { ascending: false });
  if(Number.isInteger(limit)) query = query.limit(limit);

  const { data, error } = await query;
  if(error) throw error;
  return data || [];
}

async function rrFetchAnnouncementAttachments(announcementIds){
  const ids = [...new Set((announcementIds || []).filter(Boolean))];
  if(ids.length === 0) return {};

  const { data, error } = await rrClient
    .from("announcement_attachments")
    .select("*")
    .in("announcement_id", ids)
    .order("created_at", { ascending: true });

  if(error) throw error;
  const grouped = {};
  (data || []).forEach(row => {
    (grouped[row.announcement_id] ||= []).push(row);
  });
  return grouped;
}

async function rrFetchAnnouncementsWithAttachments({ publishedOnly = false } = {}){
  let query = rrClient.from("announcements").select("*");
  if(publishedOnly){
    query = query
      .eq("published", true)
      .order("published_at", { ascending: false })
      .order("created_at", { ascending: false });
  } else {
    query = query.order("created_at", { ascending: false });
  }

  const { data, error } = await query;
  if(error) throw error;
  const announcements = data || [];
  const attachments = await rrFetchAnnouncementAttachments(announcements.map(a => a.id));
  return announcements.map(a => ({ ...a, attachments: attachments[a.id] || [] }));
}

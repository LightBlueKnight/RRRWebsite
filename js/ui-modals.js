/* ============================================================
   Red Rock Robotics — in-website confirm / alert / prompt
   ------------------------------------------------------------
   Drop-in async replacements for the native browser dialogs so
   nothing on the site ever shows a plain browser popup:
     await rrConfirm("Delete this?")        -> true/false
     await rrAlert("Something happened")    -> resolves on OK
     await rrPrompt("Your name:")           -> string, or null if cancelled

   Fully self-contained (injects its own <style>), so it looks
   right on both the hub (css/style.css) and the main site
   (main.css) without depending on either one's classes/variables.
   ============================================================ */

function rrEnsureModalHost() {
  if (document.getElementById("rrUiModalHost")) return;

  const style = document.createElement("style");
  style.textContent = `
    #rrUiModalHost{
      position:fixed; inset:0; background:rgba(10,11,14,0.8);
      display:none; align-items:center; justify-content:center;
      z-index:9999; padding:20px; font-family:'Inter',system-ui,sans-serif;
    }
    #rrUiModalHost.open{ display:flex; }
    #rrUiModalHost .rrm-box{
      width:100%; max-width:380px; background:#252123; color:#efece4;
      border:1px solid rgba(255,255,255,0.16); border-radius:12px; padding:26px;
    }
    #rrUiModalHost h3{ margin:0 0 4px; font-size:17px; font-weight:700; }
    #rrUiModalHost p{ margin:0 0 18px; font-size:12.5px; color:#9a9498; }
    #rrUiModalHost input{
      width:100%; padding:10px 12px; background:#2d282a; border:1px solid rgba(255,255,255,0.16);
      border-radius:8px; color:#efece4; font-size:13.5px; font-family:inherit; margin-bottom:14px;
      box-sizing:border-box;
    }
    #rrUiModalHost input:focus{ border-color:#ff6600; outline:none; }
    #rrUiModalHost .rrm-actions{ display:flex; gap:10px; }
    #rrUiModalHost button{
      flex:1; padding:10px 14px; border-radius:8px; font-size:13.5px; font-weight:600;
      cursor:pointer; border:1px solid transparent; font-family:inherit;
    }
    #rrUiModalHost .rrm-ok{ background:#ff6600; color:#1b120a; }
    #rrUiModalHost .rrm-ok:hover{ background:#ff7c1f; }
    #rrUiModalHost .rrm-cancel{ background:transparent; border-color:rgba(255,255,255,0.24); color:#efece4; }
    #rrUiModalHost .rrm-cancel:hover{ border-color:#ff6600; color:#ff6600; }
  `;
  document.head.appendChild(style);

  const host = document.createElement("div");
  host.id = "rrUiModalHost";
  host.setAttribute("role", "presentation");
  host.setAttribute("aria-hidden", "true");
  host.innerHTML = `
    <div class="rrm-box" role="dialog" aria-modal="true" aria-labelledby="rrUiModalTitle" aria-describedby="rrUiModalMessage">
      <h3 id="rrUiModalTitle">Notice</h3>
      <p id="rrUiModalMessage"></p>
      <input type="text" id="rrUiModalInput" style="display:none;">
      <div class="rrm-actions">
        <button class="rrm-ok" id="rrUiModalOk">OK</button>
        <button class="rrm-cancel" id="rrUiModalCancel" style="display:none;">Cancel</button>
      </div>
    </div>
  `;
  document.body.appendChild(host);
}

function rrShowModal({ title, message, mode, defaultValue }) {
  rrEnsureModalHost();
  const host = document.getElementById("rrUiModalHost");
  document.getElementById("rrUiModalTitle").textContent = title;
  document.getElementById("rrUiModalMessage").textContent = message;

  const input = document.getElementById("rrUiModalInput");
  const cancelBtn = document.getElementById("rrUiModalCancel");
  const okBtn = document.getElementById("rrUiModalOk");

  input.style.display = mode === "prompt" ? "block" : "none";
  input.value = defaultValue || "";
  cancelBtn.style.display = mode === "alert" ? "none" : "block";
  okBtn.textContent = mode === "confirm" ? "Confirm" : "OK";

  const previousFocus = document.activeElement;
  host.setAttribute("aria-hidden", "false");
  host.classList.add("open");
  setTimeout(() => {
    if (mode === "prompt") input.focus();
    else okBtn.focus();
  }, 0);

  return new Promise((resolve) => {
    function cleanup(result) {
      host.classList.remove("open");
      host.setAttribute("aria-hidden", "true");
      okBtn.onclick = null;
      cancelBtn.onclick = null;
      input.onkeydown = null;
      document.removeEventListener("keydown", onDialogKeydown, true);
      if (previousFocus && typeof previousFocus.focus === "function") previousFocus.focus();
      resolve(result);
    }

    function onDialogKeydown(e) {
      if (!host.classList.contains("open")) return;
      if (e.key === "Escape") {
        e.preventDefault();
        if (mode === "alert") okBtn.click();
        else cancelBtn.click();
        return;
      }
      if (e.key !== "Tab") return;
      const focusable = [input, okBtn, cancelBtn].filter(el => el.style.display !== "none");
      const visible = focusable.filter(el => el.offsetParent !== null);
      if (!visible.length) return;
      const first = visible[0];
      const last = visible[visible.length - 1];
      if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
    }
    okBtn.onclick = () => {
      if (mode === "prompt") cleanup(input.value);
      else if (mode === "confirm") cleanup(true);
      else cleanup(undefined);
    };
    cancelBtn.onclick = () => {
      if (mode === "prompt") cleanup(null);
      else cleanup(false);
    };
    input.onkeydown = (e) => {
      if (e.key === "Enter") okBtn.click();
    };
    document.addEventListener("keydown", onDialogKeydown, true);
  });
}

function rrAlert(message, title = "Notice") {
  return rrShowModal({ title, message, mode: "alert" });
}
function rrConfirm(message, title = "Please confirm") {
  return rrShowModal({ title, message, mode: "confirm" });
}
function rrPrompt(message, title = "Input needed", defaultValue = "") {
  return rrShowModal({ title, message, mode: "prompt", defaultValue });
}

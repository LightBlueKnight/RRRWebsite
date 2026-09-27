/* ============================================================
   Red Rock Robotics — categories
   Shared helpers for the "pick existing or add new" category
   combo on admin pages, and the filter dropdowns on member pages.
   ============================================================ */

/** Fetches categories from ALL content tables (assignments, quizzes,
 *  tutorials) combined, so a category created anywhere shows up
 *  everywhere — not scoped per content type. */
async function rrFetchCategories() {
  const [{ data: a }, { data: q }, { data: t }] = await Promise.all([
    rrClient.from("assignments").select("category"),
    rrClient.from("quizzes").select("category"),
    rrClient.from("tutorials").select("category"),
  ]);
  const set = new Set(
    [...(a || []), ...(q || []), ...(t || [])]
      .map(r => r.category)
      .filter(Boolean)
  );
  return Array.from(set).sort();
}

/** Wires a <select> + a hidden-by-default text <input> into a
 *  "pick existing or add new" combo. Call once per page load. */
function rrWireCategorySelect(selectEl, newInputEl, categories, currentValue) {
  selectEl.innerHTML = "";
  categories.forEach(c => {
    const opt = document.createElement("option");
    opt.value = c;
    opt.textContent = c;
    selectEl.appendChild(opt);
  });
  const newOpt = document.createElement("option");
  newOpt.value = "__new__";
  newOpt.textContent = "+ Add new category…";
  selectEl.appendChild(newOpt);

  if (currentValue && categories.includes(currentValue)) {
    selectEl.value = currentValue;
  } else if (currentValue) {
    const opt = document.createElement("option");
    opt.value = currentValue;
    opt.textContent = currentValue;
    selectEl.insertBefore(opt, newOpt);
    selectEl.value = currentValue;
  }

  function syncVisibility() {
    newInputEl.style.display = selectEl.value === "__new__" ? "block" : "none";
  }
  selectEl.addEventListener("change", syncVisibility);
  syncVisibility();
}

function rrGetCategoryValue(selectEl, newInputEl) {
  if (selectEl.value === "__new__") {
    return newInputEl.value.trim() || "General";
  }
  return selectEl.value || "General";
}

/** Wires a filter <select> (member-facing) from a list of items
 *  that each have a .category, calling onChange(selectedCategory)
 *  whenever the selection changes. selectedCategory is "" for "All". */
function rrWireCategoryFilter(selectEl, items, onChange) {
  const categories = Array.from(new Set(items.map(i => i.category).filter(Boolean))).sort();
  selectEl.innerHTML = `<option value="">All categories</option>` +
    categories.map(c => `<option value="${c.replace(/"/g, "&quot;")}">${c}</option>`).join("");
  selectEl.style.display = categories.length > 1 ? "inline-block" : "none";
  selectEl.onchange = () => onChange(selectEl.value);
}

# On-Call Roster Delete and Lock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `docs/superpowers/specs/2026-09-04-oncall-roster-delete-lock-design.md`: let an admin delete a roster entry, protect permanent staff with a per-person lock, pin each tech's color so deletion stops recoloring the survivors, and route unmatched weeks to Needs attention or Roster notes depending on whether they are still upcoming.

**Architecture:** All changes are in `tools/on-call/index.html`, plus one prerequisite CSS fix. `color` and `locked` are additive optional JSON fields, so `data.json`'s existing shape and the Function App contract are untouched. Deletion deliberately does **not** cascade to `schedule` rows: a removed tech's weeks become unmatched and fall into the historical-record treatment that already exists for David.

**Tech Stack:** Vanilla JS/HTML/CSS, no build step, no test framework. Verification is Playwright plus light and dark screenshots. Real inline Lucide SVG only. No em dashes in UI copy.

**Built against the scaled layout** (container 1680px, 42px cells, type floor 9px) from the 2026-09-04 scale-up. Any pixel figures below assume that baseline.

**Local static server** (from repo root):

```bash
/c/dev/tools/nodejs/node.exe -e "require('http').createServer((q,s)=>{const p=decodeURI(q.url.split('?')[0]);const f='.'+(p==='/'?'/tools/on-call/index.html':p);require('fs').readFile(f,(e,d)=>{if(e){s.statusCode=404;s.end('not found')}else{s.end(d)}})}).listen(8850,()=>console.log('serving on 8850'))"
```

Open `http://localhost:8850/tools/on-call/index.html`. **Auth bypass** via `browser_evaluate`:

```javascript
document.getElementById('authScreen').style.display='none';
document.getElementById('appScreen').style.display='block';
document.getElementById('toolContent').style.display='block';
document.body.style.opacity='1';
await loadData();
st.isAdmin = true; renderAll(); toggleEditMode();
```

**Console baseline:** one `404` for `/favicon.ico` is expected and is not a fault. **Screenshots:** call `browser_take_screenshot` with **no `filename`** so the image returns inline and can actually be reviewed.

**Discard test mutations by reloading.** Never call `saveChanges()` during verification unless a step says to; `ONCALL_SAVE_URL` is blank so it only warns, but keep the habit.

---

### Task 1: Restore the toggle switch styling (prerequisite)

**Files:**
- Modify: `tools/on-call/index.html` (CSS, insert before the `/* ── Detail panel` comment)

The spec says style the new "Protected" row exactly like the existing "In Rotation" row. That row is currently **broken**: `.tog` and `.track` have no CSS anywhere in the repo, so it renders as a raw native OS checkbox next to a 13x0px invisible div. Verified 2026-09-04. It was almost certainly orphaned when the Edit Mode checkbox+track switch was replaced with a pencil button on 2026-09-03.

Fix it first, so there is a correct pattern to copy and so the panel stops showing the only unstyled control in the tool.

- [ ] **Step 1: Add the switch CSS**

Insert immediately before the line `/* ── Detail panel (shared: calendar week + roster contact) ── */`:

```css
    /* Toggle switch used by the contact panel's In Rotation and Protected rows.
       The markup (label.tog > input + div.track) already existed but lost its
       CSS when the Edit Mode switch became a pencil button, leaving a raw
       native checkbox visible. */
    .tog { position:relative; display:inline-block; width:38px; height:22px; flex-shrink:0; cursor:pointer; }
    .tog input { position:absolute; opacity:0; width:0; height:0; }
    .tog .track { position:absolute; inset:0; background:var(--border-mid); border-radius:20px;
                  transition:background .15s; }
    .tog .track::after { content:""; position:absolute; top:3px; left:3px; width:16px; height:16px;
                         border-radius:50%; background:var(--surface); box-shadow:var(--shadow-sm);
                         transition:transform .15s; }
    .tog input:checked + .track { background:var(--blue); }
    .tog input:checked + .track::after { transform:translateX(16px); }
```

- [ ] **Step 2: Verify**

Load with the auth bypass, then `openContactPanel('rotation', 1)`. Via `browser_evaluate`:

```javascript
const t = document.querySelector('#panelBody .track');
const cb = document.getElementById('draftInRotation');
JSON.stringify({
  trackW: Math.round(t.getBoundingClientRect().width),
  trackH: Math.round(t.getBoundingClientRect().height),
  trackBg: getComputedStyle(t).backgroundColor,
  checkboxHidden: getComputedStyle(cb).opacity === '0'
});
```

Expected: `trackW` 38, `trackH` 22, a non-transparent `trackBg`, `checkboxHidden` true. Then click the switch and confirm the track changes color and the knob slides. Screenshot the panel in both themes; the raw blue checkbox must be gone.

- [ ] **Step 3: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation: restore the contact panel toggle switch styling"
```

---

### Task 2: Pin each tech's color

**Files:**
- Modify: `tools/on-call/index.html` (`buildPersonColors`)

Deletion currently recolors the survivors, because palette slots are assigned by sorted position. This makes colors permanent so deletion is safe.

- [ ] **Step 1: Replace `buildPersonColors`**

Replace the whole function:

```javascript
function buildPersonColors(data) {
  const map = {};
  const taken = new Set();

  // Pass 1: honour any color already pinned on the tech.
  data.rotationTechs.forEach(t => {
    if (t.shortName && t.shortName.trim() && t.color) {
      map[t.shortName] = t.color;
      taken.add(t.color);
    }
  });

  // Pass 2: backfill anyone without one, in sorted shortName order, taking the
  // first palette entry nobody holds. With no pre-existing colors this
  // reproduces the old sorted-position assignment exactly, so nothing changes
  // visually the first time this runs.
  //
  // The write-back to `t.color` is load-bearing, not an optimisation: it is what
  // makes deletion safe before the first save has ever happened. Every tech
  // holds a concrete color in memory right after load, so a post-delete rebuild
  // takes pass 1 for every survivor and cannot reshuffle them.
  data.rotationTechs
    .filter(t => t.shortName && t.shortName.trim() && !t.color)
    .sort((a, b) => (a.shortName < b.shortName ? -1 : 1))
    .forEach(t => {
      const next = PERSON_PALETTE.find(c => !taken.has(c)) || PERSON_PALETTE[taken.size % PERSON_PALETTE.length];
      t.color = next;
      map[t.shortName] = next;
      taken.add(next);
    });

  return map;
}
```

Blank `shortName` entries are still skipped entirely, which is the existing behaviour.

- [ ] **Step 2: Verify colors are unchanged on first load**

Load with the auth bypass. Via `browser_evaluate`:

```javascript
JSON.stringify({
  colors: Object.fromEntries(['Joshua','Nick','Joe','Robert','Krista'].map(s => [s, personColorFor(s)])),
  written: st.data.rotationTechs.map(t => t.shortName + '=' + t.color)
});
```

Expected exactly: Joshua `#1a56db`, Nick `#9333ea`, Joe `#059669`, Robert `#dc2626`, Krista `#d97706`, and every tech now carrying a `color`.

- [ ] **Step 3: Verify deletion no longer recolors survivors**

```javascript
const before = Object.fromEntries(['Joshua','Nick','Joe','Robert'].map(s => [s, personColorFor(s)]));
const i = st.data.rotationTechs.findIndex(t => t.shortName === 'Krista');
st.data.rotationTechs.splice(i, 1);
st.personColors = buildPersonColors(st.data);
const after = Object.fromEntries(['Joshua','Nick','Joe','Robert'].map(s => [s, personColorFor(s)]));
JSON.stringify({ shifted: Object.keys(before).filter(k => before[k] !== after[k]) });
```

Expected: `{"shifted":[]}`. Before this task the same test shifted Nick and Robert. Reload to discard.

- [ ] **Step 4: Verify a new tech gets an unused color**

```javascript
addContact('rotation');
st.data.rotationTechs[st.data.rotationTechs.length-1].shortName = 'Zoe';
st.personColors = buildPersonColors(st.data);
JSON.stringify({ zoe: personColorFor('Zoe'),
                 clash: ['Joshua','Nick','Joe','Robert','Krista'].map(s=>personColorFor(s)).includes(personColorFor('Zoe')) });
```

Expected: a palette color, and `clash` false. Reload to discard.

- [ ] **Step 5: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation: pin per-tech colors so roster changes stop reshuffling them"
```

---

### Task 3: Lock field and the Protected toggle

**Files:**
- Modify: `tools/on-call/index.html` (`renderContactPanelBody`, `saveContactPanel`)

- [ ] **Step 1: Add the Protected row to the panel**

In `renderContactPanelBody`'s edit branch, insert immediately after the existing In Rotation `.panel-toggle-row` block and before `<div id="draftPhones"></div>`:

```javascript
    <div class="panel-toggle-row">
      <label>Protected</label>
      <label class="tog"><input type="checkbox" id="draftLocked" ${st.draft.locked ? "checked" : ""}
        onchange="st.draft.locked=this.checked; renderContactPanelBody()"/><div class="track"></div></label>
    </div>
```

Re-rendering the body on change is deliberate: it refreshes the Remove button's disabled state (Task 5) the moment the toggle flips.

- [ ] **Step 2: Persist `locked` through save**

`saveContactPanel` already assigns the whole `st.draft` object into the array, so `locked` persists with no change. Confirm by reading the function and checking it does `sourceArr[st.panel.idx] = st.draft` (or the push in the group-change branch). **No edit needed here** — this step is a read-and-confirm, not a change.

- [ ] **Step 3: Verify**

Load with the auth bypass, `openContactPanel('rotation', 1)`. Confirm:
- Two toggle rows now render: "In Rotation" (checked) and "Protected" (unchecked).
- Clicking Protected sets `st.draft.locked` true and the switch animates.
- `saveContactPanel()` then leaves `st.data.rotationTechs[1].locked === true`.
- Reopening the panel shows Protected still checked.
- In **view** mode (`toggleEditMode()` off, reopen) neither toggle appears, since the read-only branch renders no toggles.

Screenshot the panel in both themes with Protected on.

- [ ] **Step 4: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation: add a Protected toggle to the contact panel"
```

---

### Task 4: Lock icons on the tech card and the also-reachable chip

**Files:**
- Modify: `tools/on-call/index.html` (icon constants, CSS, `renderTechStrip`, `renderAlsoReachable`)

- [ ] **Step 1: Add the lock icon constant**

Insert after the `ICON_GRIP` constant. This is the same Lucide `lock` path the hub already uses for its locked-tile badge, kept at `stroke-width="2.5"` to match how the hub renders it at small sizes:

```javascript
const ICON_LOCK = `<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>`;
```

- [ ] **Step 2: Add the icon CSS**

Insert after the `.tech-grip` rule:

```css
    .tech-lock { position:absolute; top:7px; right:7px; display:flex; color:var(--muted2); }
    .tech-card.has-grip .tech-lock { right:24px; }
    .also-lock { display:flex; color:var(--muted2); margin-left:-2px; }
```

`.has-grip` shifts the lock left so it does not sit under the drag handle in edit mode.

- [ ] **Step 3: Render the lock on tech cards**

In `renderTechStrip`, replace the card template's opening and grip line:

```javascript
    return `<div class="tech-card${canEdit ? " has-grip" : ""}" ${dragAttrs} style="--tech-color:${personColorFor(t.shortName)}"
         onclick="openContactPanel('rotation', ${i})">
        ${canEdit ? `<span class="tech-grip">${ICON_GRIP}</span>` : ""}
        ${t.locked ? `<span class="tech-lock" title="Protected from removal">${ICON_LOCK}</span>` : ""}
```

The rest of the card body is unchanged. Note the lock renders regardless of `canEdit`, so protected status is visible in view mode too.

- [ ] **Step 4: Render the lock on also-reachable chips**

In `renderAlsoReachable`, replace the chip template:

```javascript
  const chips = st.data.otherContacts.map((c, i) => `
    <span class="also-chip" onclick="openContactPanel('other', ${i})">
      <span class="also-avatar" style="background:${OTHER_CONTACT_COLOR}">${initials(c.name)}</span>${c.name}
      ${c.locked ? `<span class="also-lock" title="Protected from removal">${ICON_LOCK}</span>` : ""}
    </span>`).join("");
```

- [ ] **Step 5: Verify**

Load with the auth bypass, then:

```javascript
st.data.rotationTechs[1].locked = true;
st.data.otherContacts[0].locked = true;
renderTechStrip(); renderAlsoReachable();
JSON.stringify({
  techLocks: document.querySelectorAll('#techStrip .tech-lock').length,
  alsoLocks: document.querySelectorAll('#alsoReachable .also-lock').length,
  isRealSvg: !!document.querySelector('.tech-lock svg rect')
});
```

Expected: 1, 1, true. Then:
- Toggle edit mode off and confirm both locks are still visible (view mode).
- In edit mode, confirm the lock and the grip handle do not overlap.
- Screenshot the strip and bar in both themes; the lock must be legible in dark.

Reload to discard.

- [ ] **Step 6: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation: show a lock icon on protected roster entries"
```

---

### Task 5: Delete

**Files:**
- Modify: `tools/on-call/index.html` (CSS, `renderContactPanelBody`, new `removeContact`)

- [ ] **Step 1: Add the Remove button CSS**

Insert after the `.tog input:checked + .track::after` rule from Task 1:

```css
    .btn-remove { background:transparent; color:var(--red); border:1.5px solid var(--red-border); }
    .btn-remove:hover:not(:disabled) { background:var(--red-light); }
    .btn-remove:disabled { opacity:.45; cursor:not-allowed; }
```

This mirrors `.btn-secondary`'s transparent-with-colored-border shape and the existing `.btn-primary:disabled` convention.

- [ ] **Step 2: Add the Remove button to the panel**

In `renderContactPanelBody`'s edit branch, replace the button row:

```javascript
    <div class="panel-btnrow">
      <button class="btn btn-remove" ${st.draft.locked ? `disabled title="Unlock to remove"` : ""}
              onclick="removeContact()">Remove</button>
      <button class="btn btn-secondary" onclick="closePanel()">Cancel</button>
      <button class="btn btn-primary" onclick="saveContactPanel()">Save</button>
    </div>
```

Disabled rather than hidden, per the spec: a hidden button reads as a missing feature rather than a deliberate guard.

- [ ] **Step 3: Implement `removeContact`**

Insert immediately after `addContact`:

```javascript
function removeContact() {
  const { group, idx } = st.panel;
  const arr = st.data[group === "rotation" ? "rotationTechs" : "otherContacts"];
  const person = arr[idx];
  if (!person || person.locked) return;   // defensive; the button is disabled

  // Count across every year, not just the selected one: the weeks being kept
  // as history are not limited to whatever tab happens to be open.
  const weeks = group === "rotation" && person.shortName
    ? st.data.schedule.filter(r => r.tech === person.shortName).length
    : 0;
  const tail = weeks
    ? `\n\nTheir ${weeks} scheduled week${weeks === 1 ? "" : "s"} are kept as historical record.`
    : "";
  if (!confirm(`Remove ${person.name} from the roster?${tail}`)) return;

  arr.splice(idx, 1);
  st.personColors = buildPersonColors(st.data);
  closePanel();
  renderAll();
  saveChanges();
}
```

Copy uses "Their", not a gendered pronoun.

- [ ] **Step 4: Verify the locked guard**

Load with the auth bypass, `openContactPanel('rotation', 1)`, then:

```javascript
document.getElementById('draftLocked').click();   // turn Protected on
const b = document.querySelector('.btn-remove');
JSON.stringify({ disabled: b.disabled, title: b.title, cursor: getComputedStyle(b).cursor });
```

Expected: `disabled` true, title "Unlock to remove", cursor `not-allowed`. Click it and confirm **no** `confirm()` appears and the roster is unchanged. Toggle Protected off and confirm the button enables without closing the panel.

- [ ] **Step 5: Verify the delete itself**

With Protected off on Krista (index 4), click Remove and accept the dialog. Confirm:
- The dialog text reads "Remove Krista Guthrie from the roster?" and "Their **25** scheduled weeks are kept as historical record." 25 is her real total across all years: 7 in 2024, 9 in 2025, 9 in 2026, verified 2026-09-04. Assert the exact number, not just that a number appears.
- `st.data.rotationTechs.length` is 4, `st.data.schedule.length` is still 147.
- The tech strip shows 4 cards; the board still has 52 cells with 12 dashed.
- Every survivor's color is unchanged.
- Roster notes now lists Krista alongside David.
- Cancelling the dialog instead leaves everything untouched.

- [ ] **Step 6: Verify gating**

- `st.isAdmin = false; renderAll();` then open a contact: the panel is read-only, no Remove button.
- Admin with edit mode off: same, no Remove button.

Reload to discard, then screenshot the panel with Remove enabled and disabled, in both themes.

- [ ] **Step 7: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation: add admin delete for roster entries, blocked when protected"
```

---

### Task 6: Split unmatched weeks into upcoming and historical

**Files:**
- Modify: `tools/on-call/index.html` (`unmatchedTechs`, `renderAttention`, `renderRosterNotes`)

Deleting someone with upcoming weeks leaves real uncovered coverage, which today would be filed silently as history.

- [ ] **Step 1: Change `unmatchedTechs` to return a split**

Replace the whole function:

```javascript
function unmatchedTechs(year) {
  const known = new Set(st.data.rotationTechs.map(t => t.shortName));
  const past = {}, upcoming = {};
  sortedByDate(getYearWeeks(year))
    .filter(r => !known.has(r.tech))
    .forEach(r => {
      const bucket = daysFromToday(r.startDate) > 0 ? upcoming : past;
      (bucket[r.tech] = bucket[r.tech] || []).push(r.startDate);
    });
  return { past, upcoming };
}
```

"Upcoming" uses the same `daysFromToday(...) > 0` test as the queue and the board's next-week ring.

- [ ] **Step 2: Consume the upcoming bucket in `renderAttention`**

Replace the whole function:

```javascript
function renderAttention() {
  const el = document.getElementById("attentionCard");
  const items = [];

  const yearRows = getYearWeeks(st.year);
  if (yearRows.length && !yearRows.some(r => r.timeOff)) {
    items.push({ icon: ICON_PALMTREE,
      text: `No time off recorded anywhere in ${st.year}. Worth a pass before the holidays.` });
  }

  const { upcoming } = unmatchedTechs(st.year);
  Object.keys(upcoming).forEach(t => {
    const n = upcoming[t].length;
    items.push({ icon: ICON_FILE_TEXT,
      text: `${n} upcoming week${n === 1 ? "" : "s"} ${n === 1 ? "is" : "are"} assigned to <strong>${t}</strong>, who is no longer in the roster. Reassign ${n === 1 ? "it" : "them"}. ${upcoming[t].map(shortDate).join(", ")}.` });
  });

  if (!items.length) { el.style.display = "none"; return; }
  el.style.display = "block";
  el.innerHTML = `<div class="oc-card-lbl">Needs attention</div>` + items.map(i =>
    `<div class="oc-note-item warn"><span class="oc-note-icon">${i.icon}</span><span>${i.text}</span></div>`
  ).join("");
}
```

- [ ] **Step 3: Consume the past bucket in `renderRosterNotes`**

Replace the whole function:

```javascript
function renderRosterNotes() {
  const el = document.getElementById("rosterNotesCard");
  const { past } = unmatchedTechs(st.year);
  const names = Object.keys(past);
  if (!names.length) { el.style.display = "none"; return; }
  el.style.display = "block";

  const items = names.map(t => {
    const dates = past[t].map(shortDate).join(", ");
    const n = past[t].length;
    return `<div class="oc-note-item info">
        <span class="oc-note-icon">${ICON_FILE_TEXT}</span>
        <span>${n} week${n === 1 ? "" : "s"} in ${st.year} ${n === 1 ? "is" : "are"} assigned to
        <strong>${t}</strong>, who has left the rotation. Kept as historical record. ${dates}.</span>
      </div>`;
  }).join("");

  el.innerHTML = `<div class="oc-card-lbl">Roster notes</div>${items}`;
}
```

- [ ] **Step 4: Verify David is unchanged**

Load with the auth bypass on 2026. All three of David's weeks (Feb 1, Mar 15, Apr 26) are in the past, so:
- Needs attention shows **only** the time-off item.
- Roster notes shows the David item, wording unchanged from before this task.

- [ ] **Step 5: Verify a deletion with upcoming weeks raises an amber item**

```javascript
const i = st.data.rotationTechs.findIndex(t => t.shortName === 'Robert');
st.data.rotationTechs.splice(i, 1);
st.personColors = buildPersonColors(st.data);
renderAll();
JSON.stringify({
  attention: document.getElementById('attentionCard').textContent.replace(/\s+/g,' ').trim(),
  notes: document.getElementById('rosterNotesCard').textContent.replace(/\s+/g,' ').trim()
});
```

Expected: Robert appears in **Needs attention** with "upcoming week(s) ... Reassign them" for his post-today weeks, **and** in Roster notes for his pre-today 2026 weeks. Both cards list only their own dates. Confirm no em dashes in either string. Reload to discard.

- [ ] **Step 6: Commit**

```bash
git add tools/on-call/index.html
git commit -m "On-Call Rotation: route upcoming unmatched weeks to Needs attention"
```

---

### Task 7: Full regression, dark-mode audit, and push

**Files:**
- Modify: `tools/on-call/index.html` only if the audit finds something

- [ ] **Step 1: Prove no hardcoded colors were introduced**

```bash
/c/dev/tools/nodejs/node.exe -e "
const fs=require('fs');
const src=fs.readFileSync('tools/on-call/index.html','utf8').split('\n');
const start=src.findIndex(l=>l.includes('.oc-layout {'));
const end=src.findIndex(l=>l.includes('── Build Mode ──'));
const hits=[];
src.slice(start,end).forEach((l,i)=>{const m=l.match(/#[0-9a-fA-F]{3,6}\b|rgba?\([^)]*\)/g); if(m) hits.push('L'+(start+i+1)+' '+m.join(','));});
console.log(hits.length+' literal(s)'); hits.forEach(h=>console.log('  '+h));
"
```

Expected: the same 7 as before this plan (six `#fff` on saturated backgrounds, one `rgba(0,0,0,.2)` drop shadow). Any new literal is a bug; replace it with a token. Note the Task 1 and Task 5 CSS lives outside this block, so also eyeball those rules for literals.

- [ ] **Step 2: Re-run the NOW-tag collision sweep**

Nothing in this plan changes cell height or the row gap, but re-run it anyway since it is cheap and the fix is fragile:

```javascript
const origFind = findCurrentWeek; const out = {};
for (const theme of ['light','dark']) {
  document.documentElement.setAttribute('data-theme', theme);
  let colliding = 0;
  for (const w of sortedByDate(getYearWeeks('2026'))) {
    window.findCurrentWeek = () => w; renderYearBoard();
    const tc = document.querySelector('#yearBoard .wk.today'); const tag = tc && tc.querySelector('.wk-now-tag');
    if (!tag) continue;
    const tr = tag.getBoundingClientRect();
    if ([...document.querySelectorAll('#yearBoard .wk')].some(c => { if (c===tc) return false;
      const r=c.getBoundingClientRect();
      return !(tr.right<r.left||tr.left>r.right||tr.bottom<r.top||tr.top>r.bottom); })) colliding++;
  }
  out[theme] = colliding;
}
window.findCurrentWeek = origFind; renderAll(); JSON.stringify(out);
```

Expected: `{"light":0,"dark":0}`.

- [ ] **Step 3: Regression pass on everything already shipped**

Confirm still working: board drag-to-swap, tech-strip drag-to-reorder (and that it still does **not** touch `schedule`), find-a-person highlight plus year-switch fallback, the handoff countdown, Copy on a phone row, week cell click to panel, and Build Mode end to end (setup, canvas, drag-swap, popover, discard, commit). Zero console errors beyond the favicon.

- [ ] **Step 4: Both-theme screenshot sweep**

Light and dark, checking legibility of: the contact panel with both toggles and all three buttons, the Remove button disabled, a lock icon on a tech card, a lock on an also-reachable chip, an amber upcoming-unmatched item, and a grey roster-notes item.

- [ ] **Step 5: Verify no real data is being added, then push**

```bash
git status
git diff origin/testing..HEAD --stat
git diff origin/testing..HEAD | grep -cE '[0-9]{3}-[0-9]{3}-[0-9]{4}'
```

Expected: clean tree, only `tools/on-call/index.html` (plus any spec edits) changed, and `0` phone-number patterns.

```bash
git push origin testing
```

- [ ] **Step 6: Confirm the deploy**

The preview deploy is two hops and both must land. Poll the served HTML rather than trusting a workflow list:

```bash
URL="https://jgdev-ch.github.io/it-tools-preview/tools/on-call/"
for i in $(seq 1 30); do
  if curl -s "${URL}?cb=$(date +%s%N)" | grep -q "removeContact"; then echo "LIVE after ~$((i*15))s"; exit 0; fi
  sleep 15
done
echo TIMEOUT; exit 1
```

- [ ] **Step 7: Hand off**

Report to Josh that delete and lock are live on preview, and flag the two things worth his judgement: whether "Protected" is the right label, and whether the lock icon belongs top-right on the tech card or somewhere less crowded now that the grip shares that corner in edit mode.

**Deliberately not done** (per the spec's Out of Scope): bulk delete, undo/restore, any archive UI for departed staff, automatic reassignment of a departed person's upcoming weeks, per-week locking, and any change to `PERSON_PALETTE`.

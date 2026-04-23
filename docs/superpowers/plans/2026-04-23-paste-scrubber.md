# Paste Scrubber Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a named transform pipeline to the Name Resolver paste tab that strips noise from pasted text and shows a "Names detected" panel with per-name transform tags before lookup runs.

**Architecture:** All changes are self-contained in `tools/name-resolver/index.html`. The pipeline is a set of pure transform functions composed by `scrubLine()`. The result drives a new `renderDetectedPanel()` UI function. `handlePaste()` is updated to call the scrubber instead of the raw split logic. The column mapper card is hidden in paste mode since paste always produces a single implicit `Name` column.

**Tech Stack:** Vanilla JS, vanilla CSS, no build step. All changes stay within the single HTML file. Test verification is done in browser DevTools console using `console.assert`.

---

### Task 1: Add CSS and HTML for the "Names detected" panel

**Files:**
- Modify: `tools/name-resolver/index.html` — CSS block (inside `<style>`) and HTML block (inside `#pasteZone`)

- [ ] **Step 1: Add CSS for the detected panel**

Find the `/* ── Progress ── */` comment block in the `<style>` tag. Insert the following block immediately before it:

```css
/* ── Detected names panel ── */
.detected-hdr  { display:flex; justify-content:space-between; align-items:center; background:var(--blue-light); padding:7px 12px; font-size:11px; font-weight:700; color:var(--blue-dark); text-transform:uppercase; letter-spacing:.05em; }
.detected-hdr .detected-transformed { color:var(--blue); font-weight:500; text-transform:none; letter-spacing:0; }
.detected-list { background:var(--surface); }
.detected-row  { display:flex; align-items:center; justify-content:space-between; padding:7px 12px; border-bottom:1px solid var(--border); font-size:12px; gap:8px; }
.detected-row:last-child { border-bottom:none; }
.detected-left { display:flex; align-items:center; gap:8px; flex:1; min-width:0; }
.detected-dot  { width:6px; height:6px; border-radius:50%; background:var(--blue); flex-shrink:0; }
.detected-tags { display:flex; gap:4px; flex-wrap:wrap; justify-content:flex-end; }
.scrub-tag     { font-size:10px; font-weight:600; background:var(--amber-light); color:var(--amber); padding:2px 8px; border-radius:10px; border:1px solid var(--amber-border); white-space:nowrap; }
```

- [ ] **Step 2: Add the detected panel HTML inside `#pasteZone`**

Find the `#pasteZone` div. Replace its contents with the following (keep the outer `<div id="pasteZone" style="display:none">`):

```html
<textarea class="paste-area" id="pasteIn"
  placeholder="One name per line&#10;e.g.&#10;Sarah Johnson&#10;Mark Davies&#10;Ali Hassan"
  oninput="handlePaste()"></textarea>
<div style="font-size:11px;color:var(--muted);margin-top:4px">One name per line. Numbered lists, bullets, and @ mentions are cleaned automatically.</div>
<div id="detectedPanel" style="display:none;margin-top:10px;border:1px solid #bfdbfe;border-radius:8px;overflow:hidden">
  <div class="detected-hdr">
    <span id="detectedCount"></span>
    <span class="detected-transformed" id="detectedTransformed" style="display:none"></span>
  </div>
  <div class="detected-list" id="detectedList"></div>
</div>
```

- [ ] **Step 3: Verify HTML renders**

Open `tools/name-resolver/index.html` in a browser. Sign in, go to Step 1, click "Paste names". The panel should not be visible yet (it's `display:none`). Open DevTools console and run:

```js
document.getElementById('detectedPanel').style.display = 'block';
document.getElementById('detectedCount').textContent = '✦ 3 names detected';
document.getElementById('detectedTransformed').textContent = '1 transformed';
document.getElementById('detectedTransformed').style.display = '';
document.getElementById('detectedList').innerHTML = `
  <div class="detected-row">
    <div class="detected-left"><span class="detected-dot"></span><span>Sarah Johnson</span></div>
    <div class="detected-tags"></div>
  </div>
  <div class="detected-row">
    <div class="detected-left"><span class="detected-dot"></span><span>John Smith</span></div>
    <div class="detected-tags"><span class="scrub-tag">@ stripped</span></div>
  </div>
  <div class="detected-row">
    <div class="detected-left"><span class="detected-dot"></span><span>Emma Davies</span></div>
    <div class="detected-tags"><span class="scrub-tag">Last, First → flipped</span></div>
  </div>`;
```

Expected: blue header bar with "✦ 3 names detected" left and "1 transformed" right, three name rows below, John Smith and Emma Davies each have an amber tag pill.

- [ ] **Step 4: Commit**

```bash
git add tools/name-resolver/index.html
git commit -m "feat: add detected names panel HTML and CSS for paste scrubber"
```

---

### Task 2: Implement the scrub pipeline (`scrubLine` + `scrubNames`)

**Files:**
- Modify: `tools/name-resolver/index.html` — `<script>` block, after the `const st = { ... }` state object

- [ ] **Step 1: Add the transform pipeline and scrub functions**

Find the line `// ── Init ──` comment in the script block. Insert the following block immediately before it:

```js
// ── Paste scrubber ────────────────────────────────────────────
const SCRUB_TRANSFORMS = [
  // 1. stripListPrefix — removes leading list markers (silent, no tag)
  v => {
    const cleaned = v.replace(/^\s*(\d+[\.\)]\s*|[•\*\u2013\u2014\-]\s*)/, '');
    return { value: cleaned };
  },
  // 2. stripMentions — removes leading @ symbol
  v => {
    if (!v.startsWith('@')) return { value: v };
    return { value: v.slice(1).trimStart(), tag: '@ stripped' };
  },
  // 3. stripTitles — removes leading honorifics (case-insensitive)
  v => {
    const m = v.match(/^(Dr\.|Mr\.|Ms\.|Mrs\.|Prof\.)\s+/i);
    if (!m) return { value: v };
    return { value: v.slice(m[0].length), tag: m[1] + ' removed' };
  },
  // 4. stripSuffixes — removes (parentheticals) and [brackets] anywhere
  v => {
    const tags = [];
    let out = v;
    out = out.replace(/\s*\(([^)]*)\)/g, (_, inner) => { tags.push('(' + inner + ') removed'); return ''; });
    out = out.replace(/\s*\[([^\]]*)\]/g, (_, inner) => { tags.push('[' + inner + '] removed'); return ''; });
    return tags.length ? { value: out.trim(), tag: tags[0] } : { value: out };
  },
  // 5. flipLastFirst — detects "Last, First" pattern and reverses to "First Last"
  v => {
    const SUFFIXES = /^(jr\.?|sr\.?|ii|iii|iv)$/i;
    const parts = v.split(',');
    if (parts.length !== 2) return { value: v };
    const last = parts[0].trim(), first = parts[1].trim();
    if (last.length < 2 || first.length < 2) return { value: v };
    const allWords = [...last.split(/\s+/), ...first.split(/\s+/)];
    if (allWords.some(w => SUFFIXES.test(w))) return { value: v };
    return { value: first + ' ' + last, tag: 'Last, First → flipped' };
  },
  // 6. normalizeSpace — collapses multiple spaces and trims (silent, no tag)
  v => ({ value: v.replace(/\s+/g, ' ').trim() })
];

function scrubLine(raw) {
  let value = raw.trim();
  const tags = [];
  for (const transform of SCRUB_TRANSFORMS) {
    const result = transform(value);
    value = result.value;
    if (result.tag) tags.push(result.tag);
  }
  return { name: value, tags };
}

function scrubNames(text) {
  const lines = text.includes('\n') ? text.split(/\r?\n/) : text.split(',');
  const seen = new Set();
  const results = [];
  for (const line of lines) {
    if (!line.trim()) continue;
    const { name, tags } = scrubLine(line);
    if (!name) continue;
    const key = name.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    results.push({ name, tags });
  }
  return results;
}
```

- [ ] **Step 2: Verify the pipeline in DevTools console**

Open the tool in a browser and paste the following into the DevTools console. All assertions must pass silently (no output means pass; a failed assert prints to console):

```js
// Helper
function scrubOne(line) { return scrubLine(line); }

// stripListPrefix (silent)
console.assert(scrubOne('1. Sarah Johnson').name === 'Sarah Johnson', 'numbered dot');
console.assert(scrubOne('2) Mark Davies').name === 'Mark Davies', 'numbered paren');
console.assert(scrubOne('• Ali Hassan').name === 'Ali Hassan', 'bullet');
console.assert(scrubOne('- Tom Baker').name === 'Tom Baker', 'hyphen');
console.assert(scrubOne('— Emma Clarke').name === 'Emma Clarke', 'em dash');

// stripMentions
console.assert(scrubOne('@John Smith').name === 'John Smith', 'mention name');
console.assert(scrubOne('@John Smith').tags.includes('@ stripped'), 'mention tag');
console.assert(scrubOne('John Smith').tags.length === 0, 'no mention tag on clean');

// stripTitles
console.assert(scrubOne('Dr. Rachel Green').name === 'Rachel Green', 'dr title');
console.assert(scrubOne('Dr. Rachel Green').tags[0] === 'Dr. removed', 'dr tag');
console.assert(scrubOne('Mrs. Jane Doe').name === 'Jane Doe', 'mrs title');

// stripSuffixes
console.assert(scrubOne('Rachel Green (IT)').name === 'Rachel Green', 'paren suffix');
console.assert(scrubOne('Rachel Green (IT)').tags[0] === '(IT) removed', 'paren tag');
console.assert(scrubOne('Tom Baker [Contractor]').name === 'Tom Baker', 'bracket suffix');
console.assert(scrubOne('Tom Baker [Contractor]').tags[0] === '[Contractor] removed', 'bracket tag');

// flipLastFirst
console.assert(scrubOne('Smith, John').name === 'John Smith', 'last first flip');
console.assert(scrubOne('Smith, John').tags.includes('Last, First → flipped'), 'flip tag');
console.assert(scrubOne('John Smith').name === 'John Smith', 'plain name untouched');
console.assert(scrubOne('Smith, Jr.').name === 'Smith, Jr.', 'suffix guard');

// Full pipeline combos
console.assert(scrubOne('1. @Dr. Rachel Green (IT)').name === 'Rachel Green', 'full combo');
console.assert(scrubOne('1. @Dr. Rachel Green (IT)').tags.join(',') === '@ stripped,Dr. removed,(IT) removed', 'combo tags');

// scrubNames dedup
const r = scrubNames('Sarah Johnson\nSARAH JOHNSON\nMark Davies');
console.assert(r.length === 2, 'dedup case-insensitive');
console.assert(r[0].name === 'Sarah Johnson', 'first name');
console.assert(r[1].name === 'Mark Davies', 'second name');

console.log('All scrubber assertions passed.');
```

- [ ] **Step 3: Commit**

```bash
git add tools/name-resolver/index.html
git commit -m "feat: add scrubLine and scrubNames transform pipeline"
```

---

### Task 3: Implement `renderDetectedPanel` and wire `handlePaste`

**Files:**
- Modify: `tools/name-resolver/index.html` — `<script>` block

- [ ] **Step 1: Add `renderDetectedPanel` function**

Find the `// ── Input mode ──` comment in the script. Insert the following function immediately before it:

```js
function renderDetectedPanel(items) {
  const panel       = document.getElementById('detectedPanel');
  const list        = document.getElementById('detectedList');
  const countEl     = document.getElementById('detectedCount');
  const transformEl = document.getElementById('detectedTransformed');

  if (!items.length) {
    panel.style.display = 'none';
    list.innerHTML = '';
    return;
  }

  const transformedCount = items.filter(i => i.tags.length > 0).length;
  countEl.textContent = '✦ ' + items.length + ' name' + (items.length === 1 ? '' : 's') + ' detected';

  if (transformedCount > 0) {
    transformEl.textContent = transformedCount + ' transformed';
    transformEl.style.display = '';
  } else {
    transformEl.style.display = 'none';
  }

  list.innerHTML = items.map(({ name, tags }) => `
    <div class="detected-row">
      <div class="detected-left">
        <span class="detected-dot"></span>
        <span>${esc(name)}</span>
      </div>
      <div class="detected-tags">
        ${tags.map(t => `<span class="scrub-tag">${esc(t)}</span>`).join('')}
      </div>
    </div>`).join('');

  panel.style.display = 'block';
}
```

- [ ] **Step 2: Replace `handlePaste` with scrubber-wired version**

Find the existing `function handlePaste()` in the script and replace it entirely with:

```js
function handlePaste() {
  const raw = document.getElementById('pasteIn').value.trim();
  if (!raw) {
    _parsedRows = [];
    renderDetectedPanel([]);
    updateS1([]);
    return;
  }
  const items = scrubNames(raw);
  renderDetectedPanel(items);
  _parsedRows = items.map(i => ({ Name: i.name }));
  // _selCol1 must be set here — renderColumnMapper() is skipped in paste mode
  // but buildNames() still reads row[_selCol1] when s1Next() is called
  _selCol1 = 'Name';
  updateS1(items.map(i => i.name));
}
```

- [ ] **Step 3: Verify paste → detected panel in browser**

Open the tool, sign in, go to Step 1, click "Paste names". Paste the following text into the textarea:

```
1. Sarah Johnson
2. Mark Davies
- @John Smith
• Dr. Rachel Green (IT)
Smith, Emma
Baker, Tom [Contractor]
mark davies
```

Expected:
- Panel appears with "✦ 6 names detected" (mark davies deduped) and "4 transformed"
- Sarah Johnson: no tags
- Mark Davies: no tags
- John Smith: `@ stripped`
- Rachel Green: `Dr. removed` + `(IT) removed`
- Emma Smith: `Last, First → flipped`
- Tom Baker: `[Contractor] removed`
- "6 names ready" appears next to Continue button
- Continue button becomes enabled

- [ ] **Step 4: Commit**

```bash
git add tools/name-resolver/index.html
git commit -m "feat: wire renderDetectedPanel and handlePaste to scrub pipeline"
```

---

### Task 4: Hide column mapper in paste mode, update `setMode` and `clearInput`

**Files:**
- Modify: `tools/name-resolver/index.html` — `setMode()` and `clearInput()` functions

- [ ] **Step 1: Update `setMode` to hide column mapper in paste mode**

Find `function setMode(m)` in the script. At the end of the function body, just before the closing `}`, add:

```js
  // Hide column mapper in paste mode — not needed with single implicit Name column
  document.getElementById('mapCard').style.display = m === 'paste' ? 'none' : '';
  // Clear detected panel when switching away from paste
  if (m !== 'paste') renderDetectedPanel([]);
```

- [ ] **Step 2: Update `clearInput` to reset the detected panel**

Find `function clearInput()`. At the end of the function body, just before the closing `}`, add:

```js
  renderDetectedPanel([]);
```

- [ ] **Step 3: Verify mode switching in browser**

Open the tool, sign in, go to Step 1.

Test A — paste mode hides mapper:
1. Click "Paste names" tab
2. Paste `Sarah Johnson` into the textarea
3. Confirm the "Name columns" card does NOT appear (it's hidden)
4. Confirm "Names detected" panel appears with 1 name

Test B — switching tabs clears panel:
1. While on paste tab with names detected, click "File (CSV)" tab
2. Confirm the detected panel disappears
3. Confirm the file drop zone is visible and no column mapper card appears yet (it only appears after a file is loaded)

Test C — clear button works:
1. Back on paste tab, paste a few names
2. Confirm panel shows
3. Reload the page (or manually call `clearInput()` in console)
4. Confirm panel is hidden and textarea is empty

- [ ] **Step 4: Commit**

```bash
git add tools/name-resolver/index.html
git commit -m "feat: hide column mapper in paste mode, clear detected panel on mode switch"
```

---

### Task 5: End-to-end integration test and wrap-up

**Files:**
- Modify: `tools/name-resolver/index.html` — no code changes, verification only

- [ ] **Step 1: Full workflow test with messy real-world paste**

Open the tool, sign in. Click "Paste names". Paste the following:

```
1. @Dr. Jane Smith (Finance)
2) Williams, Robert
• Mrs. Carol White [HR]
- @Tom Jones
Jane Smith
```

Expected detected panel:
- Jane Smith — `@ stripped`, `Dr. removed`, `(Finance) removed`
- Robert Williams — `Last, First → flipped`
- Carol White — `Mrs. removed`, `[HR] removed`
- Tom Jones — `@ stripped`
- (Jane Smith deduped — 5th line is a case-insensitive duplicate)
- Header: "✦ 4 names detected" · "4 transformed"
- Continue button enabled with "4 names ready"

- [ ] **Step 2: Proceed through resolve step**

Click "Continue to Resolve →". Click "▶ Start Lookup". Verify Graph lookups fire for all 4 names (watch Network tab — should see 4 displayName search requests). The scrubber output doesn't change the resolve flow, so any matches/not-founds are fine.

- [ ] **Step 3: Verify empty paste clears gracefully**

On paste tab, paste names, then clear the textarea manually. Expected: detected panel disappears, Continue button disables, "names ready" text clears.

- [ ] **Step 4: Final commit**

```bash
git add tools/name-resolver/index.html
git commit -m "feat: paste scrubber complete — named transform pipeline with detected names panel"
```

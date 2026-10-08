const ctx = typeof browser !== 'undefined' ? browser : chrome;

const $ = (id) => document.getElementById(id);
const deckSelect = $('deckSelect');
const deckBar = $('deckBar');
const newDeckBtn = $('newDeckBtn');
const newDeckForm = $('newDeckForm');
const newDeckName = $('newDeckName');
const wordList = $('wordList');
const listMeta = $('listMeta');
const searchInput = $('search');
const today = $('today');
const syncBtn = $('syncBtn');
const accountStatus = $('accountStatus');
const authBtn = $('authBtn');
const app = $('app');
const themePick = $('themePick');

// The word card currently open in the inline editor, if any.
let editingId = null;
// The save-word shortcut as the browser reports it (the user may rebind it).
let shortcut = 'Ctrl+Shift+L';

init();

// ---- theme ----

function setupTheme() {
  HankoUI.mount(document);
  $('mark').innerHTML = HankoUI.ENSO;
  fillIcons(document);
  for (const name of HankoUI.ORDER) {
    const b = document.createElement('button');
    b.className = `swatch ${name}`;
    b.setAttribute('role', 'radio');
    b.title = HankoUI.THEMES[name].label;
    b.setAttribute('aria-label', HankoUI.THEMES[name].label);
    b.dataset.theme = name;
    b.addEventListener('click', () => HankoUI.save(name));
    themePick.appendChild(b);
  }
  // Applied here and whenever another surface changes it; the background
  // swaps the toolbar icon off the same storage change.
  HankoUI.watch((name) => {
    HankoUI.apply(document.documentElement, name);
    document.body.dataset.hkTheme = name;
    for (const b of themePick.children) b.setAttribute('aria-checked', String(b.dataset.theme === name));
  });
}

function fillIcons(root) {
  for (const el of root.querySelectorAll('[data-icon]')) el.innerHTML = HankoUI.ICONS[el.dataset.icon] || '';
}

function showAccountError(message) {
  accountStatus.textContent = message;
  accountStatus.classList.add('error');
}

async function init() {
  setupTheme();
  try {
    const cmd = (await ctx.commands.getAll()).find((c) => c.name === 'save-word');
    if (cmd && cmd.shortcut) shortcut = cmd.shortcut;
  } catch (e) {
    // keep the manifest default
  }
  await refreshAuthUI();
  await refreshDeckSelect();
  await render();

  // Pull in any changes saved on the website or another device.
  syncNow();

  deckSelect.addEventListener('change', () => {
    editingId = null;
    render();
  });

  newDeckBtn.addEventListener('click', () => {
    newDeckForm.classList.toggle('hidden');
    newDeckName.focus();
  });

  newDeckForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const name = newDeckName.value.trim();
    if (!name) return;
    const store = await getStore();
    const now = Date.now();
    const deck = { id: crypto.randomUUID(), name, createdAt: now, updatedAt: now, deleted: false };
    store.decks.push(deck);
    await setStore(store);
    newDeckName.value = '';
    newDeckForm.classList.add('hidden');
    await refreshDeckSelect(deck.id);
    await render();
    syncNow();
  });

  searchInput.addEventListener('input', () => {
    editingId = null;
    render();
  });
  searchInput.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && searchInput.value) {
      e.preventDefault();
      searchInput.value = '';
      render();
    }
  });
  // "/" jumps to search from anywhere that isn't a text field.
  document.addEventListener('keydown', (e) => {
    const typing = e.target.closest && e.target.closest('input, textarea, select');
    if (e.key === '/' && !typing) {
      e.preventDefault();
      searchInput.focus();
    }
  });

  $('openWebBtn').addEventListener('click', () => openSite('/decks'));
  $('deleteDeckBtn').addEventListener('click', deleteCurrentDeck);
  authBtn.addEventListener('click', onAuthClick);
  syncBtn.addEventListener('click', () => syncNow(true));

  // The badge count can change under us (background alarm, a save elsewhere).
  ctx.storage.onChanged.addListener((changes, area) => {
    if (area === 'local' && changes.dueNow) renderToday();
  });
}

// ---- auth / sync ----

let signedIn = false;

async function refreshAuthUI() {
  accountStatus.classList.remove('error');
  if (!window.VocabSync || !VocabSync.configured()) {
    accountStatus.textContent = 'Синк тохируулаагүй';
    authBtn.style.display = 'none';
    signedIn = false;
    syncBtn.hidden = true;
    renderToday();
    return;
  }
  const s = await VocabSync.status();
  signedIn = s.signedIn;
  syncBtn.hidden = !s.signedIn;
  if (s.signedIn) {
    accountStatus.textContent = s.email || 'Синк хийсэн';
    accountStatus.title = 'Синк хийгдэж байна';
    authBtn.textContent = 'Гарах';
  } else {
    accountStatus.textContent = 'Нэвтрээгүй';
    authBtn.textContent = 'Нэвтрэх';
  }
  renderToday();
}

async function onAuthClick() {
  if (!window.VocabSync) return;
  const s = await VocabSync.status();
  if (s.signedIn) {
    const ok = await HankoUI.confirm(app, {
      title: 'Гарах уу?',
      body: 'Энэ төхөөрөмж дээрх үгс хэвээр үлдэнэ, зөвхөн синк зогсоно.',
      confirmLabel: 'Гарах',
    });
    if (!ok) return;
  }
  authBtn.disabled = true;
  if (s.signedIn) {
    await VocabSync.signOut();
  } else {
    accountStatus.textContent = 'Нэвтэрч байна…';
    const res = await VocabSync.signIn();
    if (!res.ok) {
      authBtn.disabled = false;
      showAccountError(`Нэвтэрч чадсангүй: ${res.error}`);
      return;
    }
  }
  authBtn.disabled = false;
  await refreshAuthUI();
  await refreshDeckSelect();
  await render();
}

// Sync, then refresh the due count; re-render if anything changed. `manual`
// is the header button: it spins, and says so when it fails.
let syncing = false;
async function syncNow(manual = false) {
  if (!window.VocabSync || !VocabSync.configured() || syncing) return;
  syncing = true;
  syncBtn.classList.add('spinning');
  try {
    const res = await VocabSync.fullSync();
    if (res.signedIn && (res.pulled || res.pushed || manual)) {
      await refreshDeckSelect(deckSelect.value);
      await render();
    }
    if (res.signedIn) await VocabSync.refreshDue();
  } catch (e) {
    console.warn('Sync failed:', e);
    if (manual) HankoUI.snack(app, 'Синк хийж чадсангүй — сүлжээгээ шалгана уу');
  } finally {
    syncing = false;
    syncBtn.classList.remove('spinning');
  }
}

// Edits wait a moment before syncing, so an undo inside the snackbar's window
// never reaches the server as a delete followed by a restore.
let syncTimer = null;
function syncSoon(ms = 4500) {
  clearTimeout(syncTimer);
  syncTimer = setTimeout(() => syncNow(), ms);
}
// The popup can close before the timer fires — the background's 5-minute
// alarm picks the edit up then, but ask it now so it doesn't wait that long.
window.addEventListener('pagehide', () => {
  if (syncTimer) {
    try {
      ctx.runtime.sendMessage({ type: 'SYNC_NOW' });
    } catch (e) {
      // the alarm will catch it
    }
  }
});

// ---- today card ----

async function renderToday() {
  if (!window.VocabSync || !VocabSync.configured()) {
    today.hidden = true;
    return;
  }
  today.hidden = false;
  if (!signedIn) {
    today.innerHTML = `
      <div class="today-text">
        <div class="today-hint">Нэвтэрвэл үгс тань вэб, утсан дээр синк хийгдэж, давтах карт энд харагдана.</div>
      </div>
      <button class="hk-btn hk-primary" data-act="signin">Нэвтрэх</button>`;
    today.querySelector('[data-act="signin"]').addEventListener('click', onAuthClick);
    return;
  }
  const { dueNow } = await ctx.storage.local.get('dueNow');
  if (typeof dueNow !== 'number') {
    today.innerHTML = `<div class="today-text"><div class="today-label">Өнөөдөр давтах</div><div class="today-count">…</div></div>`;
    return;
  }
  if (dueNow === 0) {
    today.innerHTML = `
      <div class="today-text">
        <div class="today-label">Өнөөдөр давтах</div>
        <div class="today-done">Бүгдийг давтлаа ✓</div>
      </div>
      <button class="hk-btn hk-quiet" data-act="stats">Статистик</button>`;
    today.querySelector('[data-act="stats"]').addEventListener('click', () => openSite('/decks/stats'));
    return;
  }
  today.innerHTML = `
    <div class="today-text">
      <div class="today-label">Өнөөдөр давтах</div>
      <div class="today-count">${dueNow}<small>карт</small></div>
    </div>
    <button class="hk-btn hk-primary" data-act="review">Давтах <span class="hk-ico" data-icon="external" style="width:13px;height:13px"></span></button>`;
  fillIcons(today);
  today.querySelector('[data-act="review"]').addEventListener('click', () => openSite('/decks/review'));
}

// ---- store helpers ----

async function getStore() {
  const data = await ctx.storage.local.get(['decks', 'words']);
  return { decks: data.decks || [], words: data.words || [] };
}

async function setStore(store) {
  await ctx.storage.local.set(store);
}

// Visible (non-tombstoned) items.
function activeDecks(store) {
  return store.decks.filter((d) => !d.deleted);
}
function activeWords(store, deckId) {
  return store.words.filter((w) => !w.deleted && w.deckId === deckId);
}

async function refreshDeckSelect(selectId) {
  const store = await getStore();
  const decks = activeDecks(store);
  deckSelect.innerHTML = '';
  if (decks.length === 0) {
    const opt = document.createElement('option');
    opt.value = '';
    opt.textContent = 'Багц алга';
    deckSelect.appendChild(opt);
    return;
  }
  decks.forEach((deck) => {
    const opt = document.createElement('option');
    opt.value = deck.id;
    opt.textContent = `${deck.name} (${activeWords(store, deck.id).length})`;
    deckSelect.appendChild(opt);
  });
  // Default to the deck last saved into (or picked here).
  const { lastDeckId } = await ctx.storage.local.get('lastDeckId');
  const want = selectId || lastDeckId;
  if (want && decks.some((d) => d.id === want)) deckSelect.value = want;
}

// ---- word list ----

// Matches term, reading and both meanings; kana/kanji and Latin alike.
function matches(word, q) {
  return [word.term, word.reading, word.meaning, word.meaningMn].some(
    (f) => f && f.toLowerCase().includes(q)
  );
}

async function render() {
  const store = await getStore();
  const q = searchInput.value.trim().toLowerCase();
  const searching = q.length > 0;
  deckBar.hidden = searching;
  newDeckForm.classList.add('hidden');

  wordList.innerHTML = '';
  listMeta.textContent = '';

  if (searching) {
    const deckNames = new Map(activeDecks(store).map((d) => [d.id, d.name]));
    const found = store.words
      .filter((w) => !w.deleted && deckNames.has(w.deckId) && matches(w, q))
      .sort((a, b) => b.dateAdded - a.dateAdded);
    listMeta.textContent = found.length ? `${found.length} үг олдлоо` : '';
    if (!found.length) {
      wordList.innerHTML = `<div class="empty-state">“${escapeHtml(searchInput.value.trim())}” олдсонгүй.</div>`;
      return;
    }
    for (const w of found.slice(0, 200)) wordList.appendChild(wordCard(w, { q, deckName: deckNames.get(w.deckId) }));
    return;
  }

  const deckId = deckSelect.value;
  // Remember the selected deck so saves (and the PDF quick-save) target it.
  if (deckId) ctx.storage.local.set({ lastDeckId: deckId });

  if (!deckId) {
    wordList.innerHTML = `<div class="empty-state"><span class="hk-mark">${HankoUI.ENSO}</span>Багц үүсгээд, дурын хуудаснаас үг хадгална уу — үгээ сонгоод баруун товч, эсвэл <kbd>${escapeHtml(shortcut)}</kbd>.</div>`;
    return;
  }

  const words = activeWords(store, deckId).sort((a, b) => b.dateAdded - a.dateAdded);
  if (words.length === 0) {
    wordList.innerHTML = `<div class="empty-state"><span class="hk-mark">${HankoUI.ENSO}</span>Энэ багцад үг алга.<br>Хуудаснаас үг сонгоод <kbd>${escapeHtml(shortcut)}</kbd> дарна уу.</div>`;
    return;
  }
  listMeta.textContent = `${words.length} үг`;
  for (const w of words) wordList.appendChild(wordCard(w, {}));
}

function wordCard(word, { q = '', deckName = '' }) {
  if (word.id === editingId) return editCard(word);
  const row = document.createElement('div');
  row.className = 'word';
  const reading = word.reading && word.reading !== word.term ? word.reading : '';
  row.innerHTML = `
    <div class="word-main">
      <div class="word-head">
        <span class="word-term hk-jp">${hl(word.term, q)}</span>
        ${reading ? `<span class="word-reading hk-jp">${hl(reading, q)}</span>` : ''}
      </div>
      ${word.meaningMn ? `<div class="word-mn">${hl(word.meaningMn, q)}</div>` : ''}
      ${word.meaning ? `<div class="word-en">${hl(word.meaning, q)}</div>` : ''}
      ${deckName ? `<span class="word-deck">${escapeHtml(deckName)}</span>` : ''}
    </div>
    <div class="word-tools">
      ${word.sourceUrl ? `<button class="tool quiet" data-act="source" title="Эх хуудас нээх" aria-label="Эх хуудас нээх"><span class="hk-ico" data-icon="link"></span></button>` : ''}
      <button class="tool quiet" data-act="edit" title="Засах" aria-label="Засах"><span class="hk-ico" data-icon="edit"></span></button>
      <button class="tool" data-act="speak" title="Дуудах" aria-label="Дуудах"><span class="hk-ico" data-icon="speak"></span></button>
    </div>`;
  fillIcons(row);
  const speakBtn = row.querySelector('[data-act="speak"]');
  speakBtn.addEventListener('click', () => HankoUI.speak(word.reading || word.term, speakBtn));
  row.querySelector('[data-act="edit"]').addEventListener('click', () => {
    editingId = word.id;
    render();
  });
  const src = row.querySelector('[data-act="source"]');
  if (src) src.addEventListener('click', () => ctx.tabs.create({ url: word.sourceUrl }));
  return row;
}

// A word card in edit mode: reading and both meanings, delete with undo.
function editCard(word) {
  const row = document.createElement('div');
  row.className = 'word editing';
  row.innerHTML = `
    <div class="word-head"><span class="word-term hk-jp">${escapeHtml(word.term)}</span></div>
    <label class="hk-label">Дуудлага</label>
    <input class="hk-field hk-jp" data-f="reading" />
    <label class="hk-label">Утга (монгол)</label>
    <textarea class="hk-field" data-f="meaningMn" rows="1"></textarea>
    <label class="hk-label">Утга (англи)</label>
    <textarea class="hk-field" data-f="meaning" rows="1"></textarea>
    <div class="edit-actions">
      <button class="hk-btn hk-ghost hk-danger-text" data-act="delete"><span class="hk-ico" data-icon="trash" style="width:14px;height:14px"></span>Устгах</button>
      <span class="spacer"></span>
      <button class="hk-btn hk-ghost" data-act="cancel">Болих</button>
      <button class="hk-btn hk-primary" data-act="save">Хадгалах</button>
    </div>`;
  fillIcons(row);
  const f = (k) => row.querySelector(`[data-f="${k}"]`);
  f('reading').value = word.reading || '';
  f('meaningMn').value = word.meaningMn || '';
  f('meaning').value = word.meaning || '';

  // Same rule as the save panel: a changed English meaning re-translates the
  // Mongolian; editing the Mongolian never translates back.
  let lastEn = (word.meaning || '').trim();
  f('meaning').addEventListener('blur', () => {
    const text = f('meaning').value.trim();
    if (!text || text === lastEn) return;
    lastEn = text;
    ctx.runtime.sendMessage({ type: 'TRANSLATE', text }, (resp) => {
      if (resp && resp.ok && resp.mongolian) f('meaningMn').value = resp.mongolian;
    });
  });

  const close = () => {
    editingId = null;
    render();
  };
  row.querySelector('[data-act="cancel"]').addEventListener('click', close);
  row.querySelector('[data-act="save"]').addEventListener('click', async () => {
    await updateWord(word.id, {
      reading: f('reading').value.trim(),
      meaningMn: f('meaningMn').value.trim(),
      meaning: f('meaning').value.trim(),
    });
    close();
    syncSoon(800);
  });
  row.querySelector('[data-act="delete"]').addEventListener('click', async () => {
    await updateWord(word.id, { deleted: true });
    editingId = null;
    await refreshDeckSelect(deckSelect.value);
    await render();
    syncSoon();
    HankoUI.snack(app, `“${word.term}” устгагдлаа`, {
      action: {
        label: 'Буцаах',
        run: async () => {
          await updateWord(word.id, { deleted: false });
          await refreshDeckSelect(deckSelect.value);
          await render();
          syncSoon(800);
        },
      },
    });
  });
  row.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      e.preventDefault();
      close();
    } else if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
      e.preventDefault();
      row.querySelector('[data-act="save"]').click();
    }
  });
  setTimeout(() => f('meaningMn').focus(), 0);
  return row;
}

async function updateWord(id, patch) {
  const store = await getStore();
  const w = store.words.find((x) => x.id === id);
  if (!w) return;
  Object.assign(w, patch, { updatedAt: Date.now() });
  await setStore(store);
}

// ---- web ----

function openSite(path) {
  const cfg = globalThis.VOCAB_CONFIG || {};
  const base = (cfg.SITE_URL || '').replace(/\/$/, '');
  if (!base) {
    showAccountError('Вэб хаяг тохируулаагүй (config.js · SITE_URL)');
    return;
  }
  ctx.tabs.create({ url: `${base}${path}` });
}

async function deleteCurrentDeck() {
  const deckId = deckSelect.value;
  if (!deckId) return;
  const store = await getStore();
  const deck = store.decks.find((d) => d.id === deckId);
  if (!deck) return;
  const count = activeWords(store, deckId).length;
  const ok = await HankoUI.confirm(app, {
    title: 'Багц устгах уу?',
    body: `“${deck.name}” багц болон доторх ${count} үг устна. Буцаах боломжгүй.`,
    danger: true,
  });
  if (!ok) return;

  // Tombstone the deck and its words so the deletion propagates on sync.
  const now = Date.now();
  deck.deleted = true;
  deck.updatedAt = now;
  store.words.forEach((w) => {
    if (w.deckId === deckId) {
      w.deleted = true;
      w.updatedAt = now;
    }
  });
  await setStore(store);
  await refreshDeckSelect();
  await render();
  syncNow();
}

// ---- text ----

function escapeHtml(s) {
  const div = document.createElement('div');
  div.textContent = s;
  return div.innerHTML;
}

// Escaped text with the search query highlighted.
function hl(text, q) {
  if (!q) return escapeHtml(text);
  const i = text.toLowerCase().indexOf(q);
  if (i < 0) return escapeHtml(text);
  return (
    escapeHtml(text.slice(0, i)) +
    `<mark>${escapeHtml(text.slice(i, i + q.length))}</mark>` +
    escapeHtml(text.slice(i + q.length))
  );
}

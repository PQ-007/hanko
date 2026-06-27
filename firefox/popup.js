const ctx = typeof browser !== 'undefined' ? browser : chrome;

const deckSelect = document.getElementById('deckSelect');
const newDeckBtn = document.getElementById('newDeckBtn');
const newDeckForm = document.getElementById('newDeckForm');
const newDeckName = document.getElementById('newDeckName');
const confirmNewDeck = document.getElementById('confirmNewDeck');
const wordList = document.getElementById('wordList');
const openWebBtn = document.getElementById('openWebBtn');
const deleteDeckBtn = document.getElementById('deleteDeckBtn');
const accountStatus = document.getElementById('accountStatus');
const authBtn = document.getElementById('authBtn');

init();

async function init() {
  await refreshAuthUI();
  await refreshDeckSelect();
  await renderWords();

  // Pull in any changes saved on the website or another device.
  syncNow();

  deckSelect.addEventListener('change', renderWords);

  newDeckBtn.addEventListener('click', () => {
    newDeckForm.classList.toggle('hidden');
    newDeckName.focus();
  });

  confirmNewDeck.addEventListener('click', async () => {
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
    await renderWords();
    syncNow();
  });

  openWebBtn.addEventListener('click', openWeb);
  deleteDeckBtn.addEventListener('click', deleteCurrentDeck);
  authBtn.addEventListener('click', onAuthClick);
}

// ---- auth / sync ----

async function refreshAuthUI() {
  if (!window.VocabSync || !VocabSync.configured()) {
    accountStatus.textContent = 'Синк тохируулаагүй';
    authBtn.style.display = 'none';
    return;
  }
  const s = await VocabSync.status();
  if (s.signedIn) {
    accountStatus.textContent = s.email ? `Синк хийсэн · ${s.email}` : 'Синк хийсэн';
    authBtn.textContent = 'Гарах';
  } else {
    accountStatus.textContent = 'Нэвтрээгүй';
    authBtn.textContent = 'Нэвтрэх';
  }
}

async function onAuthClick() {
  if (!window.VocabSync) return;
  const s = await VocabSync.status();
  authBtn.disabled = true;
  if (s.signedIn) {
    await VocabSync.signOut();
  } else {
    accountStatus.textContent = 'Нэвтэрч байна…';
    const res = await VocabSync.signIn();
    if (!res.ok) alert(`Нэвтрэлт амжилтгүй: ${res.error}`);
  }
  authBtn.disabled = false;
  await refreshAuthUI();
  await refreshDeckSelect();
  await renderWords();
}

// Sync in the background; refresh the UI if anything changed.
async function syncNow() {
  if (!window.VocabSync || !VocabSync.configured()) return;
  try {
    const res = await VocabSync.fullSync();
    if (res.signedIn && (res.pulled || res.pushed)) {
      await refreshDeckSelect(deckSelect.value);
      await renderWords();
    }
  } catch (e) {
    console.warn('Sync failed:', e);
  }
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
  if (selectId) deckSelect.value = selectId;
}

async function renderWords() {
  const store = await getStore();
  const deckId = deckSelect.value;
  // Remember the selected deck so the background quick-save (PDFs) targets it.
  if (deckId) ctx.storage.local.set({ lastDeckId: deckId });
  const words = activeWords(store, deckId);

  wordList.innerHTML = '';

  if (!deckId) {
    wordList.innerHTML = '<div class="empty-state">Багц үүсгээд, дурын хуудаснаас үг хадгална уу (сонгосон үг дээр баруун товч дарах, эсвэл товчлуур ашиглах).</div>';
    return;
  }

  if (words.length === 0) {
    wordList.innerHTML = '<div class="empty-state">Энэ багцад хадгалсан үг алга.</div>';
    return;
  }

  words
    .sort((a, b) => b.dateAdded - a.dateAdded)
    .forEach((word) => {
      const row = document.createElement('div');
      row.className = 'word-row';
      row.innerHTML = `
        <div class="word-main">
          <span class="word-term">${escapeHtml(word.term)}</span>
          ${word.reading ? `<span class="word-reading">${escapeHtml(word.reading)}</span>` : ''}
          <div class="word-meaning">${escapeHtml(word.meaning || '')}</div>
          ${word.meaningMn ? `<div class="word-mongolian">${escapeHtml(word.meaningMn)}</div>` : ''}
        </div>
        <button class="word-remove" title="Remove" data-id="${word.id}">✕</button>
      `;
      row.querySelector('.word-remove').addEventListener('click', async () => {
        const s = await getStore();
        // Tombstone so the deletion syncs everywhere.
        const w = s.words.find((x) => x.id === word.id);
        if (w) {
          w.deleted = true;
          w.updatedAt = Date.now();
        }
        await setStore(s);
        await refreshDeckSelect(deckId);
        await renderWords();
        syncNow();
      });
      wordList.appendChild(row);
    });
}

// Open the full web editor (deck dashboard) where you can edit/organize freely
// and export to .apkg/.txt.
function openWeb() {
  const cfg = globalThis.VOCAB_CONFIG || {};
  const base = (cfg.SITE_URL || '').replace(/\/$/, '');
  if (!base) {
    alert('Вэб хаяг тохируулаагүй байна (config.js-ийн SITE_URL).');
    return;
  }
  ctx.tabs.create({ url: `${base}/decks` });
}

async function deleteCurrentDeck() {
  const deckId = deckSelect.value;
  if (!deckId) return;
  const store = await getStore();
  const deck = store.decks.find((d) => d.id === deckId);
  if (!deck) return;
  if (!confirm(`“${deck.name}” багц болон доторх бүх үгийг устгах уу? Буцаах боломжгүй.`)) return;

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
  await renderWords();
  syncNow();
}

function escapeHtml(s) {
  const div = document.createElement('div');
  div.textContent = s;
  return div.innerHTML;
}

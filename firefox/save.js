// Standalone "save word" form, opened as a small popup window when the in-page
// overlay can't be injected (e.g. Firefox's PDF viewer or file:// pages). Same
// flow as the content-script overlay: Jisho lookup, pick/create a deck, save.

const ctx = typeof browser !== 'undefined' ? browser : chrome;

const term = (new URLSearchParams(location.search).get('term') || '').trim();

const $ = (id) => document.getElementById(id);
const termEl = $('term');
const loadingEl = $('loading');
const readingEl = $('reading');
const meaningEl = $('meaning');
const deckSelect = $('deckSelect');
const newDeckRow = $('newDeckRow');

termEl.textContent = term;
document.title = term ? `Save: ${term}` : 'Save word';

init();

async function init() {
  await populateDeckSelect();

  deckSelect.addEventListener('change', () => {
    newDeckRow.classList.toggle('visible', deckSelect.value === '__new__');
  });

  $('addDeck').addEventListener('click', async () => {
    const name = $('newDeckName').value.trim();
    if (!name) return;
    const deck = await createDeck(name);
    await populateDeckSelect(deck.id);
    newDeckRow.classList.remove('visible');
  });

  $('cancel').addEventListener('click', () => window.close());
  $('save').addEventListener('click', onSave);

  // Kick off the dictionary lookup (handled in the background to dodge page CSP).
  ctx.runtime.sendMessage({ type: 'LOOKUP_WORD', term }, (response) => {
    loadingEl.remove();
    if (response && response.ok && response.result) {
      if (response.result.reading) readingEl.value = response.result.reading;
      if (response.result.meaning) meaningEl.value = response.result.meaning;
    }
  });
}

async function onSave() {
  let deckId = deckSelect.value;
  if (deckId === '__new__') {
    const name = $('newDeckName').value.trim() || 'Untitled deck';
    const deck = await createDeck(name);
    deckId = deck.id;
  }
  if (!deckId) return;

  await saveWord({
    deckId,
    term,
    reading: readingEl.value.trim(),
    meaning: meaningEl.value.trim()
  });

  // Brief confirmation, then close the window.
  document.body.innerHTML = '<div class="saved">Saved ✓</div>';
  setTimeout(() => window.close(), 600);
}

// ---- storage helpers (shared shape with popup.js / content.js) ----

async function getStore() {
  const data = await ctx.storage.local.get(['decks', 'words']);
  return { decks: data.decks || [], words: data.words || [] };
}

async function setStore(store) {
  await ctx.storage.local.set(store);
}

async function createDeck(name) {
  const store = await getStore();
  const now = Date.now();
  const deck = { id: crypto.randomUUID(), name, createdAt: now, updatedAt: now, deleted: false };
  store.decks.push(deck);
  await setStore(store);
  return deck;
}

async function saveWord(word) {
  const store = await getStore();
  const now = Date.now();
  store.words.push({ id: crypto.randomUUID(), dateAdded: now, updatedAt: now, deleted: false, ...word });
  await setStore(store);
  if (word.deckId) await ctx.storage.local.set({ lastDeckId: word.deckId });
  try {
    ctx.runtime.sendMessage({ type: 'SYNC_NOW' });
  } catch {
    // ignore if background isn't reachable
  }
}

async function populateDeckSelect(selectId) {
  const store = await getStore();
  const decks = store.decks.filter((d) => !d.deleted);
  deckSelect.innerHTML = '';
  if (decks.length === 0) {
    const opt = document.createElement('option');
    opt.value = '__new__';
    opt.textContent = '(no decks yet — create one)';
    deckSelect.appendChild(opt);
    newDeckRow.classList.add('visible');
  } else {
    decks.forEach((deck) => {
      const opt = document.createElement('option');
      opt.value = deck.id;
      opt.textContent = deck.name;
      deckSelect.appendChild(opt);
    });
    const newOpt = document.createElement('option');
    newOpt.value = '__new__';
    newOpt.textContent = '+ New deck…';
    deckSelect.appendChild(newOpt);
  }
  // Default to the last-used deck when present.
  const { lastDeckId } = await ctx.storage.local.get('lastDeckId');
  if (selectId) deckSelect.value = selectId;
  else if (lastDeckId && decks.some((d) => d.id === lastDeckId)) deckSelect.value = lastDeckId;
}

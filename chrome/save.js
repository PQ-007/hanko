// Standalone "save word" form, opened as a small popup window when the in-page
// overlay can't be injected (e.g. Firefox's PDF viewer or file:// pages). Same
// flow as the content-script overlay: Jisho lookup, pick/create a deck, save.

const ctx = typeof browser !== 'undefined' ? browser : chrome;

// Mutable: Jisho lookup may replace a conjugated form with its dictionary form.
let term = (new URLSearchParams(location.search).get('term') || '').trim();

const $ = (id) => document.getElementById(id);
const termEl = $('term');
const loadingEl = $('loading');
const readingEl = $('reading');
const meaningEl = $('meaning');
const mongolianEl = $('mongolian');
const deckSelect = $('deckSelect');
const newDeckRow = $('newDeckRow');

termEl.textContent = term;

// Same theme as the popup (and the app): applied now and on any change.
HankoUI.mount(document);
$('mark').innerHTML = HankoUI.ENSO;
$('speakIco').innerHTML = HankoUI.ICONS.speak;
$('saveKey').textContent = /Mac|iPhone|iPad/.test(navigator.platform) ? '⌘↵' : 'Ctrl↵';
HankoUI.watch((name) => HankoUI.apply(document.documentElement, name));
document.title = term ? `Хадгалах: ${term}` : 'Үг хадгалах';

// The English value last translated (so blurring unchanged text doesn't
// re-translate; editing Mongolian never translates in reverse).
let lastEn = '';

function translateMeaning() {
  const text = meaningEl.value.trim();
  if (!text || text === lastEn) return;
  lastEn = text;
  ctx.runtime.sendMessage({ type: 'TRANSLATE', text }, (resp) => {
    if (resp && resp.ok && resp.mongolian) mongolianEl.value = resp.mongolian;
  });
}

init();

async function init() {
  await populateDeckSelect();

  // Pull the account's decks/words so the dropdown includes website decks, not
  // just local ones (no-op when signed out / unconfigured).
  if (globalThis.VocabSync && VocabSync.configured()) {
    VocabSync.fullSync()
      .then((r) => {
        if (r && r.signedIn) populateDeckSelect(deckSelect.value || undefined);
      })
      .catch(() => {});
  }

  deckSelect.addEventListener('change', () => {
    newDeckRow.classList.toggle('visible', deckSelect.value === '__new__');
    checkDuplicate();
  });
  checkDuplicate();

  $('speak').addEventListener('click', () => HankoUI.speak(readingEl.value.trim() || term, $('speak')));
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') window.close();
    else if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
      e.preventDefault();
      onSave();
    }
  });

  $('addDeck').addEventListener('click', async () => {
    const name = $('newDeckName').value.trim();
    if (!name) return;
    const deck = await createDeck(name);
    await populateDeckSelect(deck.id);
    newDeckRow.classList.remove('visible');
    checkDuplicate();
  });

  $('cancel').addEventListener('click', () => window.close());
  $('save').addEventListener('click', onSave);

  // Auto-translate English -> Mongolian on Enter/blur (only when changed).
  meaningEl.addEventListener('blur', translateMeaning);
  meaningEl.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      translateMeaning();
    }
  });

  // Kick off the dictionary lookup (handled in the background to dodge page CSP).
  ctx.runtime.sendMessage({ type: 'LOOKUP_WORD', term }, (response) => {
    loadingEl.remove();
    if (response && response.ok && response.result) {
      const r = response.result;
      if (r.word && r.word !== term) {
        term = r.word; // use the dictionary form (普通形)
        termEl.textContent = term;
        checkDuplicate();
      }
      if (r.reading) readingEl.value = r.reading;
      if (r.meaning) {
        meaningEl.value = r.meaning;
        lastEn = r.meaning.trim();
      }
      if (r.mongolian) mongolianEl.value = r.mongolian;
    }
  });
}

// Say so up front when the word is already in the chosen deck.
async function checkDuplicate() {
  const id = deckSelect.value;
  $('dup').classList.toggle('visible', !!id && id !== '__new__' && (await isDuplicate(id, term)));
}

let saving = false;
async function onSave() {
  if (saving) return;
  let deckId = deckSelect.value;
  if (deckId === '__new__') {
    const name = $('newDeckName').value.trim() || 'Нэргүй багц';
    const deck = await createDeck(name);
    deckId = deck.id;
  }
  if (!deckId) return;
  saving = true;

  // The word may already be in the chosen deck — let the user decide.
  if (await isDuplicate(deckId, term)) {
    const ok = await HankoUI.confirm($('app'), {
      title: 'Давхардсан үг',
      body: `“${term}” энэ багцад аль хэдийн байна. Дахин нэмэх үү?`,
      confirmLabel: 'Дахин нэмэх',
    });
    if (!ok) {
      saving = false;
      return;
    }
  }

  await saveWord({
    deckId,
    term,
    reading: readingEl.value.trim(),
    meaning: meaningEl.value.trim(),
    meaningMn: mongolianEl.value.trim()
  });

  // Brief confirmation, then close the window.
  const deckName = [...deckSelect.options].find((o) => o.value === deckId)?.textContent || '';
  $('app').innerHTML = `<div class="saved"><span class="hk-mark">${HankoUI.ENSO}</span><div class="hk-toast"></div></div>`;
  $('app').querySelector('.hk-toast').textContent = deckName && deckName !== '+ Шинэ багц…' ? `“${deckName}”-д хадгаллаа ✓` : 'Хадгаллаа ✓';
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

async function isDuplicate(deckId, term) {
  const store = await getStore();
  return store.words.some((w) => !w.deleted && w.deckId === deckId && w.term === term);
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
    opt.textContent = '(багц алга — үүсгэнэ үү)';
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
    newOpt.textContent = '+ Шинэ багц…';
    deckSelect.appendChild(newOpt);
  }
  // Default to the last-used deck when present.
  const { lastDeckId } = await ctx.storage.local.get('lastDeckId');
  if (selectId) deckSelect.value = selectId;
  else if (lastDeckId && decks.some((d) => d.id === lastDeckId)) deckSelect.value = lastDeckId;
}

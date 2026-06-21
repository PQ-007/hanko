// Content script injected on every page.
// Shows a small "save this word" panel triggered by the context menu or a
// keyboard shortcut, auto-fills reading/meaning via the background lookup,
// and writes the saved word straight into extension storage.

const ctx = typeof browser !== 'undefined' ? browser : chrome;

let activeOverlay = null;

ctx.runtime.onMessage.addListener((message) => {
  if (message?.type === 'SHOW_SAVE_OVERLAY') {
    if (message.text) showOverlay(message.text);
  } else if (message?.type === 'TRIGGER_SAVE_FROM_SELECTION') {
    const text = (window.getSelection()?.toString() || '').trim();
    if (text) showOverlay(text);
  }
});

function removeOverlay() {
  if (activeOverlay) {
    activeOverlay.remove();
    activeOverlay = null;
  }
}

async function showOverlay(term) {
  removeOverlay();

  const host = document.createElement('div');
  host.style.position = 'fixed';
  host.style.bottom = '24px';
  host.style.right = '24px';
  host.style.zIndex = '2147483647';
  document.documentElement.appendChild(host);
  activeOverlay = host;

  const shadow = host.attachShadow({ mode: 'open' });
  shadow.innerHTML = `
    <style>
      :host { all: initial; }
      .panel {
        width: 300px;
        background: #FAF7F0;
        border: 1px solid #D8D0BE;
        border-radius: 10px;
        box-shadow: 0 8px 24px rgba(31,41,51,0.18);
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
        color: #1F2933;
        padding: 14px 16px 16px;
      }
      .row { display: flex; align-items: baseline; justify-content: space-between; margin-bottom: 8px; }
      .term {
        font-size: 19px;
        font-weight: 600;
        font-family: "Hiragino Mincho ProN", "Yu Mincho", serif;
      }
      .close {
        cursor: pointer;
        border: none;
        background: none;
        color: #8A8270;
        font-size: 16px;
        line-height: 1;
        padding: 2px 4px;
      }
      .close:hover { color: #1F2933; }
      label {
        display: block;
        font-size: 11px;
        letter-spacing: 0.03em;
        text-transform: uppercase;
        color: #8A8270;
        margin: 8px 0 3px;
      }
      input, select, textarea {
        width: 100%;
        box-sizing: border-box;
        font-size: 13px;
        padding: 6px 8px;
        border: 1px solid #D8D0BE;
        border-radius: 6px;
        background: #FFFFFF;
        color: #1F2933;
        font-family: inherit;
      }
      textarea { resize: vertical; min-height: 44px; }
      input:focus, select:focus, textarea:focus {
        outline: 2px solid #B03A2E;
        outline-offset: 1px;
      }
      .loading { font-size: 12px; color: #8A8270; margin-top: 4px; }
      .actions { display: flex; gap: 8px; margin-top: 14px; }
      button.primary, button.secondary {
        flex: 1;
        padding: 8px 10px;
        border-radius: 6px;
        font-size: 13px;
        font-weight: 600;
        cursor: pointer;
        border: 1px solid transparent;
      }
      button.primary { background: #B03A2E; color: #FAF7F0; }
      button.primary:hover { background: #9A3026; }
      button.secondary { background: transparent; color: #1F2933; border-color: #D8D0BE; }
      button.secondary:hover { background: #F0EBDD; }
      .new-deck-row { display: none; gap: 6px; margin-top: 6px; }
      .new-deck-row.visible { display: flex; }
      .new-deck-row input { flex: 1; }
      .new-deck-row button { padding: 6px 10px; font-size: 12px; }
    </style>
    <div class="panel">
      <div class="row">
        <span class="term">${escapeHtml(term)}</span>
        <button class="close" title="Close">✕</button>
      </div>
      <div class="loading" data-loading>Looking up reading and meaning…</div>

      <label>Reading</label>
      <input type="text" data-reading placeholder="ねこ" />

      <label>Meaning</label>
      <textarea data-meaning placeholder="cat"></textarea>

      <label>Deck</label>
      <select data-deck-select></select>
      <div class="new-deck-row" data-new-deck-row>
        <input type="text" data-new-deck-name placeholder="New deck name" />
        <button class="secondary" data-confirm-new-deck>Add</button>
      </div>

      <div class="actions">
        <button class="secondary" data-cancel>Cancel</button>
        <button class="primary" data-save>Save word</button>
      </div>
    </div>
  `;

  const $ = (sel) => shadow.querySelector(sel);

  $('.close').addEventListener('click', removeOverlay);
  $('[data-cancel]').addEventListener('click', removeOverlay);

  const deckSelect = $('[data-deck-select]');
  const newDeckRow = $('[data-new-deck-row]');

  await populateDeckSelect(deckSelect);

  deckSelect.addEventListener('change', () => {
    newDeckRow.classList.toggle('visible', deckSelect.value === '__new__');
  });

  $('[data-confirm-new-deck]').addEventListener('click', async () => {
    const nameInput = $('[data-new-deck-name]');
    const name = nameInput.value.trim();
    if (!name) return;
    const deck = await createDeck(name);
    await populateDeckSelect(deckSelect, deck.id);
    newDeckRow.classList.remove('visible');
  });

  $('[data-save]').addEventListener('click', async () => {
    let deckId = deckSelect.value;
    if (deckId === '__new__') {
      const nameInput = $('[data-new-deck-name]');
      const name = nameInput.value.trim() || 'Untitled deck';
      const deck = await createDeck(name);
      deckId = deck.id;
    }
    const reading = $('[data-reading]').value.trim();
    const meaning = $('[data-meaning]').value.trim();
    await saveWord({
      deckId,
      term,
      reading,
      meaning,
      sourceUrl: location.href,
      sourceTitle: document.title
    });
    flashSaved($('.panel'));
    setTimeout(removeOverlay, 700);
  });

  document.addEventListener('keydown', onKeydown);

  function onKeydown(e) {
    if (e.key === 'Escape') {
      removeOverlay();
      document.removeEventListener('keydown', onKeydown);
    }
  }

  // Kick off the dictionary lookup after the panel is visible.
  ctx.runtime.sendMessage({ type: 'LOOKUP_WORD', term }, (response) => {
    $('[data-loading]').remove();
    if (response && response.ok && response.result) {
      if (response.result.reading) $('[data-reading]').value = response.result.reading;
      if (response.result.meaning) $('[data-meaning]').value = response.result.meaning;
    }
  });
}

function flashSaved(panel) {
  panel.style.transition = 'opacity 0.2s';
  panel.style.opacity = '0.5';
  const note = document.createElement('div');
  note.textContent = 'Saved ✓';
  note.style.textAlign = 'center';
  note.style.fontSize = '12px';
  note.style.color = '#1F2933';
  note.style.marginTop = '6px';
  panel.appendChild(note);
}

function escapeHtml(s) {
  const div = document.createElement('div');
  div.textContent = s;
  return div.innerHTML;
}

// ---- storage helpers (shared shape with popup.js) ----

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
  // Remember the deck so the background quick-save (used on PDFs) targets it.
  if (word.deckId) await ctx.storage.local.set({ lastDeckId: word.deckId });
  // Ask the background to sync this new word up to the user's account (no-op
  // when signed out / unconfigured).
  try {
    ctx.runtime.sendMessage({ type: 'SYNC_NOW' });
  } catch {
    // ignore if the background isn't reachable
  }
}

async function populateDeckSelect(selectEl, selectId) {
  const store = await getStore();
  store.decks = store.decks.filter((d) => !d.deleted);
  selectEl.innerHTML = '';
  if (store.decks.length === 0) {
    const opt = document.createElement('option');
    opt.value = '__new__';
    opt.textContent = '(no decks yet — create one)';
    selectEl.appendChild(opt);
  } else {
    store.decks.forEach((deck) => {
      const opt = document.createElement('option');
      opt.value = deck.id;
      opt.textContent = deck.name;
      selectEl.appendChild(opt);
    });
    const newOpt = document.createElement('option');
    newOpt.value = '__new__';
    newOpt.textContent = '+ New deck…';
    selectEl.appendChild(newOpt);
  }
  if (selectId) selectEl.value = selectId;
}

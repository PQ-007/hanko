// Content script injected on every page.
// Shows a small "save this word" panel triggered by the context menu or a
// keyboard shortcut, auto-fills reading/meaning via the background lookup,
// and writes the saved word straight into extension storage.

const ctx = typeof browser !== 'undefined' ? browser : chrome;

let activeOverlay = null;

// Ctrl+Enter (⌘↵ on a Mac) saves from any field in the panel.
const SAVE_KEY = /Mac|iPhone|iPad/.test(navigator.platform) ? '⌘↵' : 'Ctrl↵';

// Sign-in bridge: on the website's /extension/connect page, the page posts the
// Supabase session to the window after Google sign-in. Forward it to the
// background to store. Guarded to the connect page so other sites can't inject
// a fake session.
if (location.pathname.replace(/\/+$/, '').endsWith('/extension/connect')) {
  window.addEventListener('message', (event) => {
    if (event.source !== window || event.origin !== location.origin) return;
    const d = event.data;
    if (d && d.source === 'vocab-decks' && d.access_token && d.refresh_token) {
      ctx.runtime.sendMessage({
        type: 'STORE_SESSION',
        access_token: d.access_token,
        refresh_token: d.refresh_token
      });
    }
  });
}

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
  // Shared look (ui.js): same themes as the popup and the app. The tokens go
  // on the .hk wrapper, inside the shadow root, so the page's CSS can't touch
  // them.
  HankoUI.mount(shadow);
  const style = document.createElement('style');
  style.textContent = `
      :host { all: initial; }
      .panel {
        position: relative; /* the confirm dialog covers the panel */
        width: 320px;
        background: var(--hk-page);
        border: 1px solid var(--hk-line);
        border-radius: 16px;
        box-shadow: var(--hk-shadow);
        padding: 14px 16px 16px;
        font-size: 13px;
        animation: hk-rise .2s cubic-bezier(.2,.9,.3,1.2);
      }
      .head { display: flex; align-items: center; gap: 8px; cursor: grab; user-select: none; touch-action: none; }
      .head.dragging { cursor: grabbing; }
      .head .hk-btn { cursor: pointer; }
      .term { flex: 1; min-width: 0; font-size: 21px; font-weight: 700; line-height: 1.2; word-break: break-all; }
      .close, .speak { padding: 6px; }
      .speak .hk-ico, .close .hk-ico { width: 16px; height: 16px; }
      .dup { display: none; margin-top: 6px; font-size: 11.5px; font-weight: 600; color: var(--hk-seal-text); }
      .dup.visible { display: block; }
      kbd { font: 600 10px/1 var(--hk-font); opacity: .75; margin-left: 2px; }
      .loading { margin-top: 4px; font-size: 12px; color: var(--hk-ink-mute); }
      .loading::before {
        content: ""; display: inline-block; width: 8px; height: 8px; margin-right: 6px; vertical-align: -1px;
        border: 2px solid var(--hk-seal-tint); border-top-color: var(--hk-seal-text); border-radius: 999px;
        animation: hk-spin .8s linear infinite;
      }
      @keyframes hk-spin { to { transform: rotate(360deg); } }
      .hk .hk-label { margin-top: 10px; }
      .actions { display: flex; gap: 8px; margin-top: 14px; }
      .actions .hk-btn { flex: 1; }
      .new-deck-row { display: none; gap: 6px; margin-top: 6px; }
      .new-deck-row.visible { display: flex; }
      .new-deck-row input { flex: 1; min-width: 0; }
      .saved { display: flex; align-items: center; justify-content: center; gap: 6px; margin-top: 12px; }
      .saved .hk-ico { width: 15px; height: 15px; }
  `;
  shadow.appendChild(style);
  const wrap = document.createElement('div');
  wrap.className = 'hk';
  shadow.appendChild(wrap);
  HankoUI.watch((name) => HankoUI.apply(wrap, name));
  wrap.innerHTML = `
    <div class="panel">
      <div class="head">
        <span class="hk-mark">${HankoUI.ENSO}</span>
        <span class="term hk-jp">${escapeHtml(term)}</span>
        <button class="speak hk-btn hk-ghost hk-icon-btn" title="Дуудах" aria-label="Дуудах"><span class="hk-ico">${HankoUI.ICONS.speak}</span></button>
        <button class="close hk-btn hk-ghost hk-icon-btn" title="Хаах (Esc)" aria-label="Хаах"><span class="hk-ico">${HankoUI.ICONS.close}</span></button>
      </div>
      <div class="loading" data-loading>Дуудлага, утгыг хайж байна…</div>

      <label class="hk-label">Дуудлага</label>
      <input type="text" class="hk-field hk-jp" data-reading placeholder="ねこ" />

      <label class="hk-label">Утга (монгол)</label>
      <textarea class="hk-field" data-mongolian placeholder="муур"></textarea>

      <label class="hk-label">Утга (англи)</label>
      <textarea class="hk-field" data-meaning placeholder="cat"></textarea>

      <label class="hk-label">Багц</label>
      <select class="hk-field" data-deck-select></select>
      <div class="dup" data-dup>Энэ үг энэ багцад аль хэдийн байна.</div>
      <div class="new-deck-row" data-new-deck-row>
        <input type="text" class="hk-field" data-new-deck-name placeholder="Шинэ багцын нэр" />
        <button class="hk-btn hk-quiet" data-confirm-new-deck>Нэмэх</button>
      </div>

      <div class="actions">
        <button class="hk-btn hk-quiet" data-cancel>Болих</button>
        <button class="hk-btn hk-primary" data-save>Хадгалах <kbd>${SAVE_KEY}</kbd></button>
      </div>
    </div>
  `;

  const $ = (sel) => shadow.querySelector(sel);

  $('.close').addEventListener('click', removeOverlay);
  $('.speak').addEventListener('click', () => HankoUI.speak($('[data-reading]').value.trim() || term, $('.speak')));
  makeDraggable(host, $('.head'));
  $('[data-cancel]').addEventListener('click', removeOverlay);

  // Auto-translate English -> Mongolian when the meaning field is finished
  // (Enter or blur), only when it actually changed. Editing Mongolian never
  // translates in reverse.
  let lastEn = '';
  function translateMeaning() {
    const text = $('[data-meaning]').value.trim();
    if (!text || text === lastEn) return;
    lastEn = text;
    ctx.runtime.sendMessage({ type: 'TRANSLATE', text }, (resp) => {
      if (resp && resp.ok && resp.mongolian) $('[data-mongolian]').value = resp.mongolian;
    });
  }
  $('[data-meaning]').addEventListener('blur', translateMeaning);
  $('[data-meaning]').addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      translateMeaning();
    }
  });

  const deckSelect = $('[data-deck-select]');
  const newDeckRow = $('[data-new-deck-row]');

  await populateDeckSelect(deckSelect);

  // Say so up front when the word is already in the chosen deck, rather than
  // only after Save.
  async function checkDuplicate() {
    const id = deckSelect.value;
    $('[data-dup]').classList.toggle('visible', id !== '__new__' && (await isDuplicate(id, term)));
  }
  checkDuplicate();

  deckSelect.addEventListener('change', () => {
    newDeckRow.classList.toggle('visible', deckSelect.value === '__new__');
    checkDuplicate();
  });

  $('[data-confirm-new-deck]').addEventListener('click', async () => {
    const nameInput = $('[data-new-deck-name]');
    const name = nameInput.value.trim();
    if (!name) return;
    const deck = await createDeck(name);
    await populateDeckSelect(deckSelect, deck.id);
    newDeckRow.classList.remove('visible');
    checkDuplicate();
  });

  let saving = false;
  $('[data-save]').addEventListener('click', async () => {
    if (saving) return; // Ctrl+Enter again while the duplicate dialog is up
    saving = true;
    let deckId = deckSelect.value;
    let deckName = deckSelect.selectedOptions[0]?.textContent || '';
    if (deckId === '__new__') {
      const nameInput = $('[data-new-deck-name]');
      const name = nameInput.value.trim() || 'Нэргүй багц';
      const deck = await createDeck(name);
      deckId = deck.id;
      deckName = deck.name;
    }
    // The word may already be in the chosen deck — let the user decide.
    if (await isDuplicate(deckId, term)) {
      const ok = await HankoUI.confirm($('.panel'), {
        title: 'Давхардсан үг',
        body: `“${term}” энэ багцад аль хэдийн байна. Дахин нэмэх үү?`,
        confirmLabel: 'Дахин нэмэх',
      });
      if (!ok) {
        saving = false;
        return;
      }
    }
    const reading = $('[data-reading]').value.trim();
    const meaning = $('[data-meaning]').value.trim();
    const meaningMn = $('[data-mongolian]').value.trim();
    await saveWord({
      deckId,
      term,
      reading,
      meaning,
      meaningMn,
      sourceUrl: location.href,
      sourceTitle: document.title
    });
    flashSaved($('.panel'), deckName);
    setTimeout(removeOverlay, 900);
  });

  document.addEventListener('keydown', onKeydown);

  function onKeydown(e) {
    if (!host.isConnected) {
      document.removeEventListener('keydown', onKeydown);
      return;
    }
    if (e.key === 'Escape') {
      removeOverlay();
      document.removeEventListener('keydown', onKeydown);
    } else if (e.key === 'Enter' && (e.ctrlKey || e.metaKey) && e.composedPath().includes(host)) {
      // Only from inside the panel — the page's own Ctrl+Enter stays the page's.
      e.preventDefault();
      $('[data-save]').click();
    }
  }

  // Kick off the dictionary lookup after the panel is visible.
  ctx.runtime.sendMessage({ type: 'LOOKUP_WORD', term }, (response) => {
    $('[data-loading]').remove();
    if (response && response.ok && response.result) {
      const r = response.result;
      if (r.word && r.word !== term) {
        term = r.word; // use the dictionary form (普通形); saveWord reads this
        const termEl = shadow.querySelector('.term');
        if (termEl) termEl.textContent = term;
        checkDuplicate();
      }
      if (r.reading) $('[data-reading]').value = r.reading;
      if (r.meaning) {
        $('[data-meaning]').value = r.meaning;
        lastEn = r.meaning.trim();
      }
      if (r.mongolian) $('[data-mongolian]').value = r.mongolian;
    }
  });
}

function flashSaved(panel, deckName) {
  for (const el of panel.querySelectorAll('input, textarea, select, button')) el.disabled = true;
  const note = document.createElement('div');
  note.className = 'saved hk-toast';
  note.innerHTML = `<span class="hk-ico">${HankoUI.ICONS.check}</span>`;
  note.append(deckName ? `“${deckName}”-д хадгаллаа` : 'Хадгаллаа');
  panel.appendChild(note);
}

// Drag the panel by its header, so it never has to sit on the text you're
// reading. Kept inside the viewport.
function makeDraggable(host, handle) {
  handle.addEventListener('pointerdown', (e) => {
    if (e.button !== 0 || e.target.closest('button')) return;
    const r = host.getBoundingClientRect();
    const dx = e.clientX - r.left;
    const dy = e.clientY - r.top;
    handle.setPointerCapture(e.pointerId);
    handle.classList.add('dragging');
    const move = (ev) => {
      const x = Math.min(Math.max(0, ev.clientX - dx), window.innerWidth - r.width);
      const y = Math.min(Math.max(0, ev.clientY - dy), window.innerHeight - r.height);
      Object.assign(host.style, { left: `${x}px`, top: `${y}px`, right: 'auto', bottom: 'auto' });
    };
    const up = () => {
      handle.classList.remove('dragging');
      handle.removeEventListener('pointermove', move);
      handle.removeEventListener('pointerup', up);
      handle.removeEventListener('pointercancel', up);
    };
    handle.addEventListener('pointermove', move);
    handle.addEventListener('pointerup', up);
    handle.addEventListener('pointercancel', up);
  });
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

async function isDuplicate(deckId, term) {
  const store = await getStore();
  return store.words.some((w) => !w.deleted && w.deckId === deckId && w.term === term);
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
    opt.textContent = '(багц алга — үүсгэнэ үү)';
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
    newOpt.textContent = '+ Шинэ багц…';
    selectEl.appendChild(newOpt);
  }
  // Default to the deck last saved into (same as the save window).
  const { lastDeckId } = await ctx.storage.local.get('lastDeckId');
  if (selectId) selectEl.value = selectId;
  else if (lastDeckId && store.decks.some((d) => d.id === lastDeckId)) selectEl.value = lastDeckId;
}

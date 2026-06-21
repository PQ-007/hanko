// Background service worker (Chrome) / background script (Firefox)
// Handles: context menu creation, keyboard command relay, dictionary lookups,
// and periodic/background sync to the user's Supabase account.
// Dictionary lookups happen here (not in the content script) because content
// scripts can be blocked by a page's Content-Security-Policy from fetching
// third-party APIs, while the extension background context is not.

// Load the sync helpers. Firefox lists these in manifest background.scripts;
// in the Chrome service worker we pull them in via importScripts.
if (typeof importScripts === 'function') {
  try {
    importScripts('config.js', 'sync.js');
  } catch (e) {
    // ignore — sync just stays disabled if these can't load
  }
}

const ctx = typeof browser !== 'undefined' ? browser : chrome;
const SYNC_ALARM = 'vocab-sync';

console.log('Vocab Decks background loaded');

// Create the right-click menu. removeAll first so re-running (on install,
// browser startup, or an event-page wake) never errors on a duplicate id —
// this is what keeps the menu reliable for Firefox/Zen non-persistent
// background pages.
function createMenus() {
  try {
    ctx.contextMenus.removeAll(() => {
      void ctx.runtime.lastError; // clear any pending error
      ctx.contextMenus.create(
        {
          id: 'save-word-to-deck',
          title: 'Save "%s" to vocab deck',
          contexts: ['selection']
        },
        () => {
          if (ctx.runtime.lastError) {
            console.error('contextMenus.create:', ctx.runtime.lastError.message);
          } else {
            console.log('Vocab Decks: context menu ready');
          }
        }
      );
    });
  } catch (e) {
    console.error('createMenus failed:', e);
  }
}

// Register for both install and every browser startup so the menu is always
// present, then create it now in case this script is loading on an event wake.
ctx.runtime.onInstalled.addListener(() => {
  createMenus();
  try {
    ctx.alarms.create(SYNC_ALARM, { periodInMinutes: 5 });
  } catch (e) {
    // alarms may be unavailable; popup-open sync still works.
  }
});
if (ctx.runtime.onStartup) ctx.runtime.onStartup.addListener(createMenus);
createMenus();

function backgroundSync() {
  if (globalThis.VocabSync && VocabSync.configured()) {
    VocabSync.fullSync().catch((err) => console.warn('Background sync failed:', err));
  }
}

if (ctx.alarms && ctx.alarms.onAlarm) {
  ctx.alarms.onAlarm.addListener((alarm) => {
    if (alarm.name === SYNC_ALARM) backgroundSync();
  });
}

ctx.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId !== 'save-word-to-deck') return;
  const text = (info.selectionText || '').trim();
  if (!text) return;

  // Try to show the in-page panel first (the nice editable overlay). If the
  // content script isn't reachable — e.g. Firefox's built-in PDF viewer or
  // file:// pages, where extensions can't inject — open the same editable form
  // as a small popup window instead.
  if (tab && tab.id != null) {
    Promise.resolve(ctx.tabs.sendMessage(tab.id, { type: 'SHOW_SAVE_OVERLAY', text }))
      .catch(() => openSaveWindow(text));
  } else {
    openSaveWindow(text);
  }
});

// Open the editable save form (save.html) as a small popup window — the
// fallback used on PDFs / file pages where the in-page overlay can't render.
// If even that fails, fall back to a silent background save.
function openSaveWindow(text) {
  const url = ctx.runtime.getURL('save.html') + '?term=' + encodeURIComponent(text);
  Promise.resolve(
    ctx.windows.create({ url, type: 'popup', width: 380, height: 520 })
  ).catch(() => backgroundQuickSave(text));
}

// ---- storage + direct-save fallback (used on PDFs / file pages) ----

async function getStore() {
  const data = await ctx.storage.local.get(['decks', 'words']);
  return { decks: data.decks || [], words: data.words || [] };
}

async function setStore(store) {
  await ctx.storage.local.set(store);
}

function notify(title, message) {
  try {
    if (ctx.notifications) {
      ctx.notifications.create({
        type: 'basic',
        iconUrl: ctx.runtime.getURL('icons/icon48.png'),
        title,
        message
      });
    }
  } catch (e) {
    // notifications may be unavailable; the word is still saved.
  }
}

// Save a word without the in-page panel: look it up, drop it in the last-used
// deck (or a "Quick saves" deck), and show a notification.
async function backgroundQuickSave(term) {
  if (!term) return;
  let lookup = { reading: '', meaning: '' };
  try {
    lookup = await lookupWord(term);
  } catch (e) {
    // keep going with blank reading/meaning
  }

  const store = await getStore();
  const now = Date.now();
  const { lastDeckId } = await ctx.storage.local.get('lastDeckId');

  let deck =
    store.decks.find((d) => d.id === lastDeckId && !d.deleted) ||
    store.decks.find((d) => !d.deleted && d.name === 'Quick saves');
  if (!deck) {
    deck = { id: crypto.randomUUID(), name: 'Quick saves', createdAt: now, updatedAt: now, deleted: false };
    store.decks.push(deck);
  }

  store.words.push({
    id: crypto.randomUUID(),
    deckId: deck.id,
    term,
    reading: lookup.reading || '',
    meaning: lookup.meaning || '',
    dateAdded: now,
    updatedAt: now,
    deleted: false
  });

  await setStore(store);
  await ctx.storage.local.set({ lastDeckId: deck.id });
  notify(`Saved to "${deck.name}"`, lookup.reading ? `${term} (${lookup.reading})` : term);
  backgroundSync();
}

ctx.commands.onCommand.addListener((command) => {
  if (command !== 'save-word') return;
  ctx.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    const tab = tabs && tabs[0];
    if (tab && tab.id != null) {
      ctx.tabs.sendMessage(tab.id, { type: 'TRIGGER_SAVE_FROM_SELECTION' });
    }
  });
});

ctx.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message && message.type === 'LOOKUP_WORD') {
    lookupWord(message.term)
      .then((result) => sendResponse({ ok: true, result }))
      .catch((err) => sendResponse({ ok: false, error: String(err) }));
    return true; // keep the message channel open for the async response
  }
  if (message && message.type === 'SYNC_NOW') {
    backgroundSync();
    return false;
  }
  return false;
});

async function lookupWord(term) {
  const url = `https://jisho.org/api/v1/search/words?keyword=${encodeURIComponent(term)}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Lookup failed (${res.status})`);
  const data = await res.json();
  const entry = data && data.data && data.data[0];
  if (!entry) return { reading: '', meaning: '' };

  const jp = (entry.japanese && entry.japanese[0]) || {};
  const reading = jp.reading || '';

  const senses = entry.senses || [];
  const meaning = senses
    .slice(0, 3)
    .map((s) => (s.english_definitions || []).join(', '))
    .filter(Boolean)
    .join('; ');

  return { reading, meaning };
}

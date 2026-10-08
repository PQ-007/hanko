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
    importScripts('config.js', 'sync.js', 'ui.js');
  } catch (e) {
    // ignore — sync just stays disabled if these can't load
  }
}

const ctx = typeof browser !== 'undefined' ? browser : chrome;
const SYNC_ALARM = 'vocab-sync';

console.log('Hanko background loaded');

// The toolbar icon follows the theme picked in the popup (ui.js): Цайвар's
// vermilion ensō by default, Бараан's charcoal or Цэнхэр's blue.
function applyToolbarIcon(name) {
  const action = ctx.action || ctx.browserAction;
  if (!action || !globalThis.HankoUI) return;
  try {
    Promise.resolve(action.setIcon({ path: HankoUI.iconPaths(name) })).catch(() => {});
  } catch (e) {
    // a missing icon only means the default stays
  }
}
if (globalThis.HankoUI) HankoUI.watch(applyToolbarIcon);

// The toolbar badge shows how many cards are due right now (due_summary(),
// the web dashboard's own number), in the theme's accent. Driven by
// storage.local.dueNow, which VocabSync.refreshDue() writes from here, the
// popup or after a save — so whichever surface refreshed it, the badge follows.
const BADGE_COLORS = { paper: '#c8442f', dark: '#2f6bb8', blue: '#0f3a78' };
async function applyBadge() {
  const action = ctx.action || ctx.browserAction;
  if (!action || !action.setBadgeText) return;
  const { dueNow, hankoTheme } = await ctx.storage.local.get(['dueNow', 'hankoTheme']);
  const text = typeof dueNow === 'number' && dueNow > 0 ? (dueNow > 999 ? '999+' : String(dueNow)) : '';
  try {
    await action.setBadgeText({ text });
    await action.setBadgeBackgroundColor({ color: BADGE_COLORS[hankoTheme] || BADGE_COLORS.paper });
    if (action.setBadgeTextColor) await action.setBadgeTextColor({ color: '#ffffff' });
    await action.setTitle({ title: text ? `Hanko — давтах ${dueNow} карт` : 'Hanko' });
  } catch (e) {
    // a badge is decoration; never let it break the worker
  }
}
ctx.storage.onChanged.addListener((changes, area) => {
  if (area === 'local' && (changes.dueNow || changes.hankoTheme)) applyBadge();
});
applyBadge();

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
          title: '“%s”-г багцад хадгалах',
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
if (ctx.runtime.onStartup) {
  ctx.runtime.onStartup.addListener(() => {
    createMenus();
    backgroundSync(); // fresh due count as soon as the browser opens
  });
}
createMenus();

function backgroundSync() {
  if (globalThis.VocabSync && VocabSync.configured()) {
    VocabSync.fullSync()
      .catch((err) => console.warn('Background sync failed:', err))
      .then(() => VocabSync.refreshDue());
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
    store.decks.find((d) => !d.deleted && d.name === 'Шуурхай хадгалсан');
  if (!deck) {
    deck = { id: crypto.randomUUID(), name: 'Шуурхай хадгалсан', createdAt: now, updatedAt: now, deleted: false };
    store.decks.push(deck);
  }

  // Save the dictionary form (普通形) when Jisho resolved one.
  const finalTerm = lookup.word || term;
  store.words.push({
    id: crypto.randomUUID(),
    deckId: deck.id,
    term: finalTerm,
    reading: lookup.reading || '',
    meaning: lookup.meaning || '',
    meaningMn: lookup.mongolian || '',
    dateAdded: now,
    updatedAt: now,
    deleted: false
  });

  await setStore(store);
  await ctx.storage.local.set({ lastDeckId: deck.id });
  notify(`“${deck.name}”-д хадгаллаа`, lookup.reading ? `${finalTerm} (${lookup.reading})` : finalTerm);
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
  if (message && message.type === 'TRANSLATE') {
    translateToMongolian(message.text || '')
      .then((mongolian) => sendResponse({ ok: true, mongolian }))
      .catch(() => sendResponse({ ok: false, mongolian: '' }));
    return true; // async response
  }
  if (message && message.type === 'SYNC_NOW') {
    backgroundSync();
    return false;
  }
  if (message && message.type === 'STORE_SESSION') {
    // Session handed over by the connect-page bridge after Google sign-in.
    if (globalThis.VocabSync) {
      VocabSync.storeSession(message.access_token, message.refresh_token)
        .then(() => notify('Нэвтэрлээ', 'Таны багцууд одоо синк хийгдэнэ.'))
        .catch((err) => console.warn('storeSession failed:', err));
    }
    return false;
  }
  return false;
});

async function lookupWord(term) {
  const url = `https://jisho.org/api/v1/search/words?keyword=${encodeURIComponent(term)}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Lookup failed (${res.status})`);
  const data = await res.json();
  const entries = (data && data.data) || [];
  let entry = entries[0];
  if (!entry) return { word: '', reading: '', meaning: '', mongolian: '' };

  // Keep the kanji as captured when Jisho knows it: an entry is listed under
  // its most common spelling, so its first writing would swap a rarer kanji
  // (附属, 籠る) for the common one (付属, 篭る). Same rule as parseJisho in
  // web/src/lib/jisho.ts and mobile/lib/core/dictionary.dart.
  let jp = (entry.japanese && entry.japanese[0]) || {};
  for (const e of entries) {
    const exact = (e.japanese || []).find((w) => w.word === term);
    if (exact) {
      entry = e;
      jp = exact;
      break;
    }
  }
  const reading = jp.reading || '';
  // Dictionary / base form (普通形): Jisho deinflects, so 担っています -> 担う.
  const word = jp.word || entry.slug || reading || '';

  const senses = entry.senses || [];
  const meaning = compactGloss(
    senses
      .slice(0, 3)
      .map((s) => (s.english_definitions || []).join(', '))
      .join('; ')
  );

  const mongolian = await translateToMongolian(meaning);
  return { word, reading, meaning, mongolian };
}

// A short, duplicate-free meaning: notes in brackets dropped, each item once,
// at most 3 items and about 40 characters. Copy of compactGloss in
// web/src/lib/gloss.ts (and mobile/lib/core/dictionary.dart) — keep in step.
function stripNotes(text) {
  return text
    .replace(/\([^()]*\)|（[^（）]*）|\[[^\]]*\]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function compactGloss(text) {
  const seen = new Set();
  const items = [];
  let length = 0;
  for (const raw of text.split(/[,;、，；\n]/)) {
    const item = stripNotes(raw).replace(/^[\s.:-]+|[\s.:-]+$/g, '');
    const key = item.toLowerCase();
    if (!item || seen.has(key)) continue;
    seen.add(key);
    if (items.length && length + 2 + item.length > 40) break;
    items.push(item);
    length += (items.length > 1 ? 2 : 0) + item.length;
    if (items.length === 3) break;
  }
  return items.join(', ');
}

// English -> Mongolian via the website's /api/translate proxy (keeps the
// bolor-toli key server-side). Returns '' if the site isn't configured/reachable.
async function translateToMongolian(text) {
  const siteUrl = (globalThis.VOCAB_CONFIG && globalThis.VOCAB_CONFIG.SITE_URL) || '';
  if (!siteUrl || !text) return '';
  try {
    const res = await fetch(
      `${siteUrl.replace(/\/$/, '')}/api/translate?text=${encodeURIComponent(text)}`
    );
    if (!res.ok) return '';
    const data = await res.json();
    return data.mongolian || '';
  } catch (e) {
    return '';
  }
}

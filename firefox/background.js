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

ctx.runtime.onInstalled.addListener(() => {
  try {
    ctx.contextMenus.create({
      id: 'save-word-to-deck',
      title: 'Save "%s" to vocab deck',
      contexts: ['selection']
    });
  } catch (e) {
    // contextMenus.create can throw if called twice during dev reloads; ignore.
  }
  // Periodic background sync so other devices' changes show up without opening
  // the popup.
  try {
    ctx.alarms.create(SYNC_ALARM, { periodInMinutes: 5 });
  } catch (e) {
    // alarms may be unavailable; popup-open sync still works.
  }
});

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
  if (info.menuItemId === 'save-word-to-deck' && tab && tab.id != null) {
    ctx.tabs.sendMessage(tab.id, {
      type: 'SHOW_SAVE_OVERLAY',
      text: (info.selectionText || '').trim()
    });
  }
});

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

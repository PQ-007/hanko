// Shared look for every extension surface — the popup, the save window and
// the in-page save panel (a shadow root inside someone else's page). Canonical
// copy is src/ui.js; like sync.js it is copied verbatim into chrome/ and
// firefox/ (no build step), and src/package.sh refuses to zip if they differ.
//
// Three themes, the same three as the app and the story images (web
// globals.css html[data-scheme], mobile core/theme.dart): Цайвар (default),
// Бараан, Цэнхэр. Chosen in the popup, stored in storage.local as
// `hankoTheme`, and applied as CSS custom properties on whatever element the
// surface hands us — so the page's own styles can never leak in or out.

(function () {
  const ext = typeof browser !== 'undefined' ? browser : chrome;

  const THEMES = {
    paper: {
      label: 'Цайвар',
      paper: '#f7eedd', paperDim: '#efe0c4', line: '#dcc7a2', lineSoft: '#ecdfc6',
      ink: '#1c232b', inkSoft: '#5f5546', inkMute: '#75685a',
      seal: '#c8442f', sealDark: '#a83623', sealTint: '#f6ddd6', sealText: '#c8442f',
      surface: '#ffffff', danger: '#c62828', dangerSolid: '#c62828', dangerTint: '#fbe3e1',
      page: 'linear-gradient(180deg, #f8f2e6, #efe3cc)',
      shadow: '0 10px 30px rgba(110, 80, 40, 0.22)',
    },
    dark: {
      label: 'Бараан',
      paper: '#14171c', paperDim: '#1c2027', line: '#363d48', lineSoft: '#2b313a',
      ink: '#ece9e2', inkSoft: '#b9b3a8', inkMute: '#9a9488',
      seal: '#2f6bb8', sealDark: '#3a78c9', sealTint: '#1d2d44', sealText: '#6fa3e6',
      surface: '#1e232b', danger: '#f87171', dangerSolid: '#dc2626', dangerTint: 'rgba(248, 113, 113, 0.14)',
      page: '#14171c',
      shadow: '0 10px 30px rgba(0, 0, 0, 0.5)',
    },
    blue: {
      label: 'Цэнхэр',
      paper: '#2563b8', paperDim: '#1f57a6', line: '#5b8fd6', lineSoft: '#3f78c8',
      ink: '#ffffff', inkSoft: '#dbe8fb', inkMute: '#b3cbee',
      seal: '#0f3a78', sealDark: '#0b2d5e', sealTint: '#3a74c4', sealText: '#d6e8ff',
      surface: '#2f6ec4', danger: '#fecaca', dangerSolid: '#dc2626', dangerTint: 'rgba(254, 202, 202, 0.16)',
      page: 'linear-gradient(180deg, #2c72cc, #123f7c)',
      shadow: '0 10px 30px rgba(4, 20, 48, 0.45)',
    },
  };
  const ORDER = ['paper', 'dark', 'blue'];
  const KEY = 'hankoTheme';

  // The ensō (the app's mark), as inline SVG in the current accent.
  const ENSO =
    '<svg viewBox="0 0 24 24" width="100%" height="100%" aria-hidden="true">' +
    '<path d="M17.6 5.6A8 8 0 1 0 20 11.2" fill="none" stroke="currentColor" ' +
    'stroke-width="2.6" stroke-linecap="square"/></svg>';

  // Line icons in the app's style (1.6–1.8 stroke, square caps, mitred joins).
  const icon = (d, w = 1.7) =>
    `<svg viewBox="0 0 24 24" width="100%" height="100%" aria-hidden="true"><path d="${d}" fill="none" ` +
    `stroke="currentColor" stroke-width="${w}" stroke-linecap="square" stroke-linejoin="miter"/></svg>`;
  const ICONS = {
    speak: icon('M4 9.5h3.5L12 5.5v13l-4.5-4H4zM15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11'),
    edit: icon('M5 19h3.5L19 8.5 15.5 5 5 15.5zM13 7.5l3.5 3.5'),
    trash: icon('M5 7h14M10 7V4.5h4V7M7 7l1 13h8l1-13', 1.6),
    sync: icon('M19 8.5A7.5 7.5 0 0 0 5.5 7M5 15.5A7.5 7.5 0 0 0 18.5 17M5 4v3.5h3.5M19 20v-3.5h-3.5'),
    search: icon('M10.5 17a6.5 6.5 0 1 0 0-13 6.5 6.5 0 0 0 0 13zM15.5 15.5 20 20'),
    plus: icon('M12 5v14M5 12h14', 1.8),
    close: icon('M6 6l12 12M18 6 6 18', 1.8),
    check: icon('M5 12.5l4.5 4.5L19 7', 2),
    external: icon('M9 6h9v9M18 6 7 17', 1.8),
    link: icon('M10 14l4-4M8.5 11.5 6.5 13.5a3.5 3.5 0 0 0 5 5l2-2M15.5 12.5l2-2a3.5 3.5 0 0 0-5-5l-2 2'),
  };

  // Components every surface shares. Scoped by class, injected once per
  // document or shadow root by HankoUI.mount().
  const CSS = `
  .hk {
    --hk-font: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif;
    --hk-jp: "Hiragino Sans", "Hiragino Kaku Gothic ProN", "Noto Sans JP", "Noto Sans CJK JP", "Yu Gothic", "Meiryo", sans-serif;
    font-family: var(--hk-font);
    color: var(--hk-ink);
    -webkit-font-smoothing: antialiased;
  }
  .hk *, .hk *::before, .hk *::after { box-sizing: border-box; }
  .hk .hk-jp { font-family: var(--hk-jp); }
  .hk .hk-mark { display: inline-flex; width: 22px; height: 22px; color: var(--hk-seal-text); flex-shrink: 0; }

  .hk .hk-label {
    display: block; font-size: 11px; font-weight: 600; color: var(--hk-ink-mute);
    margin: 12px 0 5px;
  }
  .hk .hk-field {
    width: 100%; font: inherit; font-size: 13px; padding: 8px 10px;
    border: 1px solid var(--hk-line); border-radius: 10px;
    background: var(--hk-surface); color: var(--hk-ink);
    transition: border-color .15s, box-shadow .15s;
  }
  .hk textarea.hk-field { resize: vertical; min-height: 48px; line-height: 1.4; }
  .hk .hk-field::placeholder { color: var(--hk-ink-mute); opacity: .8; }
  .hk .hk-field:focus { outline: none; border-color: var(--hk-seal-text); box-shadow: 0 0 0 3px var(--hk-seal-tint); }
  .hk select.hk-field { appearance: none; padding-right: 28px; cursor: pointer;
    background-image: linear-gradient(45deg, transparent 50%, var(--hk-ink-mute) 50%), linear-gradient(135deg, var(--hk-ink-mute) 50%, transparent 50%);
    background-position: calc(100% - 15px) 52%, calc(100% - 10px) 52%;
    background-size: 5px 5px; background-repeat: no-repeat; }
  .hk select.hk-field option { background: var(--hk-surface); color: var(--hk-ink); }

  .hk .hk-btn {
    display: inline-flex; align-items: center; justify-content: center; gap: 6px;
    font: inherit; font-size: 13px; font-weight: 600; line-height: 1;
    padding: 9px 14px; border-radius: 10px; cursor: pointer;
    border: 1px solid transparent; transition: background .15s, border-color .15s, color .15s;
    white-space: nowrap;
  }
  .hk .hk-btn:disabled { opacity: .55; cursor: default; }
  .hk .hk-btn:focus-visible { outline: none; box-shadow: 0 0 0 3px var(--hk-seal-tint); }
  .hk .hk-primary { background: var(--hk-seal); color: #fff; }
  .hk .hk-primary:hover:not(:disabled) { background: var(--hk-seal-dark); }
  .hk .hk-quiet { background: var(--hk-surface); color: var(--hk-ink); border-color: var(--hk-line); }
  .hk .hk-quiet:hover:not(:disabled) { background: var(--hk-paper-dim); }
  .hk .hk-ghost { background: transparent; color: var(--hk-ink-soft); }
  .hk .hk-ghost:hover:not(:disabled) { background: var(--hk-paper-dim); color: var(--hk-ink); }
  /* Solid red button (white text); --hk-danger is the red for text/icons,
     which on Цэнхэр is a light pink no white text could sit on. */
  .hk .hk-danger { background: var(--hk-danger-solid); color: #fff; }
  .hk .hk-danger:hover:not(:disabled) { filter: brightness(.92); }
  .hk .hk-danger-text { color: var(--hk-danger); }
  .hk .hk-icon-btn { padding: 7px; border-radius: 9px; }

  /* Confirm dialog (HankoUI.confirm): over whatever container it's given. */
  .hk .hk-scrim {
    position: absolute; inset: 0; z-index: 10; display: flex; align-items: center; justify-content: center;
    padding: 14px; background: rgba(0, 0, 0, .42); animation: hk-fade .14s ease-out;
    border-radius: inherit;
  }
  .hk .hk-dialog {
    width: 100%; max-width: 300px; background: var(--hk-surface); color: var(--hk-ink);
    border: 1px solid var(--hk-line); border-radius: 16px; padding: 18px 16px 14px;
    box-shadow: var(--hk-shadow); text-align: center; animation: hk-rise .18s cubic-bezier(.2,.9,.3,1.2);
  }
  .hk .hk-dialog-icon {
    width: 42px; height: 42px; margin: 0 auto 10px; border-radius: 999px;
    display: flex; align-items: center; justify-content: center; font-size: 19px; font-weight: 700;
    background: var(--hk-seal-tint); color: var(--hk-seal-text);
  }
  .hk .hk-dialog.danger .hk-dialog-icon { background: var(--hk-danger-tint); color: var(--hk-danger); }
  .hk .hk-dialog h2 { margin: 0; font-size: 15px; font-weight: 700; line-height: 1.35; }
  .hk .hk-dialog p { margin: 6px 0 0; font-size: 12.5px; line-height: 1.45; color: var(--hk-ink-soft); }
  .hk .hk-dialog-actions { display: flex; flex-direction: column; gap: 6px; margin-top: 16px; }
  .hk .hk-dialog-actions .hk-btn { width: 100%; padding: 10px 14px; }

  .hk .hk-toast {
    font-size: 12.5px; font-weight: 600; text-align: center; color: var(--hk-seal-text);
  }
  .hk .hk-ico { display: inline-flex; width: 16px; height: 16px; flex-shrink: 0; }

  /* Snackbar (HankoUI.snack): bottom of the container it's given. */
  .hk .hk-snack {
    position: absolute; left: 12px; right: 12px; bottom: 12px; z-index: 9;
    display: flex; align-items: center; gap: 10px; padding: 9px 10px 9px 14px;
    background: var(--hk-ink); color: var(--hk-paper); border-radius: 12px;
    font-size: 12.5px; font-weight: 600; box-shadow: var(--hk-shadow);
    animation: hk-rise .18s cubic-bezier(.2,.9,.3,1.2);
  }
  .hk .hk-snack span { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .hk .hk-snack button {
    border: 0; background: none; font: inherit; font-weight: 700; padding: 4px 6px; border-radius: 7px;
    color: var(--hk-paper); text-decoration: underline; text-underline-offset: 2px; cursor: pointer;
  }
  .hk[data-hk-theme="blue"] .hk-snack { background: #0b2d5e; color: #fff; }
  .hk[data-hk-theme="blue"] .hk-snack button { color: #fff; }

  /* Speaking indicator on a speak button. */
  .hk .hk-speaking { color: var(--hk-seal-text); animation: hk-pulse .9s ease-in-out infinite; }
  @keyframes hk-pulse { 50% { opacity: .45; } }

  @keyframes hk-fade { from { opacity: 0; } }
  @keyframes hk-rise { from { opacity: 0; transform: translateY(8px) scale(.97); } }
  `;

  function tokens(name) {
    const t = THEMES[name] || THEMES.paper;
    return {
      '--hk-paper': t.paper, '--hk-paper-dim': t.paperDim, '--hk-line': t.line, '--hk-line-soft': t.lineSoft,
      '--hk-ink': t.ink, '--hk-ink-soft': t.inkSoft, '--hk-ink-mute': t.inkMute,
      '--hk-seal': t.seal, '--hk-seal-dark': t.sealDark, '--hk-seal-tint': t.sealTint, '--hk-seal-text': t.sealText,
      '--hk-surface': t.surface, '--hk-danger': t.danger, '--hk-danger-solid': t.dangerSolid, '--hk-danger-tint': t.dangerTint,
      '--hk-page': t.page, '--hk-shadow': t.shadow,
    };
  }

  // Pronunciation. The browser's own Japanese voice when it has one (no
  // network, works on any page); otherwise Google's keyless TTS — the same
  // endpoint as the app — which answers 400 to any request carrying a Referer,
  // so extension pages that play it set <meta name="referrer" content="no-referrer">.
  let jaVoice = null;
  function findVoice() {
    if (!globalThis.speechSynthesis) return null;
    const voices = speechSynthesis.getVoices();
    return voices.find((v) => /^ja(-|_|$)/i.test(v.lang)) || null;
  }
  let current = null;
  function stopSpeaking() {
    if (current && current.pause) current.pause();
    if (globalThis.speechSynthesis) speechSynthesis.cancel();
    current = null;
  }

  const HankoUI = {
    THEMES,
    ORDER,
    ENSO,
    ICONS,

    /**
     * Speaks Japanese text. Resolves when it finishes (or fails); `button`, if
     * given, pulses while it plays.
     */
    speak(text, button) {
      const t = (text || '').trim();
      if (!t) return Promise.resolve();
      stopSpeaking();
      if (button) button.classList.add('hk-speaking');
      const done = () => button && button.classList.remove('hk-speaking');
      // Voices can load late (Chrome fills the list after first ask), so keep looking.
      if (!jaVoice) jaVoice = findVoice();
      return new Promise((resolve) => {
        const finish = () => { done(); resolve(); };
        if (jaVoice) {
          const u = new SpeechSynthesisUtterance(t);
          u.voice = jaVoice;
          u.lang = jaVoice.lang;
          u.rate = 0.9;
          u.onend = u.onerror = finish;
          current = null;
          speechSynthesis.speak(u);
          return;
        }
        const a = new Audio(
          'https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=ja&q=' + encodeURIComponent(t.slice(0, 180))
        );
        current = a;
        a.onended = a.onerror = finish;
        a.play().catch(finish);
      });
    },

    /**
     * A snackbar at the bottom of `container` (position: relative, inside a
     * .hk element), gone after `ms`. With `action`, shows a button that runs
     * action.run() and dismisses — used for undo.
     */
    snack(container, message, { action, ms = 4000 } = {}) {
      const old = container.querySelector(':scope > .hk-snack');
      if (old) old.remove();
      const bar = document.createElement('div');
      bar.className = 'hk-snack';
      bar.setAttribute('role', 'status');
      const span = document.createElement('span');
      span.textContent = message;
      bar.append(span);
      const timer = setTimeout(() => bar.remove(), ms);
      if (action) {
        const b = document.createElement('button');
        b.textContent = action.label;
        b.addEventListener('click', () => {
          clearTimeout(timer);
          bar.remove();
          action.run();
        });
        bar.append(b);
      }
      container.append(bar);
    },

    /** The stored theme name (Цайвар when unset or unknown). */
    async load() {
      try {
        const v = (await ext.storage.local.get(KEY))[KEY];
        return THEMES[v] ? v : 'paper';
      } catch (e) {
        return 'paper';
      }
    },

    async save(name) {
      if (!THEMES[name]) return;
      await ext.storage.local.set({ [KEY]: name });
    },

    /** Calls fn(name) now and whenever the theme changes in another surface. */
    async watch(fn) {
      fn(await HankoUI.load());
      ext.storage.onChanged.addListener((changes, area) => {
        if (area === 'local' && changes[KEY]) fn(THEMES[changes[KEY].newValue] ? changes[KEY].newValue : 'paper');
      });
    },

    /** Applies a theme's tokens to an element (and everything inside it). */
    apply(el, name) {
      const t = tokens(name);
      for (const k in t) el.style.setProperty(k, t[k]);
      el.dataset.hkTheme = THEMES[name] ? name : 'paper';
    },

    /** Injects the shared component CSS into a document or shadow root, once. */
    mount(root) {
      const target = root.head || root;
      if (target.querySelector && target.querySelector('style[data-hk-ui]')) return;
      const style = document.createElement('style');
      style.dataset.hkUi = '';
      style.textContent = CSS;
      target.appendChild(style);
    },

    /** Toolbar icon paths for a theme (icons/<theme>-<size>.png). */
    iconPaths(name) {
      const n = THEMES[name] ? name : 'paper';
      return { 16: `icons/${n}-16.png`, 32: `icons/${n}-32.png`, 48: `icons/${n}-48.png`, 128: `icons/${n}-128.png` };
    },

    /**
     * The extension's confirm(): a themed dialog drawn over `container` (which
     * must be position: relative/absolute/fixed and inside a `.hk` element).
     * Resolves true only on the confirm button; Escape or the scrim is false.
     */
    confirm(container, { title, body, confirmLabel, cancelLabel = 'Болих', danger = false, icon }) {
      return new Promise((resolve) => {
        const scrim = document.createElement('div');
        scrim.className = 'hk-scrim';
        const dlg = document.createElement('div');
        dlg.className = 'hk-dialog' + (danger ? ' danger' : '');
        dlg.setAttribute('role', danger ? 'alertdialog' : 'dialog');
        dlg.setAttribute('aria-modal', 'true');
        const ic = document.createElement('div');
        ic.className = 'hk-dialog-icon';
        ic.textContent = icon || (danger ? '✕' : '!');
        const h = document.createElement('h2');
        h.textContent = title;
        dlg.append(ic, h);
        if (body) {
          const p = document.createElement('p');
          p.textContent = body;
          dlg.append(p);
        }
        const actions = document.createElement('div');
        actions.className = 'hk-dialog-actions';
        const ok = document.createElement('button');
        ok.className = 'hk-btn ' + (danger ? 'hk-danger' : 'hk-primary');
        ok.textContent = confirmLabel || (danger ? 'Устгах' : 'За');
        const cancel = document.createElement('button');
        cancel.className = 'hk-btn hk-ghost';
        cancel.textContent = cancelLabel;
        actions.append(ok, cancel);
        dlg.append(actions);
        scrim.append(dlg);
        container.append(scrim);

        const keyTarget = container.getRootNode ? container.getRootNode() : document;
        function done(v) {
          scrim.remove();
          keyTarget.removeEventListener('keydown', onKey, true);
          resolve(v);
        }
        function onKey(e) {
          if (e.key === 'Escape') {
            e.preventDefault();
            e.stopPropagation();
            done(false);
          }
        }
        keyTarget.addEventListener('keydown', onKey, true);
        ok.addEventListener('click', () => done(true));
        cancel.addEventListener('click', () => done(false));
        scrim.addEventListener('click', (e) => e.target === scrim && done(false));
        ok.focus();
      });
    },
  };

  globalThis.HankoUI = HankoUI;
})();

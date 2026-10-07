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
      surface: '#ffffff', danger: '#c62828', dangerTint: '#fbe3e1',
      page: 'linear-gradient(180deg, #f8f2e6, #efe3cc)',
      shadow: '0 10px 30px rgba(110, 80, 40, 0.22)',
    },
    dark: {
      label: 'Бараан',
      paper: '#14171c', paperDim: '#1c2027', line: '#363d48', lineSoft: '#2b313a',
      ink: '#ece9e2', inkSoft: '#b9b3a8', inkMute: '#9a9488',
      seal: '#2f6bb8', sealDark: '#3a78c9', sealTint: '#1d2d44', sealText: '#6fa3e6',
      surface: '#1e232b', danger: '#f87171', dangerTint: 'rgba(248, 113, 113, 0.14)',
      page: '#14171c',
      shadow: '0 10px 30px rgba(0, 0, 0, 0.5)',
    },
    blue: {
      label: 'Цэнхэр',
      paper: '#2563b8', paperDim: '#1f57a6', line: '#5b8fd6', lineSoft: '#3f78c8',
      ink: '#ffffff', inkSoft: '#dbe8fb', inkMute: '#b3cbee',
      seal: '#0f3a78', sealDark: '#0b2d5e', sealTint: '#3a74c4', sealText: '#d6e8ff',
      surface: '#2f6ec4', danger: '#fecaca', dangerTint: 'rgba(254, 202, 202, 0.16)',
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
  .hk .hk-danger { background: var(--hk-danger); color: #fff; }
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

  @keyframes hk-fade { from { opacity: 0; } }
  @keyframes hk-rise { from { opacity: 0; transform: translateY(8px) scale(.97); } }
  `;

  function tokens(name) {
    const t = THEMES[name] || THEMES.paper;
    return {
      '--hk-paper': t.paper, '--hk-paper-dim': t.paperDim, '--hk-line': t.line, '--hk-line-soft': t.lineSoft,
      '--hk-ink': t.ink, '--hk-ink-soft': t.inkSoft, '--hk-ink-mute': t.inkMute,
      '--hk-seal': t.seal, '--hk-seal-dark': t.sealDark, '--hk-seal-tint': t.sealTint, '--hk-seal-text': t.sealText,
      '--hk-surface': t.surface, '--hk-danger': t.danger, '--hk-danger-tint': t.dangerTint,
      '--hk-page': t.page, '--hk-shadow': t.shadow,
    };
  }

  const HankoUI = {
    THEMES,
    ORDER,
    ENSO,

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

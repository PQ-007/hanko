// Three looks, the same three as the story images (storyCard.ts styles):
// Цайвар (warm amber paper, white cards, vermilion seal — the default),
// Бараан (dark) and Цэнхэр (seal blue). Per device (localStorage), applied
// before first paint by THEME_SCRIPT in app/layout.tsx so nobody sees a flash
// of the wrong theme. There is deliberately no "follow the system" option.
//
// Two attributes on <html>:
//   data-theme  = "light" | "dark" — what `dark:` utilities key off, so blue
//                 (a dark-type theme) gets every dark-mode fix for free;
//   data-scheme = "paper" | "blue" — re-tints the tokens on top of that.
// The tab icon follows too: /favicon-<theme>.svg on a <link id="hk-icon">
// that the script itself creates. Not rendered by React on purpose: React
// re-inserts its own copy of a hoisted <link> whose href the script changed
// before hydration, and the browser would show that stale icon instead.

export type ThemeChoice = "paper" | "dark" | "blue";
export const THEME_KEY = "hanko.theme";

/** Older stored values ("light", "system", nothing) all land on Цайвар. */
export function readTheme(): ThemeChoice {
  try {
    const v = window.localStorage.getItem(THEME_KEY);
    return v === "dark" || v === "blue" ? v : "paper";
  } catch {
    return "paper";
  }
}

export const ICON_ID = "hk-icon";
export const iconFor = (choice: ThemeChoice) => `/favicon-${choice}.svg`;

function iconLink(): HTMLLinkElement {
  let link = document.getElementById(ICON_ID) as HTMLLinkElement | null;
  if (!link) {
    link = document.createElement("link");
    link.id = ICON_ID;
    link.rel = "icon";
    link.type = "image/svg+xml";
    document.head.appendChild(link);
  }
  return link;
}

export function applyTheme(choice: ThemeChoice) {
  const root = document.documentElement;
  iconLink().href = iconFor(choice);
  root.dataset.theme = choice === "paper" ? "light" : "dark";
  if (choice === "dark") delete root.dataset.scheme;
  else root.dataset.scheme = choice;
}

export function saveTheme(choice: ThemeChoice) {
  try {
    window.localStorage.setItem(THEME_KEY, choice);
  } catch {
    // A preference that doesn't survive a reload is a small loss.
  }
  applyTheme(choice);
}

/** Inline, render-blocking: the same logic as applyTheme, before React loads. */
export const THEME_SCRIPT = `(function(){var r=document.documentElement;var v="paper";try{v=localStorage.getItem("${THEME_KEY}");}catch(e){}if(v!=="dark"&&v!=="blue")v="paper";r.dataset.theme=v==="paper"?"light":"dark";if(v!=="dark")r.dataset.scheme=v;var i=document.getElementById("${ICON_ID}");if(!i){i=document.createElement("link");i.id="${ICON_ID}";i.rel="icon";i.type="image/svg+xml";document.head.appendChild(i);}i.href="/favicon-"+v+".svg";})();`;

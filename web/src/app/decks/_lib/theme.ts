// Light / dark / follow the system. Per device (localStorage), applied as
// html[data-theme]; app/layout.tsx runs THEME_SCRIPT before first paint so a
// dark-theme user never sees a white flash.

export type ThemeChoice = "light" | "dark" | "system";
export const THEME_KEY = "hanko.theme";

export function readTheme(): ThemeChoice {
  try {
    const v = window.localStorage.getItem(THEME_KEY);
    return v === "light" || v === "dark" ? v : "system";
  } catch {
    return "system";
  }
}

export function applyTheme(choice: ThemeChoice) {
  const dark =
    choice === "dark" || (choice === "system" && window.matchMedia("(prefers-color-scheme: dark)").matches);
  document.documentElement.dataset.theme = dark ? "dark" : "light";
}

export function saveTheme(choice: ThemeChoice) {
  try {
    if (choice === "system") window.localStorage.removeItem(THEME_KEY);
    else window.localStorage.setItem(THEME_KEY, choice);
  } catch {
    // A preference that doesn't survive a reload is a small loss.
  }
  applyTheme(choice);
}

/** Inline, render-blocking: the same logic as applyTheme, before React loads. */
export const THEME_SCRIPT = `(function(){try{var v=localStorage.getItem("${THEME_KEY}");var d=v==="dark"||(v!=="light"&&matchMedia("(prefers-color-scheme: dark)").matches);document.documentElement.dataset.theme=d?"dark":"light";}catch(e){}})();`;

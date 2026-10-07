// Hanko's own icon set — drawn for this app, no icon package.
//
// The style is deliberately printed rather than rounded: 1.6px strokes with
// square caps and mitred joins on a 24px grid, the way a woodblock or a
// stamp-cut glyph reads, so the set has a character of its own instead of
// looking like every other app's rounded line icons. Filled shapes are used
// sparingly (the "today" square, the ⋯ dots, play) as solid ink accents.
//
// Text first: most actions are words. An icon exists here only where it
// genuinely helps — navigation, playback, close, menu, undo, search.

import type { SVGProps } from "react";

const PATHS = {
  // Navigation
  today: (
    <>
      <path d="M4 5.5h16V20H4z" />
      <path d="M4 9.5h16M8.5 3v4M15.5 3v4" />
      <path d="M9.5 12.5h5v5h-5z" fill="currentColor" stroke="none" />
    </>
  ),
  // An open book: the library of decks.
  library: (
    <>
      <path d="M12 6.5C10 5 7 4.5 3.5 5v14c3.5-.5 6.5 0 8.5 1.5 2-1.5 5-2 8.5-1.5V5c-3.5-.5-6.5 0-8.5 1.5z" />
      <path d="M12 6.5v14" />
    </>
  ),
  // An ensō — the Zen brush circle, left open: practice is never finished.
  practice: <path d="M17.6 5.6A8 8 0 1 0 20 11.2" strokeWidth="2.2" />,
  progress: (
    <>
      <path d="M3.5 20.5h17" />
      <path d="M6.5 20.5v-5M12 20.5V10M17.5 20.5V4.5" strokeWidth="2.4" />
    </>
  ),
  friends: (
    <>
      <path d="M9 4.5a3.25 3.25 0 1 1 0 6.5 3.25 3.25 0 0 1 0-6.5z" />
      <path d="M3 20c.4-3.6 2.8-5.5 6-5.5s5.6 1.9 6 5.5" />
      <path d="M15.5 5.2a2.8 2.8 0 0 1 0 5.4M17.5 14.6c2 .6 3.2 2.4 3.5 5.4" />
    </>
  ),
  duel: (
    <>
      <path d="M3.5 6.5 10 12l-6.5 5.5z" />
      <path d="M20.5 6.5 14 12l6.5 5.5z" fill="currentColor" />
    </>
  ),
  // A calligraphy brush — handle and an inked tip — for kanji writing.
  write: (
    <>
      <path d="M20.5 3.5 13 11" strokeWidth="2.2" />
      <path
        d="M13 11c-1.7-1.7-4.6-1.2-5.8 1-1 1.9-.5 4.4-3 7.5 3.4-.4 6.4-1.3 8-3.3 1.6-2 1.8-4 .8-5.2z"
        fill="currentColor"
        stroke="none"
      />
    </>
  ),

  // Actions
  plus: <path d="M12 4.5v15M4.5 12h15" />,
  close: <path d="M5.5 5.5l13 13M18.5 5.5l-13 13" />,
  more: (
    <g fill="currentColor" stroke="none">
      <path d="M4 10.75h2.5v2.5H4zM10.75 10.75h2.5v2.5h-2.5zM17.5 10.75H20v2.5h-2.5z" />
    </g>
  ),
  back: <path d="M20 12H5M11 5.5 4.5 12l6.5 6.5" />,
  forward: <path d="M4 12h15M13 5.5l6.5 6.5-6.5 6.5" />,
  chevron: <path d="M9.5 5.5 16 12l-6.5 6.5" />,
  chevronDown: <path d="M5.5 9.5 12 16l6.5-6.5" />,
  undo: (
    <>
      <path d="M8.5 5 4 9.5 8.5 14" />
      <path d="M4 9.5h10a5.5 5.5 0 0 1 0 11H9" />
    </>
  ),
  search: (
    <>
      <path d="M10.5 4a6.5 6.5 0 1 1 0 13 6.5 6.5 0 0 1 0-13z" />
      <path d="M15.5 15.5l5 5" />
    </>
  ),
  adjust: (
    <>
      <path d="M3.5 7h17M3.5 17h17" />
      <path d="M7.5 4.5h3v5h-3zM14 14.5h3v5h-3z" fill="var(--hk-icon-bg, #fff)" />
    </>
  ),
  share: (
    <>
      <path d="M12 15V3.5M7 8l5-4.5L17 8" />
      <path d="M5 11.5V20h14v-8.5" />
    </>
  ),
  download: (
    <>
      <path d="M12 3.5V15M7 10.5l5 4.5 5-4.5" />
      <path d="M4.5 20h15" />
    </>
  ),
  check: <path d="M4.5 12.5 9.5 17.5 19.5 6.5" />,
  trash: (
    <>
      <path d="M4 6.5h16M9.5 6.5V3.5h5v3" />
      <path d="M6 6.5 7 20.5h10l1-14" />
    </>
  ),
  edit: (
    <>
      <path d="M4 20h4.5L19.5 9 15 4.5 4 15.5z" />
    </>
  ),
  folder: <path d="M3.5 5.5h6l2 2.5h9v11.5h-17z" />,
  grid: <path d="M4.5 4.5h6v6h-6zM13.5 4.5h6v6h-6zM4.5 13.5h6v6h-6zM13.5 13.5h6v6h-6z" />,
  list: (
    <>
      <path d="M9 6.5h11M9 12h11M9 17.5h11" />
      <path d="M4 5.5h2v2H4zM4 11h2v2H4zM4 16.5h2v2H4z" fill="currentColor" stroke="none" />
    </>
  ),
  sound: (
    <>
      <path d="M4 9.5h4L13 5v14l-5-4.5H4z" />
      <path d="M16.5 9a4 4 0 0 1 0 6M19 6.5a7.5 7.5 0 0 1 0 11" />
    </>
  ),
  play: <path d="M7 4.5v15l12-7.5z" fill="currentColor" />,
  pause: <path d="M7 5h3.5v14H7zM13.5 5H17v14h-3.5z" fill="currentColor" stroke="none" />,
  signOut: (
    <>
      <path d="M13.5 4H5v16h8.5" />
      <path d="M10 12h10.5M16.5 8l4 4-4 4" />
    </>
  ),
  shuffle: (
    <>
      <path d="M3.5 7H8l8 10h4.5M3.5 17H8l2.5-3M13.5 10 16 7h4.5" />
      <path d="M18 4.5 20.5 7 18 9.5M18 14.5l2.5 2.5-2.5 2.5" />
    </>
  ),
  retry: (
    <>
      <path d="M19.5 12A7.5 7.5 0 1 1 17 6.4" />
      <path d="M19.5 3.5V8H15" />
    </>
  ),
  eye: (
    <>
      <path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z" />
      <path d="M12 9.25a2.75 2.75 0 1 1 0 5.5 2.75 2.75 0 0 1 0-5.5z" fill="currentColor" stroke="none" />
    </>
  ),
  lock: (
    <>
      <path d="M5 10.5h14V20H5z" />
      <path d="M8 10.5V7.5a4 4 0 0 1 8 0v3" />
    </>
  ),
  // A quarter-arc; spin it with `animate-spin`.
  spinner: <path d="M12 3.5A8.5 8.5 0 0 1 20.5 12" strokeWidth="2" />,
  globe: (
    <>
      <path d="M12 3.5a8.5 8.5 0 1 1 0 17 8.5 8.5 0 0 1 0-17z" />
      <path d="M3.5 12h17M12 3.5c-2.6 2.4-3.6 5.2-3.6 8.5s1 6.1 3.6 8.5M12 3.5c2.6 2.4 3.6 5.2 3.6 8.5s-1 6.1-3.6 8.5" />
    </>
  ),
  bot: (
    <>
      <path d="M4.5 8.5h15V19h-15z" />
      <path d="M12 8.5V4.5M10 4.5h4M2 12.5v3M22 12.5v3" />
      <path d="M8.5 12.5h2v2h-2zM13.5 12.5h2v2h-2z" fill="currentColor" stroke="none" />
    </>
  ),
  alert: (
    <>
      <path d="M12 3.5 21 19.5H3z" />
      <path d="M12 9.5v5" />
      <path d="M11 16.5h2v2h-2z" fill="currentColor" stroke="none" />
    </>
  ),
  trophy: (
    <>
      <path d="M7 4.5h10V10a5 5 0 0 1-10 0z" />
      <path d="M7 6.5H4v1.5a3 3 0 0 0 3 3M17 6.5h3v1.5a3 3 0 0 1-3 3M12 15v3.5M8 20.5h8" />
    </>
  ),
  copy: (
    <>
      <path d="M8.5 8.5h11v11h-11z" />
      <path d="M15.5 8.5V4.5h-11v11h4" />
    </>
  ),
  signIn: (
    <>
      <path d="M10.5 4H19v16h-8.5" />
      <path d="M3.5 12H14M10 8l4 4-4 4" />
    </>
  ),
  flame: <path d="M12 3c.5 3.5 5.5 5.5 5.5 10.5a5.5 5.5 0 0 1-11 0c0-2.4 1.2-4 2.5-5 .2 1.8 1 3 2.2 3.4C10.6 9.6 11 6.2 12 3z" />,
  snowflake: (
    <>
      <path d="M12 3v18M4.2 7.5l15.6 9M4.2 16.5l15.6-9" />
      <path d="M9.5 4.5 12 7l2.5-2.5M9.5 19.5 12 17l2.5 2.5" />
    </>
  ),
  skull: (
    <>
      <path d="M5 11a7 7 0 0 1 14 0v4l-2 1v3.5H7V16l-2-1z" />
      <path d="M8.5 10.5h2.5v2.5H8.5zM13 10.5h2.5v2.5H13z" fill="currentColor" stroke="none" />
      <path d="M10.5 19.5V17M13.5 19.5V17" />
    </>
  ),
  sparkle: <path d="M12 3.5c.6 4.4 2.1 6.9 6.5 8.5-4.4 1.6-5.9 4.1-6.5 8.5-.6-4.4-2.1-6.9-6.5-8.5 4.4-1.6 5.9-4.1 6.5-8.5z" />,
  image: (
    <>
      <path d="M3.5 4.5h17v15h-17z" />
      <path d="M3.5 16 9 10.5l4.5 4.5 2.5-2.5 4.5 4.5" />
      <path d="M15 7.5h2.5V10H15z" fill="currentColor" stroke="none" />
    </>
  ),
  languages: (
    <>
      <path d="M3.5 6h9M8 4v2c0 4-2 7-4.5 8.5M5.5 9.5c1 2.5 3 4 5.5 5" />
      <path d="M12.5 20.5l4-10 4 10M14 17h5" />
    </>
  ),
  link: (
    <>
      <path d="M10 14 14 10" />
      <path d="M8.5 11.5 6 14a3.5 3.5 0 0 0 5 5l2.5-2.5M15.5 12.5 18 10a3.5 3.5 0 0 0-5-5l-2.5 2.5" />
    </>
  ),
  refresh: (
    <>
      <path d="M19.5 9A7.5 7.5 0 0 0 5.6 7.2M4.5 15a7.5 7.5 0 0 0 13.9 1.8" />
      <path d="M19.5 3.5V9H14M4.5 20.5V15H10" />
    </>
  ),
  // Two flash cards, the front one tilted: classic card review.
  cards: (
    <>
      <path d="M4 6.5h11v13H4z" />
      <path d="M9 4.5l10.5 2.2-2.6 12.6" />
      <path d="M7 11h5M7 14h3.5" />
    </>
  ),
  // Training without a schedule: free practice.
  dumbbell: (
    <>
      <path d="M8 12h8" strokeWidth="2.2" />
      <path d="M4.5 8h3v8h-3zM16.5 8h3v8h-3z" />
      <path d="M2.5 10.5v3M21.5 10.5v3" />
    </>
  ),
} as const;

export type IconName = keyof typeof PATHS;
export const ICON_NAMES = Object.keys(PATHS) as IconName[];

export default function Icon({
  name,
  size = 20,
  title,
  ...rest
}: { name: IconName; size?: number; title?: string } & Omit<SVGProps<SVGSVGElement>, "name">) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.6}
      strokeLinecap="square"
      strokeLinejoin="miter"
      aria-hidden={title ? undefined : true}
      role={title ? "img" : undefined}
      focusable="false"
      {...rest}
    >
      {title && <title>{title}</title>}
      {PATHS[name]}
    </svg>
  );
}

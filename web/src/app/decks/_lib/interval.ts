import type { Preview } from "@/lib/srs";
import { T } from "./strings";

// A rating button's consequence, in whichever unit is honest for it: cards in
// the learning steps come back in minutes, graduated cards in days.
export function formatPreview(preview: Preview): string {
  return preview.unit === "minutes"
    ? T.intervalMinutes(preview.value)
    : formatInterval(preview.value);
}

// Human-readable "when will I see this again" label for a scheduling
// interval, so each rating button can show its consequence up front rather
// than making the user guess what "Хэцүү" will cost them.
// Months and years keep one decimal place. Rounding them to whole units
// collapses genuinely different schedules onto the same label — 75 and 102
// days are both "3 сар" when rounded, which makes two rating buttons look
// identical even though one buys you a month more.
export function formatInterval(days: number): string {
  if (days < 1) return T.intervalDays(1);
  if (days < 30) return T.intervalDays(Math.round(days));
  if (days < 365) return T.intervalMonths(round1(days / 30));
  return T.intervalYears(Math.max(1, round1(days / 365)));
}

function round1(n: number): number {
  return Math.round(n * 10) / 10;
}

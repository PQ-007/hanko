import { T } from "./strings";

// Human-readable "when will I see this again" label for a scheduling
// interval, so each rating button can show its consequence up front rather
// than making the user guess what "Хэцүү" will cost them.
export function formatInterval(days: number): string {
  if (days < 1) return T.intervalDays(1);
  if (days < 30) return T.intervalDays(Math.round(days));
  if (days < 365) return T.intervalMonths(Math.max(1, Math.round(days / 30)));
  return T.intervalYears(Math.max(1, Math.round((days / 365) * 10) / 10));
}

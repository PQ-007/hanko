// Local-calendar date helpers. Everything here works in the user's own
// timezone on purpose: Mongolia is UTC+8, so slicing an ISO string would
// shift local midnight back into the previous day and misplace activity.

export const WEEKDAY_MN = ["Ня", "Да", "Мя", "Лх", "Пү", "Ба", "Бя"];

export const MONTH_MN = [
  "1-р",
  "2-р",
  "3-р",
  "4-р",
  "5-р",
  "6-р",
  "7-р",
  "8-р",
  "9-р",
  "10-р",
  "11-р",
  "12-р",
];

export function startOfDay(d: Date): Date {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x;
}

export function addDays(d: Date, n: number): Date {
  const x = new Date(d);
  x.setDate(x.getDate() + n);
  return x;
}

// Stable YYYY-MM-DD key in local time, safe to use as a Map/Set key.
export function localDateKey(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

// "3-р сарын 14" — human-readable Mongolian date for tooltips.
export function formatDateMn(d: Date): string {
  return `${MONTH_MN[d.getMonth()]} сарын ${d.getDate()}`;
}

// Longest run of consecutive days present in the set.
export function longestStreak(dayKeys: Set<string>): number {
  if (dayKeys.size === 0) return 0;
  const sorted = [...dayKeys].sort();
  let best = 1;
  let run = 1;
  for (let i = 1; i < sorted.length; i++) {
    const prev = new Date(`${sorted[i - 1]}T00:00:00`);
    const cur = new Date(`${sorted[i]}T00:00:00`);
    const diff = Math.round((cur.getTime() - prev.getTime()) / 86_400_000);
    run = diff === 1 ? run + 1 : 1;
    if (run > best) best = run;
  }
  return best;
}

// Current run ending today (or yesterday — a streak stays alive until the
// day is actually over).
export function currentStreak(dayKeys: Set<string>): number {
  const cursor = startOfDay(new Date());
  if (!dayKeys.has(localDateKey(cursor))) cursor.setDate(cursor.getDate() - 1);
  let streak = 0;
  while (dayKeys.has(localDateKey(cursor))) {
    streak += 1;
    cursor.setDate(cursor.getDate() - 1);
  }
  return streak;
}

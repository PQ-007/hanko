import { GRADE_COLOR } from "./gradeColors";

// Sequential scale for the activity heatmap. Magnitude data -> one hue,
// light->dark. These are the exact five blue steps already validated in
// gradeColors.ts (adjacent-lightness gap + light-surface contrast floor);
// reusing them verbatim keeps the whole app on one checked ramp instead of
// introducing a second, unvalidated set of blues.
export const HEATMAP_STEPS = [
  GRADE_COLOR.F.fill, // #86b6ef  lightest — least activity
  GRADE_COLOR.D.fill, // #3987e5
  GRADE_COLOR.C.fill, // #256abf
  GRADE_COLOR.B.fill, // #184f95
  GRADE_COLOR.A.fill, // #0d366b  darkest — most activity
] as const;

// A day with no reviews is chart furniture, not a data value, so it sits
// outside the ramp as a neutral surface tint.
export const HEATMAP_EMPTY = "#ebedf0";

// Maps a day's review count onto a ramp step. Thresholds are relative to the
// user's own busiest day so the scale stays meaningful whether they do 5
// reviews a day or 200.
export function heatmapColor(count: number, max: number): string {
  if (count <= 0) return HEATMAP_EMPTY;
  if (max <= 1) return HEATMAP_STEPS[2];
  const ratio = count / max;
  if (ratio <= 0.25) return HEATMAP_STEPS[0];
  if (ratio <= 0.5) return HEATMAP_STEPS[1];
  if (ratio <= 0.75) return HEATMAP_STEPS[2];
  if (ratio < 1) return HEATMAP_STEPS[3];
  return HEATMAP_STEPS[4];
}

// Single accent for one-series charts (same ramp, mid step).
export const ACCENT = GRADE_COLOR.D.fill;
export const ACCENT_DARK = GRADE_COLOR.A.fill;

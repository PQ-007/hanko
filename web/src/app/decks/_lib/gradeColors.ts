import type { Grade } from "@/lib/srs";

// One-hue ordinal ramp (blue, light -> dark = weak -> strong mastery), validated
// with the data-viz skill's palette checker: 5 steps clear the 0.06 min-adjacent-
// lightness gap and the light-surface 2:1 floor (6 steps do not, at this app's
// palette resolution — see conversation). "New" sits outside the ramp as a
// neutral, since it's "not graded yet" rather than the worst grade.
export const GRADE_ORDER: Grade[] = ["new", "F", "D", "C", "B", "A"];

export const GRADE_COLOR: Record<Grade, { fill: string; text: string }> = {
  new: { fill: "#898781", text: "#0b0b0b" },
  F: { fill: "#86b6ef", text: "#0b0b0b" },
  D: { fill: "#3987e5", text: "#0b0b0b" },
  C: { fill: "#256abf", text: "#ffffff" },
  B: { fill: "#184f95", text: "#ffffff" },
  A: { fill: "#0d366b", text: "#ffffff" },
};

import { T } from "../../_lib/strings";
import type { StrokeGrade } from "./strokes";

/** What went wrong with a checked kanji, in one line (mobile's missMessage). */
export function missMessage(g: StrokeGrade): string {
  const i = (g.stroke ?? 0) + 1;
  switch (g.issue) {
    case "count":
      return T.writingStrokeCount(g.drawn, g.expected);
    case "order":
      return T.writingStrokeOrder(i, (g.expectedStroke ?? 0) + 1);
    case "direction":
      return T.writingStrokeDirection(i);
    default:
      return T.writingStrokeShape(i);
  }
}

import { highlightRange, rubyUnits } from "@/lib/examples";

/**
 * A Japanese sentence with furigana over its kanji (when `furigana` describes
 * it) and the word `term` picked out. The mobile side is the sentence half of
 * example_line.dart.
 */
export default function RubySentence({
  ja,
  furigana,
  term,
  className = "",
}: {
  ja: string;
  furigana?: string | null;
  term: string;
  className?: string;
}) {
  const units = rubyUnits(ja, furigana);
  const mark = highlightRange(ja, term);
  // Each unit's start in the sentence, to know which ones the word covers.
  const starts = units.map((_, i) => units.slice(0, i).reduce((n, u) => n + u.text.length, 0));
  return (
    <span lang="ja" className={className}>
      {units.map((u, i) => {
        const start = starts[i];
        const marked = mark !== null && start < mark[1] && start + u.text.length > mark[0];
        const cls = marked ? "font-semibold text-seal" : undefined;
        return u.reading ? (
          <ruby key={i} className={cls}>
            {u.text}
            <rt className="text-[0.6em] font-normal text-ink-mute">{u.reading}</rt>
          </ruby>
        ) : (
          <span key={i} className={cls}>
            {u.text}
          </span>
        );
      })}
    </span>
  );
}

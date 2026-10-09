import type { QuizOption } from "../../battle/_lib/quiz";

// The question set the server plans when a match starts (0030
// duel_plan_questions) and stores on `matches.questions`: both players answer
// the same words with the same four options in the same order. Parsed here
// rather than trusted — an older match has null, and a malformed set must
// degrade to "each player's own deck" (the pre-0030 behaviour), not crash.

export interface SharedQuestion {
  term: string;
  reading: string | null;
  options: string[];
  /** Index of the right option. */
  answer: number;
}

export function parseQuestions(raw: unknown): SharedQuestion[] | null {
  if (!Array.isArray(raw)) return null;
  const out: SharedQuestion[] = [];
  for (const q of raw) {
    if (!q || typeof q !== "object") continue;
    const { term, reading, options, answer } = q as Record<string, unknown>;
    if (
      typeof term !== "string" ||
      !Array.isArray(options) ||
      options.length !== 4 ||
      !options.every((o) => typeof o === "string") ||
      typeof answer !== "number" ||
      !Number.isInteger(answer) ||
      answer < 0 ||
      answer > 3
    ) {
      continue;
    }
    out.push({ term, reading: typeof reading === "string" ? reading : null, options: options as string[], answer });
  }
  return out.length > 0 ? out : null;
}

/** The question for a round (1-based); wraps when a match outlasts the set. */
export function questionFor(questions: SharedQuestion[], roundNo: number): SharedQuestion {
  return questions[(Math.max(1, roundNo) - 1) % questions.length];
}

/** The four options as QuizOption rows, in the server's order. */
export function quizFor(q: SharedQuestion): QuizOption[] {
  return q.options.map((text, i) => ({
    term: `${q.term}#${i}`,
    reading: null,
    answerText: text,
    correct: i === q.answer,
  }));
}

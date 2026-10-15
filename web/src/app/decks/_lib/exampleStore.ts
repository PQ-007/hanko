import { plainOf, type Example } from "../../../lib/examples.ts";

// The example sentence part of the add and edit dialogs (0031): a Tatoeba
// suggestion for the word with its English translation, the Mongolian
// machine-translated from the English, all three editable.
//
// A port of ExampleController in mobile/lib/features/decks/example_section.dart,
// pinned by the same cases (exampleStore.test.ts / word_example_test.dart).
// Plain class + subscribe rather than a hook, so the rules run under
// `node --test` with no React; useExample() in ExampleSection.tsx wraps it.
//
// A suggestion only ever lands in fields the user hasn't written in: once
// they type, the sentence is theirs, and a new term doesn't replace it.

export interface WordExample {
  ja: string;
  en: string;
  mn: string;
  /** Reading markup for `ja` (0032), from Tatoeba; absent for a sentence the user wrote. */
  furigana?: string;
}

/** `e.furigana` if it still describes `e.ja` — an edited sentence loses it. */
export function furiganaFor(e: { ja: string; furigana?: string | null }): string | undefined {
  const f = e.furigana?.trim();
  return f && plainOf(f) === e.ja.trim() ? f : undefined;
}

export const NO_EXAMPLE: WordExample = { ja: "", en: "", mn: "" };

export interface ExampleState extends WordExample {
  looking: boolean;
  /** Tatoeba had nothing good for the word. */
  none: boolean;
  translating: boolean;
}

export interface ExampleDeps {
  find: (term: string) => Promise<Example | null>;
  /** English → Mongolian, whole sentence; "" on failure. */
  translate: (text: string) => Promise<string>;
}

const isEmpty = (e: WordExample) => !e.ja.trim() && !e.en.trim() && !e.mn.trim();

/** The row values, empty parts as null (so clearing really clears). */
export function exampleRow(e: WordExample) {
  return {
    example_ja: e.ja.trim() || null,
    example_en: e.en.trim() || null,
    example_mn: e.mn.trim() || null,
    example_furigana: furiganaFor(e) ?? null,
  };
}

/** A word row's sentence, or null when it has none (or predates 0031). */
export function exampleOf(row: {
  example_ja?: string | null;
  example_en?: string | null;
  example_mn?: string | null;
  example_furigana?: string | null;
}): WordExample | null {
  const ja = (row.example_ja ?? "").trim();
  if (!ja) return null;
  const e: WordExample = { ja, en: (row.example_en ?? "").trim(), mn: (row.example_mn ?? "").trim() };
  const f = furiganaFor({ ja, furigana: row.example_furigana });
  return f ? { ...e, furigana: f } : e;
}

export class ExampleStore {
  private state: ExampleState;
  private listeners = new Set<() => void>();
  private auto = false;
  private query: string | null = null;
  private context: string | null = null;
  private lastEn: string;
  /** The suggestion's reading; kept out of the editable fields. */
  private furigana: string | undefined;
  /** The search for `query`, kept so a save can finish it after the form has moved on (take). */
  private found: Promise<Example | null> | null = null;
  private seq = 0;

  private deps: ExampleDeps;

  // No parameter properties: node's type stripping can't run them.
  constructor(deps: ExampleDeps, initial?: WordExample | null) {
    this.deps = deps;
    this.state = { ...(initial ?? NO_EXAMPLE), looking: false, none: false, translating: false };
    this.lastEn = initial?.en ?? "";
    this.furigana = initial?.furigana;
  }

  // ---- for useSyncExternalStore ----
  subscribe = (fn: () => void) => {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  };
  get = () => this.state;

  private patch(p: Partial<ExampleState>) {
    this.state = { ...this.state, ...p };
    for (const fn of this.listeners) fn();
  }

  get isEmpty() {
    return isEmpty(this.state);
  }

  get value(): WordExample {
    const v = { ja: this.state.ja.trim(), en: this.state.en.trim(), mn: this.state.mn.trim() };
    const f = furiganaFor({ ja: v.ja, furigana: this.furigana });
    return f ? { ...v, furigana: f } : v;
  }

  /**
   * Suggest a sentence for `query` (the dictionary form), found while the
   * user's term was `context`. An empty query withdraws a suggestion.
   */
  suggest(query: string, context?: string) {
    const q = query.trim();
    if (!this.auto && !this.isEmpty) return;
    this.context = context ?? q;
    if (q === this.query) return;
    this.query = q;
    const mine = ++this.seq;
    const clear = this.auto ? NO_EXAMPLE : {};
    this.auto = false;
    this.patch({ ...clear, none: false, looking: q !== "" });
    this.found = q ? this.deps.find(q) : null;
    if (this.found) void this.fetch(this.found, mine);
  }

  private async fetch(found: Promise<Example | null>, mine: number) {
    const hit = await found;
    if (mine !== this.seq) return;
    if (!this.isEmpty) {
      this.patch({ looking: false }); // typed in while we waited: theirs wins
      return;
    }
    if (!hit) {
      this.patch({ looking: false, none: true });
      return;
    }
    this.auto = true;
    this.furigana = hit.furigana;
    this.patch({ looking: false, ja: hit.ja, en: hit.en, mn: "" });
    await this.translate(hit.en, mine);
  }

  private async translate(text: string, mine: number) {
    this.lastEn = text;
    this.patch({ translating: true });
    const out = await this.deps.translate(text);
    const keep = out && mine === this.seq && this.state.en.trim() === text;
    this.patch({ translating: false, ...(keep ? { mn: out } : {}) });
  }

  /** A field the user typed into: the sentence is theirs now. */
  edit(field: keyof WordExample, v: string) {
    this.auto = false;
    this.patch({ [field]: v });
  }

  /** English edited by hand gets a fresh Mongolian translation. */
  async englishLeft() {
    const t = this.state.en.trim();
    if (!t || t === this.lastEn) return;
    await this.translate(t, this.seq);
  }

  /** Fetch a suggestion even over what's there (the edit dialog's button). */
  research(term: string) {
    this.patch(NO_EXAMPLE);
    this.auto = true;
    this.query = null;
    this.suggest(term);
  }

  clear() {
    this.seq++;
    this.auto = false;
    this.query = null;
    this.context = null;
    this.found = null;
    this.patch({ ...NO_EXAMPLE, looking: false, none: false });
  }

  /**
   * What to save with `term`, without waiting — Tatoeba alone takes 1–4 s,
   * and the word must not. `now` goes in with the word. `later`, when a
   * sentence or its translation is still on its way, finishes on its own
   * (even after the form is cleared or closed) for the caller to attach once
   * it lands (attachExampleLater). A suggestion found for some other term —
   * the user typed on before it settled — is dropped rather than saved under
   * the wrong word.
   */
  take(term: string): { now: WordExample; later: Promise<WordExample | null> | null } {
    const t = term.trim();
    const stale = t !== this.context && t !== this.query;
    const found = this.found;
    if (this.state.looking && this.isEmpty) {
      return { now: NO_EXAMPLE, later: stale || !found ? null : this.finish(found) };
    }
    if (this.auto && stale) return { now: NO_EXAMPLE, later: null };
    const v = this.value;
    // Mongolian not in yet: the sentence goes in whole, a moment later.
    if (v.en && !v.mn) return { now: NO_EXAMPLE, later: this.translated(v) };
    return { now: v, later: null };
  }

  private async finish(found: Promise<Example | null>): Promise<WordExample | null> {
    const hit = await found;
    return hit ? this.translated({ ja: hit.ja, en: hit.en, mn: "", ...(hit.furigana ? { furigana: hit.furigana } : {}) }) : null;
  }

  private async translated(v: WordExample): Promise<WordExample> {
    return { ...v, mn: await this.deps.translate(v.en) };
  }
}

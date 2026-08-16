import type { CardState, Word } from "@/lib/types";

// A word search hit, with its deck name joined in.
export type WordHit = Word & { deck?: { name: string } | null };

// One row of the review queue: a card joined to the word it drills. Shape is
// fixed by the review_queue() RPC in supabase/migrations/0010_review_queue.sql —
// the server decides what's due (day cutoff, daily caps), not the client.
export interface QueueCard {
  card_id: string;
  word_id: string;
  deck_id: string;
  template: string;
  state: CardState;
  learning_step: number;
  due_at: string;
  interval_days: number;
  repetitions: number;
  ease_factor: number;
  term: string;
  reading: string | null;
  meaning: string | null;
  meaning_mn: string | null;
  audio_path: string | null;
}

export type WordView = "list" | "grid";

// Shared row shapes for the decks/words tables (mirrors supabase/migrations).

export interface Folder {
  id: string;
  user_id: string;
  name: string;
  created_at: string;
  updated_at: string;
  deleted: boolean;
}

export interface Deck {
  id: string;
  user_id: string;
  name: string;
  folder_id: string | null;
  created_at: string;
  updated_at: string;
  deleted: boolean;
}

export interface Word {
  id: string;
  deck_id: string;
  user_id: string;
  term: string;
  reading: string | null;
  meaning: string | null;
  meaning_mn: string | null;
  audio_path: string | null;
  date_added: string;
  updated_at: string;
  deleted: boolean;
  ease_factor: number;
  interval_days: number;
  repetitions: number;
  due_at: string;
  last_reviewed_at: string | null;
}

export interface DeckWithCount extends Deck {
  word_count: number;
}

// Scheduling state lives on cards, not words (supabase/migrations/0006_cards.sql):
// one word can carry several cards — recognition, recall, reading, audio — each
// scheduled independently. `words` keeps its own SRS columns for one more
// release so the deployed extension and web build keep working; review_card()
// mirrors state into them.
export type CardState = "new" | "learning" | "review" | "relearning";

export interface Card {
  id: string;
  word_id: string;
  user_id: string;
  template: "recognition" | "recall" | "reading" | "audio";
  state: CardState;
  learning_step: number;
  ease_factor: number;
  interval_days: number;
  repetitions: number;
  lapses: number;
  suspended: boolean;
  due_at: string;
  last_reviewed_at: string | null;
  created_at: string;
  updated_at: string;
}

// Shared row shapes for the decks/words tables (mirrors supabase/migrations).

export interface Deck {
  id: string;
  user_id: string;
  name: string;
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
}

export interface DeckWithCount extends Deck {
  word_count: number;
}

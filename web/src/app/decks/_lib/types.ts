import type { Word } from "@/lib/types";

// A word search hit, with its deck name joined in.
export type WordHit = Word & { deck?: { name: string } | null };

export type WordView = "list" | "grid";

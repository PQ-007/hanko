import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { createClient } from "@/lib/supabase/server";
import { T } from "../../decks/_lib/strings";
import { fetchSharedDeck } from "../_lib/fetchShared";
import SharedDeckView from "./SharedDeckView";

// A shared deck (0028): public, no account needed. Outside /decks on purpose —
// the proxy only gates /decks, so a signed-out visitor lands here, not /login.

export async function generateMetadata({ params }: { params: Promise<{ token: string }> }): Promise<Metadata> {
  const { token } = await params;
  const deck = await fetchSharedDeck(token);
  if (!deck) return { title: T.sharedBy, robots: { index: false } };
  const title = deck.name;
  const description = `${T.sharedWords(deck.words.length)} · ${T.sharedPitch}`;
  return {
    title,
    description,
    // Links are meant to be passed around, not found by search engines.
    robots: { index: false },
    openGraph: { title, description, type: "website" },
    twitter: { card: "summary_large_image", title, description },
  };
}

export default async function SharedDeckPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const deck = await fetchSharedDeck(token);
  if (!deck) notFound();

  let signedIn = false;
  try {
    const supabase = await createClient();
    signedIn = !!(await supabase.auth.getUser()).data.user;
  } catch {
    // No session or Supabase unreachable — treat as a visitor.
  }

  return (
    <Suspense>
      <SharedDeckView deck={deck} token={token} signedIn={signedIn} />
    </Suspense>
  );
}

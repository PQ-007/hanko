import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{ code?: string; next?: string }>;
}) {
  // After Google sign-in Supabase may land back on the Site URL ("/") with the
  // OAuth ?code=. Forward it to the callback route so it gets exchanged for a
  // session (instead of being ignored here).
  const { code, next } = await searchParams;
  if (code) {
    const params = new URLSearchParams({ code });
    if (next) params.set("next", next);
    redirect(`/auth/callback?${params.toString()}`);
  }

  let user = null;
  try {
    const supabase = await createClient();
    const res = await supabase.auth.getUser();
    user = res.data.user;
  } catch {
    // Supabase not configured / unreachable — send to login rather than 500.
  }

  redirect(user ? "/decks" : "/login");
}

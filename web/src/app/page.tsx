import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export default async function Home() {
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

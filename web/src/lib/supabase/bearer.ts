import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { createClient as createCookieClient } from "@/lib/supabase/server";
import type { SupabaseClient } from "@supabase/supabase-js";

// Route handlers are called by two different kinds of client:
//
//   - the web app, which authenticates with the SSR cookie session
//   - the Flutter app, which has no cookies and sends `Authorization: Bearer`
//
// This picks whichever applies. The bearer client is built per-request with the
// caller's own token, so Row Level Security still scopes every query to that
// user — this is not a service-role bypass.
export async function clientForRequest(request: Request): Promise<SupabaseClient> {
  const auth = request.headers.get("authorization");
  const token = auth?.toLowerCase().startsWith("bearer ")
    ? auth.slice(7).trim()
    : null;

  if (!token) return await createCookieClient();

  return createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    (process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY)!,
    {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    }
  );
}

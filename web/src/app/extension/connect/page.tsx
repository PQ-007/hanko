"use client";

import { Suspense, useEffect, useRef, useState } from "react";
import { createClient } from "@supabase/supabase-js";

// Standalone Supabase client using the *implicit* flow so the access + refresh
// tokens come back in the URL hash — which is exactly what we need to forward
// to the browser extension. (The main app uses the cookie-based SSR client; this
// page is a separate, self-contained bridge.)
//
// Built lazily inside the browser-only effect: creating it at module scope would
// run during Vercel's build-time prerender, where the env vars aren't inlined
// yet, and throw "supabaseUrl is required".
function makeSupabase() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    (process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY)!,
    { auth: { flowType: "implicit", detectSessionInUrl: true, persistSession: false } }
  );
}

function ConnectInner() {
  const [message, setMessage] = useState("Connecting…");
  const started = useRef(false);

  useEffect(() => {
    if (started.current) return;
    started.current = true;

    (async () => {
      const supabase = makeSupabase();
      // The extension passes its identity redirect URL as ?cb=...
      const cb = new URLSearchParams(window.location.search).get("cb");

      // If we already have a session (we're back from Google), hand the tokens
      // to the extension via its callback URL.
      const {
        data: { session },
      } = await supabase.auth.getSession();

      if (session) {
        // Hand the session to the extension's content-script bridge, which runs
        // on this page and forwards it to the extension background to store.
        window.postMessage(
          {
            source: "vocab-decks",
            access_token: session.access_token,
            refresh_token: session.refresh_token,
          },
          window.location.origin
        );

        if (cb) {
          // Legacy launchWebAuthFlow path (kept for compatibility).
          const hash = new URLSearchParams({
            access_token: session.access_token,
            refresh_token: session.refresh_token,
          }).toString();
          window.location.replace(`${cb}#${hash}`);
        }
        setMessage("Signed in! You can close this tab — your decks will sync.");
        return;
      }

      // No session yet → start Google OAuth, returning to this same page
      // (preserving cb) so the effect above can forward the tokens.
      setMessage("Redirecting to Google…");
      const redirectTo = `${window.location.origin}/extension/connect${
        cb ? `?cb=${encodeURIComponent(cb)}` : ""
      }`;
      const { error } = await supabase.auth.signInWithOAuth({
        provider: "google",
        options: { redirectTo },
      });
      if (error) setMessage(`Sign-in failed: ${error.message}`);
    })();
  }, []);

  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-3 p-8 text-center">
      <h1 className="text-xl font-semibold">Hanko</h1>
      <p className="text-sm text-ink-soft">{message}</p>
    </main>
  );
}

export default function ConnectPage() {
  return (
    <Suspense>
      <ConnectInner />
    </Suspense>
  );
}

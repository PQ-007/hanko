"use client";

import { Suspense, useState } from "react";
import { useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

function LoginInner() {
  const params = useSearchParams();
  const next = params.get("next") ?? "/decks";
  const error = params.get("error");
  const [loading, setLoading] = useState(false);

  async function signIn() {
    setLoading(true);
    const supabase = createClient();
    const redirectTo = `${window.location.origin}/auth/callback?next=${encodeURIComponent(
      next
    )}`;
    await supabase.auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo },
    });
  }

  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-6 p-8">
      <div className="flex flex-col items-center text-center">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/hanko.svg" alt="" className="mb-3 h-14 w-14" />
        <h1 className="text-3xl font-semibold">Hanko</h1>
        <p className="text-sm italic text-gray-400">Verba non Acta</p>
        <p className="mt-2 text-sm text-gray-500">
          Үгсийн багцаа удирдах, төхөөрөмж хооронд синк хийх, Anki руу
          экспортлохын тулд нэвтэрнэ үү.
        </p>
      </div>

      {error && (
        <p className="rounded border border-gray-300 bg-gray-100 px-4 py-2 text-sm text-gray-800">
          Нэвтрэлт амжилтгүй боллоо. Дахин оролдоно уу.
        </p>
      )}

      <button
        onClick={signIn}
        disabled={loading}
        className="flex items-center gap-3 rounded-lg border border-gray-300 bg-white px-6 py-3 font-medium text-gray-800 shadow-sm transition hover:bg-gray-50 disabled:opacity-60"
      >
        <GoogleIcon />
        {loading ? "Шилжүүлж байна…" : "Google-ээр нэвтрэх"}
      </button>
    </main>
  );
}

export default function LoginPage() {
  return (
    <Suspense>
      <LoginInner />
    </Suspense>
  );
}

function GoogleIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 48 48" aria-hidden>
      <path
        fill="#EA4335"
        d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"
      />
      <path
        fill="#4285F4"
        d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"
      />
      <path
        fill="#FBBC05"
        d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"
      />
      <path
        fill="#34A853"
        d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"
      />
    </svg>
  );
}

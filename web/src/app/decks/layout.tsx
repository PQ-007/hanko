import { createClient } from "@/lib/supabase/server";
import HeaderNav from "./_components/HeaderNav";
import EnsureTimezone from "./_components/EnsureTimezone";

export default async function DecksLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <div className="flex min-h-screen flex-col bg-gradient-to-b from-paper to-paper-dim text-ink">
      <EnsureTimezone userId={user?.id} />
      {/* Translucent + blurred rather than flat white: the header stays
          legible over whatever scrolls under it without drawing a hard line
          across the page, which is what made the old chrome feel boxy. */}
      <header className="sticky top-0 z-20 border-b border-line/70 bg-white/80 backdrop-blur-md">
        <div className="mx-auto flex w-full max-w-[1400px] flex-wrap items-center justify-between gap-3 px-4 py-2.5 sm:px-6">
          <h1 className="flex items-center gap-2.5 text-base font-semibold tracking-tight">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/hanko.svg" alt="" className="h-7 w-7" />
            <span className="flex items-baseline gap-2">
              Hanko
              <span className="hidden text-xs font-normal italic text-ink-mute sm:inline">
                Verba non Acta
              </span>
            </span>
          </h1>
          <HeaderNav />
          <div className="flex items-center gap-3 text-sm text-ink-soft">
            <span className="hidden max-w-[180px] truncate text-xs md:inline">
              {user?.email}
            </span>
            <form action="/auth/signout" method="post">
              <button
                type="submit"
                className="rounded-control px-3 py-1.5 text-xs font-medium text-ink-soft transition hover:bg-paper-dim hover:text-ink"
              >
                Гарах
              </button>
            </form>
          </div>
        </div>
      </header>
      <main className="flex-1">{children}</main>
    </div>
  );
}

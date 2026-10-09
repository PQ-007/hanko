import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import HeaderNav from "./_components/HeaderNav";
import EnsureTimezone from "./_components/EnsureTimezone";
import TabBar from "./_components/TabBar";
import PageTitle from "./_components/PageTitle";
import DuelInviteToast from "./_components/DuelInviteToast";
import { T } from "./_lib/strings";
import { Settings2 } from "@/ui/icons";

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
    // An app shell, not a scrolling page: the bars stay put and only <main>
    // scrolls (h-dvh tracks the real visible height as mobile browser bars
    // come and go). Below lg the header slims down and the tabs move to a
    // bottom bar, like the mobile app; sessions hide both (useImmersive).
    <div className="flex h-dvh flex-col overflow-hidden bg-gradient-to-b from-paper to-paper-dim text-ink">
      <EnsureTimezone userId={user?.id} />
      <header className="hk-chrome z-20 shrink-0 border-b border-line/70 bg-surface/80 pt-[env(safe-area-inset-top)] backdrop-blur-md">
        {/* max-width and px match the content containers below (DeckDashboard,
            StatsDashboard) so the logo/nav line up with the page content's
            left/right edges instead of drifting at wider viewports. */}
        <div className="mx-auto flex w-full max-w-[1700px] items-center justify-between gap-3 px-4 py-2 sm:px-8 lg:py-2.5">
          <h1 className="flex min-w-0 items-center gap-2.5 text-base font-semibold tracking-tight">
            <PageTitle />
            <span className="hidden items-baseline gap-2 lg:flex">
              Hanko
              <span className="hidden text-xs font-normal italic text-ink-mute sm:inline">
                Verba non Acta
              </span>
            </span>
          </h1>
          <div className="hidden lg:block">
            <HeaderNav />
          </div>
          <div className="flex items-center gap-3 text-sm text-ink-soft">
            <span className="hidden max-w-[180px] truncate text-xs xl:inline">
              {user?.email}
            </span>
            {/* Settings (theme, profile, limits) — sign-out lives there too. */}
            <Link
              href="/decks/settings"
              title={T.settingsTitle}
              aria-label={T.settingsTitle}
              className="flex items-center gap-1.5 rounded-control px-2.5 py-1.5 text-xs font-medium text-ink-soft transition hover:bg-paper-dim hover:text-ink"
            >
              <Settings2 size={17} />
              <span className="hidden sm:inline">{T.settingsTitle}</span>
            </Link>
          </div>
        </div>
      </header>
      <main id="hk-main" className="hk-main min-h-0 flex-1 overflow-y-auto overscroll-contain">
        {children}
      </main>
      <TabBar />
      <DuelInviteToast />
    </div>
  );
}

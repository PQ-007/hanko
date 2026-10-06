"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Layers, LayoutDashboard, Swords, Trophy, Users } from "lucide-react";
import { T } from "../_lib/strings";

// The phone/tablet navigation — the mobile app's bottom bar: four tabs and a
// raised Review button in the middle. Hidden from lg up, where the header
// carries the same links.
const TABS = [
  { href: "/decks/stats", label: T.homeTab, icon: LayoutDashboard },
  { href: "/decks", label: T.decksNav, icon: Layers },
  { href: "/decks/review", label: T.practiceNav, icon: Swords, center: true },
  { href: "/decks/review/duel", label: T.duelTab, icon: Trophy },
  { href: "/decks/friends", label: T.friendsNav, icon: Users },
];

function isActive(pathname: string, href: string) {
  if (href === "/decks/review") return pathname === href || pathname === "/decks/review/battle" || pathname === "/decks/writing";
  return pathname === href || pathname.startsWith(href + "/");
}

export default function TabBar() {
  const pathname = usePathname();
  return (
    <nav
      className="hk-chrome grid shrink-0 grid-cols-5 border-t border-line/70 bg-white/95 pb-[env(safe-area-inset-bottom)] backdrop-blur-md lg:hidden"
      aria-label={T.mainNav}
    >
      {TABS.map(({ href, label, icon: Icon, center }) => {
        const active = isActive(pathname, href);
        if (center) {
          return (
            <Link key={href} href={href} className="flex flex-col items-center justify-end pb-1.5" aria-current={active ? "page" : undefined}>
              <span
                className={`-mt-5 flex h-14 w-14 items-center justify-center rounded-full text-white shadow-lg ring-4 ring-paper transition active:scale-95 ${
                  active ? "bg-seal-dark" : "bg-seal"
                }`}
              >
                <Icon size={24} />
              </span>
              <span className={`mt-0.5 text-[10px] font-semibold ${active ? "text-seal" : "text-ink-soft"}`}>{label}</span>
            </Link>
          );
        }
        return (
          <Link
            key={href}
            href={href}
            aria-current={active ? "page" : undefined}
            className={`flex flex-col items-center justify-center gap-0.5 py-2 transition active:scale-95 ${
              active ? "text-seal" : "text-ink-mute"
            }`}
          >
            <Icon size={21} strokeWidth={active ? 2.4 : 1.9} />
            <span className="text-[10px] font-semibold">{label}</span>
          </Link>
        );
      })}
    </nav>
  );
}

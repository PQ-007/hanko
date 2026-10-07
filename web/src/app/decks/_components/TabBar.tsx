"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import MaterialIcon, { type MaterialName } from "@/ui/MaterialIcon";
import { T } from "../_lib/strings";

// The phone/tablet navigation — the mobile app's bottom bar, with the mobile
// app's own icons (Material, outlined → filled when active, a tinted pill
// behind the active one) and its raised blue "+" in the middle. Hidden from
// lg up, where the header carries the same links.
const TABS: { href: string; label: string; icon: MaterialName; active: MaterialName; center?: boolean }[] = [
  { href: "/decks/stats", label: T.homeTab, icon: "home_outlined", active: "home" },
  { href: "/decks", label: T.decksNav, icon: "collections_bookmark_outlined", active: "collections_bookmark" },
  { href: "/decks/review", label: T.practiceNav, icon: "add", active: "add", center: true },
  { href: "/decks/review/duel", label: T.duelTab, icon: "sports_kabaddi", active: "sports_kabaddi" },
  { href: "/decks/friends", label: T.friendsNav, icon: "groups_outlined", active: "groups" },
];

function isActive(pathname: string, href: string) {
  if (href === "/decks/review") return pathname === href || pathname === "/decks/review/battle" || pathname === "/decks/writing";
  // "/decks" is the parent of every route here, so it must match exactly.
  if (href === "/decks") return pathname === "/decks";
  return pathname === href || pathname.startsWith(href + "/");
}

export default function TabBar() {
  const pathname = usePathname();
  return (
    <nav
      className="hk-chrome grid shrink-0 grid-cols-5 border-t border-line/70 bg-surface/95 pb-[env(safe-area-inset-bottom)] backdrop-blur-md lg:hidden"
      aria-label={T.mainNav}
    >
      {TABS.map(({ href, label, icon, active: activeIcon, center }) => {
        const active = isActive(pathname, href);
        if (center) {
          return (
            <Link
              key={href}
              href={href}
              aria-label={label}
              aria-current={active ? "page" : undefined}
              className="flex flex-col items-center justify-center py-1.5"
            >
              <span
                className={`flex h-[52px] w-[52px] items-center justify-center rounded-full text-white shadow-[0_3px_10px_rgba(24,79,149,0.35)] transition active:scale-95 ${
                  active ? "bg-seal-dark" : "bg-seal"
                }`}
              >
                <MaterialIcon name="add" size={30} />
              </span>
            </Link>
          );
        }
        return (
          <Link
            key={href}
            href={href}
            aria-current={active ? "page" : undefined}
            className={`flex flex-col items-center justify-center gap-1 pb-2 pt-3 transition active:scale-95 ${
              active ? "text-ink" : "text-ink-soft"
            }`}
          >
            <span
              className={`flex h-8 w-14 items-center justify-center rounded-full transition-colors ${active ? "bg-seal-tint text-seal-dark" : ""}`}
            >
              <MaterialIcon name={active ? activeIcon : icon} size={24} />
            </span>
            <span className={`text-[11px] ${active ? "font-bold" : "font-medium"}`}>{label}</span>
          </Link>
        );
      })}
    </nav>
  );
}

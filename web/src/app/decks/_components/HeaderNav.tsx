"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { LayoutDashboard, Layers, Swords } from "lucide-react";
import { T } from "../_lib/strings";

const LINKS = [
  { href: "/decks/stats", label: T.dashboardNav, icon: LayoutDashboard },
  { href: "/decks", label: T.decksNav, icon: Layers },
  { href: "/decks/review", label: T.practiceNav, icon: Swords },
];

export default function HeaderNav() {
  const pathname = usePathname();

  return (
    <nav className="flex items-center gap-1">
      {LINKS.map(({ href, label, icon: Icon }) => {
        // Exact match for every existing tab, except /decks/review: that's
        // the first nav entry with a nested route (/decks/review/battle),
        // and without this it would stop looking active the moment a fight
        // starts — a stricter startsWith would also wrongly light up
        // "Decks" while inside /decks/review, so this stays scoped to the
        // one entry that actually needs it rather than changing the rule
        // for all three.
        const active =
          href === "/decks/review"
            ? pathname === href || pathname.startsWith(href + "/")
            : pathname === href;
        return (
          <Link
            key={href}
            href={href}
            className={`flex items-center gap-1.5 rounded-control px-3 py-1.5 text-sm font-medium transition ${
              active
                ? "bg-seal text-white shadow-sm"
                : "text-ink-soft hover:bg-paper-dim hover:text-ink"
            }`}
          >
            <Icon size={15} />
            <span className="hidden sm:inline">{label}</span>
          </Link>
        );
      })}
    </nav>
  );
}

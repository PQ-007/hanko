"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { LayoutDashboard, Layers } from "lucide-react";
import { T } from "../_lib/strings";

const LINKS = [
  { href: "/decks/stats", label: T.dashboardNav, icon: LayoutDashboard },
  { href: "/decks", label: T.decksNav, icon: Layers },
];

export default function HeaderNav() {
  const pathname = usePathname();

  return (
    <nav className="flex items-center gap-1">
      {LINKS.map(({ href, label, icon: Icon }) => {
        const active = pathname === href;
        return (
          <Link
            key={href}
            href={href}
            className={`flex items-center gap-1.5 rounded px-2.5 py-1.5 text-sm font-medium transition ${
              active ? "bg-gray-900 text-white" : "text-gray-600 hover:bg-gray-100"
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

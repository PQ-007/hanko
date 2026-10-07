"use client";

import { usePathname } from "next/navigation";
import { T } from "../_lib/strings";

// The phone/tablet header names the screen you're on, like an app's top bar.
const TITLES: [string, string][] = [
  ["/decks/stats", T.homeTab],
  ["/decks/review/duel", T.duelTab],
  ["/decks/review", T.practiceNav],
  ["/decks/friends", T.friendsNav],
  ["/decks/writing", T.writingTitle],
  ["/decks/practice", T.practiceNav],
  ["/decks/settings", T.settingsTitle],
  ["/decks", T.decksNav],
];

export default function PageTitle() {
  const pathname = usePathname();
  const title = TITLES.find(([p]) => pathname === p || pathname.startsWith(p + "/"))?.[1] ?? "Hanko";
  return <span className="truncate text-lg font-bold tracking-tight lg:hidden">{title}</span>;
}

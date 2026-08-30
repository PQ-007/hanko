"use client";

import { Suspense } from "react";
import BattleArena from "./_components/BattleArena";

export default function BattlePage() {
  return (
    <Suspense>
      <BattleArena />
    </Suspense>
  );
}

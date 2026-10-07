"use client";

import FightScene from "./FightScene";

// The app's loading state: a fight, not a spinner. All the behaviour lives in
// FightScene, which the practice landing page's Monster Hunt card also uses —
// this only fixes the sizing and hangs the caption underneath.
export default function LoadingScene({ label }: { label: string }) {
  return (
    // Centred in the visible screen (below the header), not parked at the top.
    <div className="flex min-h-[calc(100dvh-9rem)] w-full items-center justify-center px-4 py-10 [&_p]:text-base">
      <FightScene slotClass="hanko-loading-slot" label={label} />
    </div>
  );
}

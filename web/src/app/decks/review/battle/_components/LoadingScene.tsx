"use client";

import FightScene from "./FightScene";

// The app's loading state: a fight, not a spinner. All the behaviour lives in
// FightScene, which the practice landing page's Monster Hunt card also uses —
// this only fixes the sizing and hangs the caption underneath.
export default function LoadingScene({ label }: { label: string }) {
  return (
    <div className="py-10">
      <FightScene slotClass="hanko-loading-slot" label={label} />
    </div>
  );
}

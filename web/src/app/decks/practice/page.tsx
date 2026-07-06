"use client";

import { Suspense } from "react";
import PracticeSession from "./_components/PracticeSession";

export default function PracticePage() {
  return (
    <Suspense>
      <PracticeSession />
    </Suspense>
  );
}

"use client";

import { Suspense } from "react";
import AudioDecks from "./AudioDecks";

export default function AudioPage() {
  return (
    <Suspense>
      <AudioDecks />
    </Suspense>
  );
}

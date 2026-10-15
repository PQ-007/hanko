"use client";

import { Suspense } from "react";
import LeechList from "./LeechList";

export default function LeechesPage() {
  return (
    <Suspense>
      <LeechList />
    </Suspense>
  );
}

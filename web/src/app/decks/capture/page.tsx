"use client";

import { Suspense } from "react";
import CaptureFlow from "./CaptureFlow";

export default function CapturePage() {
  return (
    <Suspense>
      <CaptureFlow />
    </Suspense>
  );
}

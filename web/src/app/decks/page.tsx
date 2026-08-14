import { Suspense } from "react";
import DeckDashboard from "./DeckDashboard";

export default function DecksPage() {
  return (
    <Suspense>
      <DeckDashboard />
    </Suspense>
  );
}

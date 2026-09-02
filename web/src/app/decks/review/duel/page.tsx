import { Suspense } from "react";
import DuelLobby from "./_components/DuelLobby";

export default function DuelPage() {
  return (
    <Suspense>
      <DuelLobby />
    </Suspense>
  );
}

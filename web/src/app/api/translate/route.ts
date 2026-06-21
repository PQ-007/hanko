import { NextResponse } from "next/server";
import { translateToMongolian } from "@/lib/translate";

export const runtime = "nodejs";

// GET /api/translate?text=... -> { mongolian }
// English -> Mongolian via bolor-toli (server-side; key stays secret).
// Public endpoint (translation isn't user-specific) so the extension can call
// it too without auth.
export async function GET(request: Request) {
  const text = new URL(request.url).searchParams.get("text")?.trim();
  if (!text) {
    return NextResponse.json({ error: "Missing text" }, { status: 400 });
  }
  try {
    const mongolian = await translateToMongolian(text);
    return NextResponse.json({ mongolian });
  } catch (e) {
    return NextResponse.json(
      { mongolian: "", error: e instanceof Error ? e.message : "translate failed" },
      { status: 200 }
    );
  }
}

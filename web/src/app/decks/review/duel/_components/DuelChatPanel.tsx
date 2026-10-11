"use client";

import { useEffect, useRef, useState } from "react";
import { T } from "../../../_lib/strings";
import { EMOTES, MAX_TEXT, PHRASES } from "../_lib/chat";
import type { DuelChat } from "../_lib/useDuelChat";

/**
 * The chat under the fighters: a short log, a row of emotes, preset phrases,
 * and a text box — the text box only for a friend (chat.ts says why it is
 * the receiver that enforces that, not this).
 */
export default function DuelChatPanel({ chat, foeName }: { chat: DuelChat; foeName: string }) {
  const [draft, setDraft] = useState("");
  const log = useRef<HTMLDivElement>(null);

  // Newest at the bottom, kept in view — scrolling the log, not the page.
  useEffect(() => {
    const el = log.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [chat.entries.length]);

  function submit() {
    if (chat.send("text", draft)) setDraft("");
  }

  return (
    <div className="flex flex-col gap-2 rounded-card bg-white/5 p-3 ring-1 ring-white/10">
      <div ref={log} className="flex max-h-28 min-h-14 flex-col gap-1 overflow-y-auto pr-1 text-sm">
        {chat.entries.length === 0 ? (
          <p className="m-auto text-center text-xs text-paper/40">{T.duelChatEmpty}</p>
        ) : (
          chat.entries.map((e) => (
            <p key={e.key} className={`max-w-[85%] break-words ${e.mine ? "self-end text-right" : "self-start"}`}>
              <span className={`text-[11px] font-semibold ${e.mine ? "text-sky-300" : "text-rose-300"}`}>
                {e.mine ? T.duelYou : foeName}
              </span>{" "}
              <span className={`text-paper/90 ${e.kind === "emote" ? "text-lg" : ""}`}>{e.text}</span>
            </p>
          ))
        )}
      </div>

      <div className="flex flex-wrap justify-center gap-1.5">
        {EMOTES.map((e) => (
          <button
            key={e.id}
            type="button"
            onClick={() => chat.send("emote", e.id)}
            className="flex h-10 w-10 items-center justify-center rounded-full bg-white/10 text-xl transition hover:-translate-y-0.5 hover:bg-white/20 active:scale-95"
            aria-label={e.id}
          >
            {e.icon}
          </button>
        ))}
      </div>

      <div className="-mx-3 flex gap-1.5 overflow-x-auto px-3 pb-0.5 [scrollbar-width:none]">
        {PHRASES.map((p) => (
          <button
            key={p.id}
            type="button"
            onClick={() => chat.send("phrase", p.id)}
            className="shrink-0 rounded-full border border-white/15 bg-white/5 px-3 py-1.5 text-xs font-medium text-paper/85 transition hover:bg-white/15"
          >
            {p.text}
          </button>
        ))}
      </div>

      {chat.canType ? (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            submit();
          }}
          className="flex gap-2"
        >
          <input
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            maxLength={MAX_TEXT}
            placeholder={T.duelChatPlaceholder}
            aria-label={T.duelChatPlaceholder}
            className="min-w-0 flex-1 rounded-control border border-white/15 bg-black/20 px-3 py-2 text-sm text-paper placeholder:text-paper/35 focus:border-white/40 focus:outline-none"
          />
          <button
            type="submit"
            disabled={!draft.trim()}
            className="hk-btn hk-btn-primary px-4 py-2 text-sm disabled:!bg-seal disabled:opacity-40"
          >
            {T.duelChatSend}
          </button>
        </form>
      ) : (
        <p className="text-center text-[11px] text-paper/40">{T.duelChatStrangers}</p>
      )}
    </div>
  );
}

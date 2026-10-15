import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { audioFrames, firstFrame, Mp3Frame, mp3DurationMs, silence, concat } from "../../../lib/mp3.ts";
import { assemble, buildAudioDeck, cueAt, DEFAULT_OPTIONS, planParts, speakable, type AudioOptions } from "./audioDeck.ts";

// The same recorded clips and the same cases as mobile's mp3_test.dart and
// audio_deck_test.dart: 食べる (ja) and "to eat" (en), from Google's voice.
const fixtures = join(import.meta.dirname, "../../../../../mobile/test/fixtures");
const ja = new Uint8Array(readFileSync(join(fixtures, "tts_ja.mp3")));
const en = new Uint8Array(readFileSync(join(fixtures, "tts_en.mp3")));
const close = (a: number, b: number, tol: number, msg?: string) => assert.ok(Math.abs(a - b) <= tol, msg ?? `${a} ≉ ${b} ± ${tol}`);
const opts = (o: Partial<AudioOptions> = {}): AudioOptions => ({ ...DEFAULT_OPTIONS, ...o });

// ---- mp3 ---------------------------------------------------------------------

test("Google's clips: MPEG-2 Layer III, 24 kHz mono, 192-byte frames of 24 ms", () => {
  const f = firstFrame(ja)!;
  assert.equal(f.sampleRate, 24000);
  assert.equal(f.samples, 576);
  assert.equal(f.ms, 24);
  assert.ok(f.size === 192 || f.size === 193);
  assert.ok(f.sameFormat(firstFrame(en)!), "Japanese and English can share one file");
});

test("every byte of a clip is whole frames, so its length is exact", () => {
  assert.equal(audioFrames(ja).length, ja.length);
  const ms = mp3DurationMs(ja);
  assert.ok(ms > 500);
  assert.equal(ms % 24, 0, "a whole number of 24 ms frames");
});

test("an ID3v2 tag in front is stripped", () => {
  const tag = new Uint8Array([0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, 5, 1, 2, 3, 4, 5]);
  assert.deepEqual(audioFrames(concat([tag, ja])), ja);
});

test("trailing junk (an ID3v1 tag) is dropped", () => {
  const tag = new Uint8Array(128);
  tag.set([0x54, 0x41, 0x47]);
  assert.deepEqual(audioFrames(concat([ja, tag])), ja);
});

test("silence is valid frames in the same format, close to the asked length", () => {
  const s = silence(firstFrame(ja)!, 1000);
  close(mp3DurationMs(s), 1000, 24);
  assert.ok(Mp3Frame.at(s, 0)!.sameFormat(firstFrame(ja)!));
});

test("clips and silence join into one stream whose length adds up", () => {
  const joined = concat([audioFrames(ja), silence(firstFrame(ja)!, 500), audioFrames(en)]);
  close(mp3DurationMs(joined), mp3DurationMs(ja) + 500 + mp3DurationMs(en), 24);
});

// ---- audio deck -----------------------------------------------------------------

const words = [
  { term: "食べる", reading: "たべる", meaning: "to eat", meaning_mn: "идэх" },
  { term: "ありがとう", meaning: "thank you" },
];
const sheep = { ja: "私は羊の群を見た。", en: "I saw a flock of sheep." };
const ids = (parts: ReturnType<typeof planParts>) => parts.map((p) => `${p.wordIndex}:${p.lang}:${p.text}`);

test("each word: its reading (else the term), then English, repeated", () => {
  assert.deepEqual(ids(planParts(words, opts({ repeat: 2 }))), [
    "0:ja:たべる", "0:en:to eat", "0:ja:たべる", "0:en:to eat",
    "1:ja:ありがとう", "1:en:thank you", "1:ja:ありがとう", "1:en:thank you",
  ]);
  assert.deepEqual(planParts(words, opts({ english: false })).map((p) => p.lang), ["ja", "ja"]);
});

test("assembled: clips with pauses, each word cued where it starts", () => {
  const o = opts({ pauseMs: 1000 });
  const parts = planParts(words, o);
  const r = assemble(parts, parts.map((p) => (p.lang === "ja" ? ja : en)), o);
  const perWord = mp3DurationMs(ja) + mp3DurationMs(en) + 2 * 1000;
  assert.deepEqual(r.kept, [0, 1]);
  assert.equal(r.starts[0], 0);
  close(r.starts[1], perWord, 50);
  close(mp3DurationMs(r.mp3), 2 * perWord, 100);
});

test("a word whose Japanese couldn't be fetched is left out whole", () => {
  const o = opts();
  const r = assemble(planParts(words, o), [null, en, ja, en], o);
  assert.deepEqual(r.kept, [1], "no meaning without its word");
  assert.deepEqual(r.starts, [0]);
});

test("a missing English clip only drops the meaning", () => {
  const o = opts();
  assert.deepEqual(assemble(planParts(words, o), [ja, null, ja, en], o).kept, [0, 1]);
});

test("the cue playing at a moment", () => {
  const cues = [{ startMs: 0, term: "a" }, { startMs: 3000, term: "b" }, { startMs: 6000, term: "c" }];
  assert.equal(cueAt(cues, 0), 0);
  assert.equal(cueAt(cues, 2999), 0);
  assert.equal(cueAt(cues, 3000), 1);
  assert.equal(cueAt(cues, 8000), 2);
});

test("example sentences: spoken once after the repeats, translation only with English on", () => {
  assert.deepEqual(ids(planParts(words, opts({ repeat: 2, sentences: true }), [sheep, null])), [
    "0:ja:たべる", "0:en:to eat", "0:ja:たべる", "0:en:to eat",
    "0:ja:私は羊の群を見た。", "0:en:I saw a flock of sheep.",
    "1:ja:ありがとう", "1:en:thank you", "1:ja:ありがとう", "1:en:thank you",
  ]);
  assert.deepEqual(
    planParts(words, opts({ english: false, sentences: true }), [sheep, null]).map((p) => p.text),
    ["たべる", "私は羊の群を見た。", "ありがとう"]
  );
  assert.equal(planParts(words, opts(), [sheep, null]).length, 4, "switched off, examples are ignored");
});

test("a missing sentence drops the sentence and its translation, never the word", () => {
  const o = opts({ sentences: true });
  const r = assemble(planParts(words, o, [sheep, null]), [ja, en, null, en, ja, en], o);
  assert.deepEqual(r.kept, [0, 1]);
  const perWord = mp3DurationMs(ja) + mp3DurationMs(en) + 2 * o.pauseMs;
  close(mp3DurationMs(r.mp3), 2 * perWord, 100, "no orphaned translation");
});

test("build: each text fetched once, cues in order; a saved sentence wins over a looked-up one", async () => {
  const asked: string[] = [];
  const looked: string[] = [];
  const deck = await buildAudioDeck(
    { id: "d1", name: "N1" },
    [{ ...words[0], example_ja: "りんごを食べる。", example_en: "I eat an apple." }, words[1]],
    opts({ repeat: 3, sentences: true }),
    {
      clip: async (t, lang) => (asked.push(`${lang}:${t}`), lang === "ja" ? ja : en),
      findExample: async (t) => (looked.push(t), null),
    }
  );
  assert.equal(asked.length, 6, "2 words × (ja + en) + 1 sentence × (ja + en); repeats reuse the clip");
  assert.deepEqual(looked, ["ありがとう"], "the word with a saved sentence isn't looked up");
  assert.deepEqual(deck!.cues.map((c) => c.term), ["食べる", "ありがとう"]);
  assert.equal(deck!.cues[0].sentence, "りんごを食べる。");
  assert.equal(deck!.cues[1].sentence, null);
  assert.equal(deck!.skipped, 0);
});

test("build: nothing fetched at all is no deck", async () => {
  assert.equal(await buildAudioDeck({ id: "d", name: "n" }, words, opts(), { clip: async () => null }), null);
});

test("speakable: whitespace collapsed, long text cut at a break that fits", () => {
  assert.equal(speakable("  to   eat \n"), "to eat");
  const long = `${"a".repeat(150)}; ${"b".repeat(60)}`;
  assert.equal(speakable(long), "a".repeat(150));
});

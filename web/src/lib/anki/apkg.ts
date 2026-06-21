import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import initSqlJs from "sql.js";
import JSZip from "jszip";

const nodeRequire = createRequire(import.meta.url);

// Builds a real Anki .apkg package (a zip of a SQLite "collection.anki2" plus
// media files), equivalent to what the genanki library produces. We implement
// it directly so there's no reliance on an unmaintained wrapper, and so we can
// embed per-word audio as media.
//
// The Anki schema and the JSON blobs below follow Anki's schema version 11,
// matching genanki's known-good defaults.

const FIELD_SEP = "\x1f"; // Anki separates note fields with the unit separator.

// Stable model (note type) shared across all exports so re-imports merge into a
// single "Basic-vocabdecks" note type rather than piling up duplicates.
const MODEL_ID = 1718000000001;

export interface ApkgNote {
  // A stable per-note id (we derive it from the word's UUID) so re-importing an
  // updated deck updates existing cards instead of duplicating them.
  guidSeed: string;
  front: string;
  back: string;
  tags?: string[];
  // Optional audio: raw bytes + a filename. We append [sound:<filename>] to the
  // back field and add the bytes to the package media.
  audio?: { filename: string; bytes: Uint8Array };
}

let sqlPromise: ReturnType<typeof initSqlJs> | null = null;
function getSql() {
  if (!sqlPromise) {
    // sql.js ships its wasm next to its JS entry in node_modules; resolve the
    // package dir and read the bytes directly. We avoid resolving the .wasm path
    // statically so the bundler doesn't try to process it as a module. This
    // works in dev and when bundled for serverless (see outputFileTracingIncludes
    // in next.config.ts).
    const sqlJsDir = dirname(nodeRequire.resolve("sql.js"));
    const wasmBinary = readFileSync(join(sqlJsDir, "sql-wasm.wasm"));
    sqlPromise = initSqlJs({ wasmBinary });
  }
  return sqlPromise;
}

function guid(seed: string): string {
  // Short, URL-safe, deterministic guid derived from the seed.
  return createHash("sha1").update(seed).digest("base64url").slice(0, 10);
}

function fieldChecksum(firstField: string): number {
  // Anki's csum: first 8 hex digits of the SHA1 of the first field, as an int.
  const hex = createHash("sha1").update(stripHtml(firstField)).digest("hex");
  return parseInt(hex.slice(0, 8), 16);
}

function stripHtml(s: string): string {
  return s.replace(/<[^>]+>/g, "");
}

export async function buildApkg(
  deckName: string,
  notes: ApkgNote[]
): Promise<Uint8Array> {
  const SQL = await getSql();
  const db = new SQL.Database();
  const now = Date.now();
  const nowSec = Math.floor(now / 1000);
  const deckId = now; // unique per export; Anki dedupes decks by name on import.

  const models = {
    [MODEL_ID]: {
      id: MODEL_ID,
      name: "Basic-vocabdecks",
      type: 0,
      mod: nowSec,
      usn: -1,
      sortf: 0,
      did: deckId,
      tmpls: [
        {
          name: "Card 1",
          ord: 0,
          qfmt: "{{Front}}",
          afmt: '{{FrontSide}}\n\n<hr id="answer">\n\n{{Back}}',
          bqfmt: "",
          bafmt: "",
          did: null,
          bfont: "",
          bsize: 0,
        },
      ],
      flds: [
        { name: "Front", ord: 0, sticky: false, rtl: false, font: "Arial", size: 20, media: [] },
        { name: "Back", ord: 1, sticky: false, rtl: false, font: "Arial", size: 20, media: [] },
      ],
      css:
        ".card {\n font-family: arial;\n font-size: 20px;\n text-align: center;\n color: black;\n background-color: white;\n}\n",
      latexPre:
        "\\documentclass[12pt]{article}\n\\special{papersize=3in,5in}\n\\usepackage[utf8]{inputenc}\n\\usepackage{amssymb,amsmath}\n\\pagestyle{empty}\n\\setlength{\\parindent}{0in}\n\\begin{document}\n",
      latexPost: "\\end{document}",
      req: [[0, "any", [0]]],
      vers: [],
    },
  };

  const decks = {
    1: {
      id: 1,
      name: "Default",
      mod: nowSec,
      usn: -1,
      lrnToday: [0, 0],
      revToday: [0, 0],
      newToday: [0, 0],
      timeToday: [0, 0],
      collapsed: false,
      browserCollapsed: false,
      desc: "",
      dyn: 0,
      conf: 1,
      extendNew: 10,
      extendRev: 50,
    },
    [deckId]: {
      id: deckId,
      name: deckName,
      mod: nowSec,
      usn: -1,
      lrnToday: [0, 0],
      revToday: [0, 0],
      newToday: [0, 0],
      timeToday: [0, 0],
      collapsed: false,
      browserCollapsed: false,
      desc: "",
      dyn: 0,
      conf: 1,
      extendNew: 10,
      extendRev: 50,
    },
  };

  const dconf = {
    1: {
      id: 1,
      mod: 0,
      name: "Default",
      usn: 0,
      maxTaken: 60,
      autoplay: true,
      timer: 0,
      replayq: true,
      new: { bury: false, delays: [1, 10], initialFactor: 2500, ints: [1, 4, 0], order: 1, perDay: 20, separate: true },
      rev: { bury: false, ease4: 1.3, fuzz: 0.05, ivlFct: 1, maxIvl: 36500, minSpace: 1, perDay: 100, hardFactor: 1.2 },
      lapse: { delays: [10], leechAction: 1, leechFails: 8, minInt: 1, mult: 0 },
      dyn: false,
    },
  };

  const conf = {
    nextPos: 1,
    estTimes: true,
    activeDecks: [1],
    sortType: "noteFld",
    timeLim: 0,
    sortBackwards: false,
    addToCur: true,
    curDeck: 1,
    newBury: true,
    newSpread: 0,
    dueCounts: true,
    curModel: MODEL_ID,
    collapseTime: 1200,
  };

  db.run(SCHEMA_SQL);

  db.run(
    `INSERT INTO col (id, crt, mod, scm, ver, dty, usn, ls, conf, models, decks, dconf, tags)
     VALUES (1, ?, ?, ?, 11, 0, 0, 0, ?, ?, ?, ?, '{}')`,
    [
      nowSec,
      now,
      now,
      JSON.stringify(conf),
      JSON.stringify(models),
      JSON.stringify(decks),
      JSON.stringify(dconf),
    ]
  );

  const media: Record<string, string> = {};
  const mediaFiles: { key: string; bytes: Uint8Array }[] = [];

  notes.forEach((note, i) => {
    const noteId = now + i * 2; // keep note/card ids unique & increasing
    const cardId = noteId + 1;
    let back = note.back;

    if (note.audio) {
      const key = String(mediaFiles.length);
      media[key] = note.audio.filename;
      mediaFiles.push({ key, bytes: note.audio.bytes });
      back = `${back}<br>[sound:${note.audio.filename}]`;
    }

    const flds = [note.front, back].join(FIELD_SEP);
    const tags = note.tags?.length ? ` ${note.tags.join(" ")} ` : "";

    db.run(
      `INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, flags, data)
       VALUES (?, ?, ?, ?, -1, ?, ?, ?, ?, 0, '')`,
      [
        noteId,
        guid(note.guidSeed),
        MODEL_ID,
        nowSec,
        tags,
        flds,
        stripHtml(note.front),
        fieldChecksum(note.front),
      ]
    );

    // A fresh "new" card in the target deck.
    db.run(
      `INSERT INTO cards (id, nid, did, ord, mod, usn, type, queue, due, ivl,
        factor, reps, lapses, left, odue, odid, flags, data)
       VALUES (?, ?, ?, 0, ?, -1, 0, 0, ?, 0, 0, 0, 0, 0, 0, 0, 0, '')`,
      [cardId, noteId, deckId, nowSec, i + 1]
    );
  });

  const dbBytes = db.export();
  db.close();

  const zip = new JSZip();
  zip.file("collection.anki2", dbBytes);
  zip.file("media", JSON.stringify(media));
  for (const m of mediaFiles) zip.file(m.key, m.bytes);

  return zip.generateAsync({ type: "uint8array" });
}

const SCHEMA_SQL = `
CREATE TABLE col (
  id integer primary key, crt integer not null, mod integer not null,
  scm integer not null, ver integer not null, dty integer not null,
  usn integer not null, ls integer not null, conf text not null,
  models text not null, decks text not null, dconf text not null, tags text not null
);
CREATE TABLE notes (
  id integer primary key, guid text not null, mid integer not null,
  mod integer not null, usn integer not null, tags text not null,
  flds text not null, sfld integer not null, csum integer not null,
  flags integer not null, data text not null
);
CREATE TABLE cards (
  id integer primary key, nid integer not null, did integer not null,
  ord integer not null, mod integer not null, usn integer not null,
  type integer not null, queue integer not null, due integer not null,
  ivl integer not null, factor integer not null, reps integer not null,
  lapses integer not null, left integer not null, odue integer not null,
  odid integer not null, flags integer not null, data text not null
);
CREATE TABLE revlog (
  id integer primary key, cid integer not null, usn integer not null,
  ease integer not null, ivl integer not null, lastIvl integer not null,
  factor integer not null, time integer not null, type integer not null
);
CREATE TABLE graves (usn integer not null, oid integer not null, type integer not null);
CREATE INDEX ix_notes_usn on notes (usn);
CREATE INDEX ix_cards_usn on cards (usn);
CREATE INDEX ix_revlog_usn on revlog (usn);
CREATE INDEX ix_cards_nid on cards (nid);
CREATE INDEX ix_cards_sched on cards (did, queue, due);
CREATE INDEX ix_revlog_cid on revlog (cid);
CREATE INDEX ix_notes_csum on notes (csum);
`;

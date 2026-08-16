// Regression tests for the sync cursors. No dependencies, no runner:
//
//   node src/sync.test.js            # tests src/sync.js
//   node src/sync.test.js path.js    # tests another copy (chrome/, firefox/)
//
// What these exist to catch: the pull cursor used to be written from the
// *device* clock and compared against server-generated updated_at. A device
// running ahead of Postgres wrote a cursor in the future, and every row
// committed inside that window was filtered out of all later pulls — silent,
// permanent data loss that no amount of manual clicking around reveals,
// because both clients look fine in isolation.
//
// The harness fakes extension storage and the Supabase REST endpoint, and
// keeps the server clock and the device clock separately controllable.
const path = require("path");

// The two clocks the tests play against. Everything in the harness reads these
// rather than the real wall clock.
let SERVER_NOW = Date.parse("2026-08-16T12:00:00Z");
let DEVICE_SKEW = 0;                       // device clock minus server clock
const realNow = Date.now;
Date.now = () => SERVER_NOW + DEVICE_SKEW;

const store = {};
global.chrome = {
  storage: { local: {
    get: async (keys) => Object.fromEntries(
      (Array.isArray(keys) ? keys : [keys]).map((k) => [k, store[k]]).filter(([, v]) => v !== undefined)),
    set: async (obj) => Object.assign(store, obj),
    remove: async (keys) => (Array.isArray(keys) ? keys : [keys]).forEach((k) => delete store[k]),
  } },
  tabs: { create: () => {} },
};

const serverRows = { decks: [], words: [] };
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
const token = `x.${b64({ exp: Math.floor(SERVER_NOW / 1000) + 99999, sub: "user-1" })}.y`;
store.session = { access_token: token, refresh_token: "r" };

const pulls = [];
global.fetch = async (url, opts = {}) => {
  const u = new URL(url);
  const table = u.pathname.split("/").pop();
  const respond = (body) => ({
    ok: true, status: 200,
    text: async () => JSON.stringify(body),
    headers: { get: (h) => (h.toLowerCase() === "date" ? new Date(SERVER_NOW).toUTCString() : null) },
  });
  if ((opts.method ?? "GET") === "GET") {
    const gte = u.searchParams.get("updated_at");
    if (!gte) return respond([]);                       // serverNow probe
    const since = Date.parse(gte.replace("gte.", ""));
    pulls.push({ table, since });
    return respond(serverRows[table].filter((r) => Date.parse(r.updated_at) >= since));
  }
  JSON.parse(opts.body).forEach((row) => {              // upsert
    const at = serverRows[table].findIndex((r) => r.id === row.id);
    const stamped = { ...row, updated_at: new Date(SERVER_NOW).toISOString() };
    if (at === -1) serverRows[table].push(stamped); else serverRows[table][at] = stamped;
  });
  return respond(null);
};

global.VOCAB_CONFIG = {
  SUPABASE_URL: "https://fake.supabase.co",
  SUPABASE_PUBLISHABLE_KEY: "k",
  SITE_URL: "https://example.test",
};
require(path.resolve(process.argv[2] ?? path.join(__dirname, "sync.js")));

(async () => {
  const results = [];
  const check = (name, pass, detail) => results.push({ name, pass, detail });

  // The device clock runs one minute AHEAD of the server — the exact condition
  // that used to lose rows permanently.
  DEVICE_SKEW = 60_000;

  await VocabSync.fullSync();                       // first sync, empty world

  // Another device (the web app) writes a word 10s later, in SERVER time.
  SERVER_NOW += 10_000;
  serverRows.words.push({ id: "w-remote", deck_id: "d", term: "犬",
    updated_at: new Date(SERVER_NOW).toISOString(), date_added: new Date(SERVER_NOW).toISOString() });

  SERVER_NOW += 5_000;
  await VocabSync.fullSync();                       // second sync

  const got = (await chrome.storage.local.get(["words"])).words ?? [];
  check("remote word survives a device clock 60s ahead of the server",
    got.some((w) => w.id === "w-remote"),
    `pulled from ${new Date(pulls.at(-1).since).toISOString()}, row at ${new Date(SERVER_NOW - 5000).toISOString()}`);

  check("pull cursor is in server time, not device time",
    pulls.at(-1).since <= SERVER_NOW && pulls.at(-1).since < Date.now() - 30_000,
    `cursor ${new Date(pulls.at(-1).since).toISOString()} vs device ${new Date(Date.now()).toISOString()}`);

  // A local edit stamped with the (skewed) device clock must still push.
  const local = (await chrome.storage.local.get(["words"])).words ?? [];
  local.push({ id: "w-local", deckId: "d", term: "猫", dateAdded: Date.now(), updatedAt: Date.now() });
  await chrome.storage.local.set({ words: local });
  SERVER_NOW += 1000;
  await VocabSync.fullSync();
  check("local edit stamped with the skewed device clock still pushes",
    serverRows.words.some((w) => w.id === "w-local"));

  // And the reverse skew: device an hour BEHIND the server.
  DEVICE_SKEW = -3_600_000;
  SERVER_NOW += 1000;
  serverRows.words.push({ id: "w-remote2", deck_id: "d", term: "鳥",
    updated_at: new Date(SERVER_NOW).toISOString(), date_added: new Date(SERVER_NOW).toISOString() });
  SERVER_NOW += 1000;
  await VocabSync.fullSync();
  const got2 = (await chrome.storage.local.get(["words"])).words ?? [];
  check("remote word survives a device clock 1h behind the server",
    got2.some((w) => w.id === "w-remote2"));

  results.forEach((r) => console.log(`${r.pass ? "PASS" : "FAIL"}  ${r.name}${r.detail ? `\n        ${r.detail}` : ""}`));
  Date.now = realNow;
  process.exit(results.every((r) => r.pass) ? 0 : 1);
})();

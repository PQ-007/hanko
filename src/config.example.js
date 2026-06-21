// Copy to config.js (in each of chrome/ and firefox/) and fill in. These are
// the same public values the website uses — the anon key is safe to ship
// because Supabase Row Level Security protects every row.
globalThis.VOCAB_CONFIG = {
  SUPABASE_URL: "https://YOUR-PROJECT.supabase.co",
  SUPABASE_ANON_KEY: "YOUR-ANON-KEY",
  // Where the website is hosted (used for the sign-in / connect page).
  SITE_URL: "http://localhost:3000",
};

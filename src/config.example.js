// Copy to config.js (in each of chrome/ and firefox/) and fill in. These are
// the same public values the website uses — the publishable key is safe to ship
// because Supabase Row Level Security protects every row.
globalThis.VOCAB_CONFIG = {
  SUPABASE_URL: "https://YOUR-PROJECT.supabase.co",
  // New projects: publishable key (sb_publishable_...). Legacy projects can use
  // SUPABASE_ANON_KEY instead — either works.
  SUPABASE_PUBLISHABLE_KEY: "sb_publishable_YOUR-KEY",
  // Where the website is hosted (used for the sign-in / connect page).
  SITE_URL: "http://localhost:3000",
};

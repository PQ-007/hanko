// Roster split, from the actual character names in the two purchased packs
// (see CLAUDE.md's Phase 0 notes and sprites.ts). 9 hero-coded characters
// from Pack 01 are player-usable; everything else — the rest of Pack 01 plus
// all of Pack 02 — is monster-coded (33 characters).

export const PLAYER_ROSTER = [
  "archer",
  "armored-axeman",
  "knight",
  "knight-templar",
  "lancer",
  "priest",
  "soldier",
  "swordsman",
  "wizard",
  // The three Black Knights, added as playable. They stay in MONSTER_ROSTER
  // too — a character being available on both sides costs nothing and means
  // you can end up facing your own armour, which is a better encounter than
  // removing three monsters from the pool to gain three heroes. pickMonster()
  // refuses to draw the character you're currently playing, so the mirror is
  // never literally identical sprites on both sides.
  //
  // All three carry the full pose set including three attacks, so they climb
  // the whole streak ladder; black-knight-b also has the cannonball, which
  // makes it the first melee-looking hero that fires something.
  "black-knight-a",
  "black-knight-b",
  "black-knight-c",
] as const;

// The player is a fixed character for v1 — Knight, the plainest melee
// fighter, no character-select screen yet. Easy fast-follow: swap this for a
// picker over PLAYER_ROSTER once that's wanted.
export const PLAYER_CHARACTER = "knight";

export const MONSTER_ROSTER = [
  "armored-orc",
  "armored-skeleton",
  "bat",
  "black-knight-a",
  "black-knight-b",
  "black-knight-c",
  "blood-monster-a",
  "blood-monster-b",
  "demon-a",
  "demon-b",
  "demon-c",
  "demon-d",
  "demon-e",
  "demoness-a",
  "demoness-b",
  "elite-orc",
  "eyeball-monster",
  "flame-golem",
  "ghostfire",
  "greatsword-skeleton",
  "hellbat",
  "hellhound",
  "lava-slime",
  "minotaur",
  "necromancer",
  "orc",
  "orc-rider",
  "skeleton",
  "skeleton-archer",
  "slime",
  "warlock",
  "werebear",
  "werewolf",
] as const;

// Picked lazily, once per fight (`useState(() => pickMonster())`) — never
// call this directly inside a render, or the monster re-rolls on every
// unrelated re-render.
//
// A shuffle bag, not an independent draw per spawn. Independent draws are
// "random" in a way that doesn't feel random: with 33 monsters, after ten
// kills there is still a 27% chance of never having met any of the four orcs,
// while some other monster has turned up three times. Dealing from a shuffled
// deck and reshuffling only when it runs out means every monster in the roster
// appears once before any appears twice — all 33 show up inside 33 fights,
// guaranteed, and nothing repeats back to back.
let bag: string[] = [];
let lastPicked: string | null = null;

function refill() {
  bag = [...MONSTER_ROSTER];
  // Fisher-Yates. Same reason as quiz.ts: `.sort(() => Math.random() - 0.5)`
  // is not a shuffle, and this one is drawn from often enough to notice.
  for (let i = bag.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [bag[i], bag[j]] = [bag[j], bag[i]];
  }
  // Cards are taken off the end, so bag[last] is the next one out. If the
  // fresh deck would open with the monster the old one closed on, swap it
  // deeper — otherwise a reshuffle is the one place a repeat can still happen.
  if (bag.length > 1 && bag[bag.length - 1] === lastPicked) {
    [bag[bag.length - 1], bag[0]] = [bag[0], bag[bag.length - 1]];
  }
}

// `exclude` is the character the player is currently using. Three of the
// roster are now playable as well as spawnable, and two identical sprites
// facing each other reads as a rendering fault rather than a mirror match.
// The skipped card stays in the deck, so excluding one doesn't cost it its
// turn in the cycle.
export function pickMonster(exclude?: string): string {
  if (bag.length === 0) refill();
  let i = bag.length - 1;
  if (exclude) {
    // At most one copy of each slug per deal, so this steps back once.
    while (i >= 0 && bag[i] === exclude) i--;
    if (i < 0) {
      refill();
      i = bag.length - 1;
      while (i >= 0 && bag[i] === exclude) i--;
    }
    // Only reachable if the roster holds nothing but the excluded character.
    if (i < 0) i = bag.length - 1;
  }
  const [next] = bag.splice(i, 1);
  lastPicked = next;
  return next;
}

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  BOT_DIFFICULTIES,
  BOT_PROFILES,
  botAnswer,
  botBaselineMs,
  isBotDifficulty,
  type BotProfile,
} from "./bot.ts";
import {
  DUEL_ROUND_COUNT,
  deriveDuelState,
  duelOutcome,
  resolveRound,
  roundDurationMs,
  type ResolvedRound,
} from "./duel.ts";

// A scripted generator, so every assertion below is about the bot's rules
// rather than about luck. Same approach damage.test.ts uses for crit/evade.
function scripted(...values: number[]): () => number {
  let i = 0;
  return () => values[i++ % values.length];
}

const profile: BotProfile = { accuracy: 0.8, meanReactionMs: 3000, reactionJitterMs: 1000 };

test("the first draw is reaction and the second is correctness", () => {
  // The draw order is part of the contract — every other test here scripts
  // against it, and swapping the two would silently invert all of them.
  // rng()=0.5 -> zero jitter -> exactly the mean; rng()=0.0 -> correct.
  const answer = botAnswer(profile, scripted(0.5, 0.0), 10_000);
  assert.deepEqual(answer, { correct: true, elapsedMs: 3000 });
});

test("jitter spans the full declared range and no further", () => {
  const fastest = botAnswer(profile, scripted(0, 0), 10_000);
  const slowest = botAnswer(profile, scripted(1, 0), 10_000);
  assert.equal(fastest?.elapsedMs, 2000); // mean - jitter
  assert.equal(slowest?.elapsedMs, 4000); // mean + jitter
});

test("correctness follows the profile's accuracy threshold", () => {
  assert.equal(botAnswer(profile, scripted(0.5, 0.79), 10_000)?.correct, true);
  assert.equal(botAnswer(profile, scripted(0.5, 0.81), 10_000)?.correct, false);
});

test("the bot times out when its reaction runs past the round", () => {
  // The property that makes difficulty mean anything: a bot that always
  // answers inside the timer is not a setting, it is a different game.
  assert.equal(botAnswer(profile, scripted(1, 0), 3500), null);
});

test("a reaction landing exactly on the buzzer counts as a timeout", () => {
  // Same boundary the human clock uses — at t=duration the question is over.
  assert.equal(botAnswer(profile, scripted(1, 0), 4000), null);
  assert.notEqual(botAnswer(profile, scripted(1, 0), 4001), null);
});

test("the hardest bot still misses rounds at the tightest timer", () => {
  // A 3s round against master's 1.7s±0.7s must not be a guaranteed answer,
  // or the last third of a match becomes unwinnable by construction.
  const master = BOT_PROFILES.master;
  const worst = botAnswer(master, scripted(1, 0), roundDurationMs(12));
  assert.ok(
    worst === null || worst.elapsedMs < roundDurationMs(12),
    "slowest master sample must either miss or beat the buzzer"
  );
  assert.ok(master.meanReactionMs + master.reactionJitterMs >= roundDurationMs(12) * 0.8);
});

test("reaction never goes below the 200ms floor, even with a wild profile", () => {
  const twitchy: BotProfile = { accuracy: 1, meanReactionMs: 300, reactionJitterMs: 5000 };
  const answer = botAnswer(twitchy, scripted(0, 0), 10_000);
  assert.equal(answer?.elapsedMs, 200);
});

test("the same seed always produces the same answer", () => {
  const first = botAnswer(profile, scripted(0.31, 0.62), 8000);
  for (let i = 0; i < 20; i++) {
    assert.deepEqual(botAnswer(profile, scripted(0.31, 0.62), 8000), first);
  }
});

test("accuracy holds up over a real distribution", () => {
  // Not a stub: a long run against Math.random, checking the profile's
  // headline number is actually what the bot delivers.
  const p: BotProfile = { accuracy: 0.75, meanReactionMs: 1000, reactionJitterMs: 100 };
  let answered = 0;
  let correct = 0;
  for (let i = 0; i < 20_000; i++) {
    const a = botAnswer(p, Math.random, 10_000);
    if (!a) continue;
    answered++;
    if (a.correct) correct++;
  }
  assert.equal(answered, 20_000, "a 1s reaction never times out at a 10s round");
  const rate = correct / answered;
  assert.ok(Math.abs(rate - 0.75) < 0.02, `accuracy was ${rate}`);
});

test("the three profiles are ordered — harder means more accurate and faster", () => {
  const ordered = BOT_DIFFICULTIES.map((d) => BOT_PROFILES[d]);
  for (let i = 1; i < ordered.length; i++) {
    assert.ok(ordered[i].accuracy > ordered[i - 1].accuracy, `accuracy at ${i}`);
    assert.ok(ordered[i].meanReactionMs < ordered[i - 1].meanReactionMs, `speed at ${i}`);
  }
});

test("every difficulty in the list has a profile", () => {
  for (const d of BOT_DIFFICULTIES) assert.ok(BOT_PROFILES[d], d);
});

test("the bot is scaled against its own mean, not a human's baseline", () => {
  // Handing it a constant would make `master` hit like a freak of nature for
  // being fast in general rather than for beating its own normal.
  for (const d of BOT_DIFFICULTIES) {
    assert.equal(botBaselineMs(BOT_PROFILES[d]), BOT_PROFILES[d].meanReactionMs);
  }
});

test("isBotDifficulty rejects anything not in the roster", () => {
  // It guards a URL parameter, so a bad value must not index into undefined.
  assert.equal(isBotDifficulty("rival"), true);
  assert.equal(isBotDifficulty("impossible"), false);
  assert.equal(isBotDifficulty(null), false);
  assert.equal(isBotDifficulty(""), false);
});

// ---------------------------------------------------------------------------
// The two modules together
// ---------------------------------------------------------------------------

// Everything above tests one function at a time, which is exactly how a mode
// ends up correct in every part and unplayable as a whole. This plays real
// matches and asserts the two properties that decide whether it is worth
// playing at all: the difficulties are actually different, and a match lasts.
//
// Bounds are deliberately loose. The measured rates at 4,000 matches per
// difficulty are 94% / 51% / 12% against an 0.8-accuracy 2.8s opponent; the
// assertions below would survive a fair amount of retuning and only fail if a
// change made a difficulty pointless or ended matches in a handful of rounds.
test("the three difficulties produce genuinely different matches", () => {
  const HUMAN: BotProfile = { accuracy: 0.8, meanReactionMs: 2800, reactionJitterMs: 1200 };
  const MATCHES = 2000;

  function winRate(foe: BotProfile) {
    let won = 0;
    let rounds = 0;
    for (let i = 0; i < MATCHES; i++) {
      const played: ResolvedRound[] = [];
      let state = deriveDuelState(played);
      for (let n = 1; n <= DUEL_ROUND_COUNT; n++) {
        const d = roundDurationMs(n);
        played.push(
          resolveRound(
            n,
            botAnswer(HUMAN, Math.random, d),
            botAnswer(foe, Math.random, d),
            HUMAN.meanReactionMs,
            botBaselineMs(foe),
            state
          )
        );
        state = deriveDuelState(played);
        if (duelOutcome(state) !== "ongoing") break;
      }
      if (duelOutcome(state) === "won") won++;
      rounds += played.length;
    }
    return { win: won / MATCHES, avgRounds: rounds / MATCHES };
  }

  const rookie = winRate(BOT_PROFILES.rookie);
  const rival = winRate(BOT_PROFILES.rival);
  const master = winRate(BOT_PROFILES.master);

  assert.ok(rookie.win > rival.win, `rookie ${rookie.win} should be easier than rival ${rival.win}`);
  assert.ok(rival.win > master.win, `rival ${rival.win} should be easier than master ${master.win}`);
  // Every difficulty has to be both winnable and losable, or it is scenery.
  assert.ok(master.win > 0.02, `master is unwinnable: ${master.win}`);
  assert.ok(rookie.win < 0.995, `rookie is unlosable: ${rookie.win}`);
  // The middle one should feel like a coin toss.
  assert.ok(Math.abs(rival.win - 0.5) < 0.2, `rival is not even: ${rival.win}`);
  // And a match must not be over before it starts — this is the assertion that
  // catches someone doubling BASE_DAMAGE.
  for (const [name, r] of [["rookie", rookie], ["rival", rival], ["master", master]] as const) {
    assert.ok(r.avgRounds > 8, `${name} matches end after ${r.avgRounds} rounds`);
  }
});

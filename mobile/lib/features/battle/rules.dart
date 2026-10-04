import 'dart:math';

// Monster Hunt's rules: a port of the web's damage.ts, quiz.ts and the rating
// helpers in BattleArena.tsx. Pinned to the TypeScript by the shared fixture
// web/src/app/decks/review/battle/_lib/fixtures/battle.fixture.json
// (test/battle_rules_test.dart), so the two games can't drift apart.
//
// Randomness comes in through a `double Function()` returning [0, 1) — the
// shape of JS's Math.random — and is consumed in the same order as the
// TypeScript, so scripted values reproduce a fight exactly.

typedef Rand = double Function();

final _rng = Random();
double defaultRand() => _rng.nextDouble();

const playerMaxHp = 100;
const monsterMaxHp = 100;

const _baseWrongDamage = 15;
const _baseCorrectDamage = 12;
const _easyDamageMultiplier = 1.3;
const _hardDamageMultiplier = 0.7;
const _critDamageMultiplier = 1.5;

const streakBonusThreshold = 2;
const _critChancePerStreakPoint = 0.05;
const _evadeChancePerStreakPoint = 0.05;
const _maxRollChance = 0.5;

const armorStreakInterval = 7;
const _maxArmorCharges = 1;

/// 10s per question; the thirds grade a correct answer's speed.
const questionTimeLimitMs = 10000;
const _easyCutoffMs = questionTimeLimitMs / 3;
const _goodCutoffMs = questionTimeLimitMs * 2 / 3;

class BattleEvent {
  const BattleEvent({
    required this.rating,
    required this.timedOut,
    required this.crit,
    required this.evaded,
    required this.armorConsumed,
    required this.damage,
  });

  final String rating;
  final bool timedOut;
  final bool crit;
  final bool evaded;
  final bool armorConsumed;
  final int damage;

  bool get correct => rating != 'again';

  factory BattleEvent.fromJson(Map<String, dynamic> j) => BattleEvent(
        rating: j['rating'] as String,
        timedOut: j['timedOut'] as bool,
        crit: j['crit'] as bool,
        evaded: j['evaded'] as bool,
        armorConsumed: j['armorConsumed'] as bool,
        damage: (j['damage'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'rating': rating,
        'timedOut': timedOut,
        'crit': crit,
        'evaded': evaded,
        'armorConsumed': armorConsumed,
        'damage': damage,
      };
}

class BattleState {
  const BattleState({
    required this.playerHp,
    required this.monsterHp,
    required this.streak,
    required this.armorCharges,
    required this.crit,
    required this.evaded,
    required this.armorConsumed,
  });

  final int playerHp;
  final int monsterHp;
  final int streak;
  final int armorCharges;
  final bool crit;
  final bool evaded;
  final bool armorConsumed;

  bool get playerDefeated => playerHp <= 0;
  bool get monsterDefeated => monsterHp <= 0;

  Map<String, dynamic> toJson() => {
        'playerHp': playerHp,
        'monsterHp': monsterHp,
        'streak': streak,
        'armorCharges': armorCharges,
        'crit': crit,
        'evaded': evaded,
        'armorConsumed': armorConsumed,
        'playerDefeated': playerDefeated,
        'monsterDefeated': monsterDefeated,
      };
}

double _clampChance(int streak, double perPoint) {
  final bonus = max(0, streak - streakBonusThreshold) * perPoint;
  return min(_maxRollChance, bonus);
}

double _correctDamageMultiplier(String rating) => switch (rating) {
      'easy' => _easyDamageMultiplier,
      'hard' => _hardDamageMultiplier,
      _ => 1,
    };

/// JS Math.round: halves round toward +infinity (Dart's round() goes away
/// from zero; the same for the positive damage values here, but kept exact).
int _jsRound(double v) => (v + 0.5).floorToDouble().toInt();

/// Resolves ONE answer. Impure (rolls crit/evade) — call exactly once per real
/// answer. Only [streak] and [armorCharges] of the state before are read.
BattleEvent rollEvent(
  String rating, {
  required int streak,
  required int armorCharges,
  bool timedOut = false,
  Rand rand = defaultRand,
}) {
  if (rating != 'again') {
    final crit = rand() < _clampChance(streak, _critChancePerStreakPoint);
    final damage = _jsRound(
      _baseCorrectDamage * _correctDamageMultiplier(rating) * (crit ? _critDamageMultiplier : 1),
    );
    return BattleEvent(
      rating: rating,
      timedOut: false,
      crit: crit,
      evaded: false,
      armorConsumed: false,
      damage: damage,
    );
  }

  // A held armour charge is a guaranteed save, checked before evade is rolled.
  if (armorCharges > 0) {
    return BattleEvent(
      rating: rating,
      timedOut: timedOut,
      crit: false,
      evaded: false,
      armorConsumed: true,
      damage: 0,
    );
  }

  final evaded = rand() < _clampChance(streak, _evadeChancePerStreakPoint);
  return BattleEvent(
    rating: rating,
    timedOut: timedOut,
    crit: false,
    evaded: evaded,
    armorConsumed: false,
    damage: evaded ? 0 : _baseWrongDamage,
  );
}

/// Pure fold over already-resolved events — never rolls, so undo is just
/// dropping the last event. Monster HP counts only events from
/// [monsterStartIndex] on (a new monster starts full); player HP and the
/// streak span the whole session.
BattleState deriveBattleState(List<BattleEvent> events, int monsterStartIndex) {
  var playerHp = playerMaxHp;
  var monsterHp = monsterMaxHp;
  var streak = 0;
  var armor = 0;
  var lastCrit = false, lastEvaded = false, lastArmor = false;

  for (var i = 0; i < events.length; i++) {
    final e = events[i];
    if (e.correct) {
      streak += 1;
      if (i >= monsterStartIndex) monsterHp = max(0, monsterHp - e.damage);
      if (streak % armorStreakInterval == 0) armor = min(_maxArmorCharges, armor + 1);
    } else {
      streak = 0;
      if (e.armorConsumed) {
        armor = max(0, armor - 1);
      } else {
        playerHp = max(0, playerHp - e.damage);
      }
    }
    lastCrit = e.crit;
    lastEvaded = e.evaded;
    lastArmor = e.armorConsumed;
  }

  return BattleState(
    playerHp: playerHp,
    monsterHp: monsterHp,
    streak: streak,
    armorCharges: armor,
    crit: lastCrit,
    evaded: lastEvaded,
    armorConsumed: lastArmor,
  );
}

/// How heavy the swing looks, from the streak.
int streakTier(int streak) {
  if (streak >= armorStreakInterval) return 2;
  if (streak > streakBonusThreshold) return 1;
  return 0;
}

enum BattleOutcome { ongoing, defeat, cleared }

/// Defeat is checked first: an answer that both kills the player and empties
/// the queue is a loss.
BattleOutcome battleOutcome(BattleState s, {required bool queueIsEmpty}) {
  if (s.playerDefeated) return BattleOutcome.defeat;
  if (queueIsEmpty) return BattleOutcome.cleared;
  return BattleOutcome.ongoing;
}

/// How fast a correct answer was. Drives damage only.
String ratingForElapsed(int elapsedMs) {
  if (elapsedMs < _easyCutoffMs) return 'easy';
  if (elapsedMs < _goodCutoffMs) return 'good';
  return 'hard';
}

/// What the scheduler is told: never "easy". A four-option question has a 25%
/// guess floor, and inside 3.3 seconds that luck must not buy interval
/// (CLAUDE.md 3.1b). The fight still uses the fast tier for damage.
String scheduleRating(String speed) => speed == 'easy' ? 'good' : speed;

// ---- Quiz -------------------------------------------------------------------

/// Below this many words a four-option question can't be built.
const minWordsForBattle = 4;

class QuizWord {
  const QuizWord({
    required this.id,
    required this.term,
    this.reading,
    this.meaning,
    this.meaningMn,
  });

  final String id;
  final String term;
  final String? reading;
  final String? meaning;
  final String? meaningMn;

  factory QuizWord.fromJson(Map<String, dynamic> j) => QuizWord(
        id: j['id'] as String,
        term: j['term'] as String,
        reading: j['reading'] as String?,
        meaning: j['meaning'] as String?,
        meaningMn: j['meaning_mn'] as String?,
      );
}

class QuizOption {
  const QuizOption({
    required this.term,
    this.reading,
    required this.answerText,
    required this.correct,
  });

  final String term;
  final String? reading;
  final String answerText;
  final bool correct;

  Map<String, dynamic> toJson() => {
        'term': term,
        'reading': reading,
        'answerText': answerText,
        'correct': correct,
      };
}

/// Mongolian meaning, falling back to English (quiz.ts `answerText`).
String answerTextOf(String? meaningMn, String? meaning) {
  final mn = meaningMn?.trim() ?? '';
  if (mn.isNotEmpty) return mn;
  return meaning?.trim() ?? '';
}

/// Fisher-Yates, consuming [rand] exactly as quiz.ts's `shuffle` does.
List<T> shuffled<T>(List<T> items, Rand rand) {
  final arr = [...items];
  for (var i = arr.length - 1; i > 0; i--) {
    final j = (rand() * (i + 1)).floor();
    final t = arr[i];
    arr[i] = arr[j];
    arr[j] = t;
  }
  return arr;
}

/// Four options: the card's meaning plus three from the player's own words,
/// excluded by word id (not term). Synchronous, no network.
List<QuizOption> buildQuiz({
  required String wordId,
  required String term,
  String? reading,
  String? meaning,
  String? meaningMn,
  required List<QuizWord> allWords,
  Rand rand = defaultRand,
}) {
  final correct = QuizOption(
    term: term,
    reading: reading,
    answerText: answerTextOf(meaningMn, meaning),
    correct: true,
  );
  final pool = allWords
      .where((w) => w.id != wordId && answerTextOf(w.meaningMn, w.meaning).isNotEmpty)
      .toList();
  final distractors = shuffled(pool, rand).take(3).map((w) => QuizOption(
        term: w.term,
        reading: w.reading,
        answerText: answerTextOf(w.meaningMn, w.meaning),
        correct: false,
      ));
  return shuffled([correct, ...distractors], rand);
}

// ---- Projectiles ------------------------------------------------------------

/// Characters whose attack leaves their hands, by pose (projectiles.ts).
const projectileFrames = <String, Map<String, int>>{
  'archer': {'attack01': 1, 'attack02': 1},
  'black-knight-b': {'attack03': 1},
  'demon-b': {'attack01': 1},
  'necromancer': {'attack02': 6},
  'priest': {'attack01': 5},
  'skeleton-archer': {'attack01': 1},
  'warlock': {'attack02': 9},
  'wizard': {'attack01': 10, 'attack02': 7},
};

int? projectileFor(String slug, String pose) => projectileFrames[slug]?[pose];

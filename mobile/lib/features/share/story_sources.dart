import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/strings.dart';
import '../../models/library.dart';
import 'story_card.dart';

StoryWord _word(Map<String, dynamic> w) => StoryWord(
      term: w['term'] as String,
      reading: w['reading'] as String?,
      meaningMn: w['meaning_mn'] as String?,
      meaningEn: w['meaning'] as String?,
    );

/// "Today's words" — share_today() (0028): the SRS day's recalls, same card
/// the web's TodayShareModal makes. Null when nothing was recalled yet.
Future<StoryCard?> todayStory({required int streak}) async {
  final r = await Supabase.instance.client.rpc('share_today', params: {'p_limit': 50});
  final m = Map<String, dynamic>.from(r as Map);
  final words = (m['words'] as List? ?? const []).map((w) => _word(Map<String, dynamic>.from(w as Map))).toList();
  if (words.isEmpty) return null;
  final day = DateTime.parse(m['day'] as String);
  final recalled = (m['recalled'] as num?)?.toInt() ?? words.length;
  final added = (m['added'] as num?)?.toInt() ?? 0;
  return StoryCard(
    kicker: '${monthMn[day.month - 1]} сарын ${day.day}',
    heading: T.storyTodayHeading,
    numbers: [
      StoryNumber('$recalled', T.storyNumRecalled),
      if (added > 0) StoryNumber('$added', T.storyNumAdded),
      if (streak > 1) StoryNumber('$streak', T.storyNumStreak),
    ],
    words: words.take(storyMaxWords).toList(),
    total: recalled,
    moreLabel: T.storyMore,
  );
}

/// A shared deck's invitation, like the web's DeckShareModal: the deck's
/// first words in the order they were added.
Future<StoryCard?> deckStory(Deck deck) async {
  final db = Supabase.instance.client;
  final rows = await db
      .from('words')
      .select('term, reading, meaning, meaning_mn')
      .eq('deck_id', deck.id)
      .eq('deleted', false)
      .order('date_added')
      .limit(storyMaxWords);
  final words = rows.map(_word).toList();
  if (words.isEmpty) return null;
  final count = await db
      .from('words')
      .count(CountOption.exact)
      .eq('deck_id', deck.id)
      .eq('deleted', false);
  return StoryCard(
    kicker: T.sharedBy,
    heading: deck.name,
    numbers: [StoryNumber('$count', T.storyNumWords)],
    words: words,
    total: count,
    moreLabel: T.storyMore,
  );
}

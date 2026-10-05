import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_deck.dart';

final deckPlayerProvider = Provider<DeckPlayer>((ref) {
  final player = DeckPlayer();
  ref.onDispose(player.dispose);
  return player;
});

/// Plays one audio deck in the app, with its own just_audio player (separate
/// from word pronunciation in core/audio.dart). "Skip" moves by word, using
/// the deck's cues — a deck is one file.
///
/// No lock-screen controls on purpose: audio_service, the package that
/// provides them, deadlocked Android's main thread on this Flutter version
/// (Dart and the platform share one thread since 3.29, and the opt-out flag
/// is no longer allowed) — an ANR on first play, then a hang at launch when
/// started from main(). For listening with the screen locked, the player
/// hands the MP3 to the phone's own music app instead.
class DeckPlayer {
  DeckPlayer() {
    _player.processingStateStream.listen((s) {
      // At the end, stop at the start rather than sit past the last word.
      if (s == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero);
      }
    });
  }

  final _player = AudioPlayer();
  AudioDeck? deck;

  Stream<Duration> get positionStream => _player.positionStream;
  Duration get position => _player.position;
  bool get playing => _player.playing;
  Stream<bool> get playingStream => _player.playingStream;

  /// Loads [d] unless it's already the one loaded (returning to the player
  /// screen mustn't restart a deck mid-walk).
  Future<void> open(AudioDeck d) async {
    if (deck?.path == d.path && deck?.createdAt == d.createdAt) return;
    deck = d;
    await _player.setFilePath(d.path);
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> fastForward() => _seekBy(const Duration(seconds: 10));
  Future<void> rewind() => _seekBy(const Duration(seconds: -10));

  /// Next or previous word. "Previous" a moment into a word restarts it,
  /// the way a music player's back button restarts a song.
  Future<void> skipWord(int delta) async {
    final d = deck;
    if (d == null || d.cues.isEmpty) return;
    final ms = _player.position.inMilliseconds;
    var i = d.cueAt(ms);
    final restart = delta < 0 && ms - d.cues[i].startMs > 1500;
    if (!restart) i = (i + delta).clamp(0, d.cues.length - 1);
    await _player.seek(Duration(milliseconds: d.cues[i].startMs));
  }

  Future<void> _seekBy(Duration by) async {
    final total = _player.duration ?? Duration.zero;
    var to = _player.position + by;
    if (to < Duration.zero) to = Duration.zero;
    if (to > total) to = total;
    await _player.seek(to);
  }

  /// Unloads the deck (its file is about to go).
  Future<void> close() async {
    deck = null;
    await _player.stop();
  }

  Future<void> dispose() => _player.dispose();
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repository.dart';

final audioProvider = Provider<AudioCache>((ref) {
  final cache = AudioCache(ref.watch(supabaseProvider));
  ref.onDispose(cache.dispose);
  return cache;
});

/// Pronunciation playback with an on-disk cache.
///
/// Audio lives in a private Supabase Storage bucket, so every play would
/// otherwise be: sign a URL, then stream it. That is fine on wifi and useless
/// on the underground — which is exactly where the review queue gets used.
/// So the day's clips are pulled to disk up front and played from there.
///
/// Files are keyed by word id and never expire: a word's pronunciation doesn't
/// change, and the whole point is that they survive going offline. They are
/// small (a second or two of speech) and live in the OS cache directory, which
/// the system may reclaim under storage pressure.
class AudioCache {
  AudioCache(this._db);

  final SupabaseClient _db;
  final _player = AudioPlayer();
  Directory? _dir;

  Future<Directory> _cacheDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}/word-audio');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  File _fileFor(Directory dir, String wordId) => File('${dir.path}/$wordId.mp3');

  /// Downloads [audioPath] if it isn't already on disk. Returns the local file,
  /// or null if the download failed — a missing clip must never break a review.
  Future<File?> ensureCached(String wordId, String? audioPath) async {
    if (audioPath == null || audioPath.isEmpty) return null;
    try {
      final dir = await _cacheDir();
      final file = _fileFor(dir, wordId);
      if (await file.exists() && await file.length() > 0) return file;

      final bytes = await _db.storage.from('word-audio').download(audioPath);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (e) {
      debugPrint('Audio cache miss for $wordId: $e');
      return null;
    }
  }

  /// Warms the cache for a whole queue, one at a time so a session start
  /// doesn't fire fifty parallel downloads at a phone on a weak connection.
  /// Failures are per-word and silent; this is opportunistic.
  Future<void> precache(Iterable<({String wordId, String? audioPath})> items) async {
    for (final item in items) {
      if (item.audioPath == null) continue;
      await ensureCached(item.wordId, item.audioPath);
    }
  }

  /// Plays a word's pronunciation, preferring the cached file and falling back
  /// to a signed URL when the clip hasn't been cached yet.
  Future<void> play(String wordId, String? audioPath) async {
    if (audioPath == null || audioPath.isEmpty) return;
    try {
      final file = await ensureCached(wordId, audioPath);
      if (file != null) {
        await _player.setFilePath(file.path);
      } else {
        final signed = await _db.storage
            .from('word-audio')
            .createSignedUrl(audioPath, 60);
        await _player.setUrl(signed);
      }
      await _player.play();
    } catch (e) {
      debugPrint('Audio playback failed for $wordId: $e');
    }
  }

  void dispose() => _player.dispose();
}

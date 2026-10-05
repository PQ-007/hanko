import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../battle/fight_scene.dart';
import '../battle/hero.dart';
import '../decks/word_actions.dart';
import 'capture_review_screen.dart';
import 'ocr_layout.dart';
import 'photo_view_screen.dart';
import 'segment.dart';

/// Camera capture, step one: photograph (or pick) pages of Japanese, crop and
/// brush-select on the photo itself ([PhotoViewScreen]), then choose which
/// words to keep — from the brushed words, the suggestions, or any span of the
/// recognised text selected by hand.
///
/// Text recognition runs on the phone (ML Kit's bundled Japanese model), so
/// this step works with no connection at all; only the dictionary lookup on
/// the next step needs one.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.japanese);
  final _picker = ImagePicker();

  /// Photos in the order taken.
  final _photos = <ScannedPhoto>[];

  /// Words the user has chosen, in the order chosen (Dart sets keep insertion
  /// order), from suggestions and manual selections alike.
  final _chosen = <String>{};

  bool _reading = false;

  @override
  void dispose() {
    _recognizer.close();
    super.dispose();
  }

  Future<void> _scan(ImageSource source) async {
    final XFile? file;
    try {
      // 2400px still gives a printed character dozens of pixels — plenty for
      // recognition — while a full 12MP photo would cost ~50MB to display.
      file = await _picker.pickImage(source: source, maxWidth: 2400, maxHeight: 2400, imageQuality: 92);
    } catch (e) {
      if (mounted) toast(context, '${T.captureFailed}: $e');
      return;
    }
    if (file == null || !mounted) return;
    setState(() => _reading = true);
    ScannedPhoto? photo;
    try {
      final size = await _imageSize(file.path);
      final result = await _recognizer.processImage(InputImage.fromFilePath(file.path));
      final units = unitsFrom(result);
      if (!mounted) return;
      if (!units.any((u) => _hasJapanese(u.text))) {
        toast(context, T.captureNothingFound);
      } else {
        photo = ScannedPhoto(path: file.path, size: size, units: units);
      }
    } catch (e) {
      if (mounted) toast(context, '${T.captureFailed}: $e');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
    if (photo != null && mounted) await _edit(photo, isNew: true);
  }

  /// The image's size as Flutter displays it (EXIF rotation applied), which
  /// is also the space ML Kit reports boxes in for a file input.
  static Future<Size> _imageSize(String path) async {
    final codec = await ui.instantiateImageCodec(await XFile(path).readAsBytes());
    final frame = await codec.getNextFrame();
    final size = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    frame.image.dispose();
    codec.dispose();
    return size;
  }

  /// Opens the photo view. A new photo backed out of is dropped (like
  /// cancelling a scan); an existing one just keeps its previous state.
  Future<void> _edit(ScannedPhoto photo, {bool isNew = false}) async {
    final edit = await Navigator.of(context).push<PhotoEdit>(
      MaterialPageRoute(builder: (_) => PhotoViewScreen(photo: photo)),
    );
    if (!mounted || edit == null) return;
    setState(() {
      photo.crop = edit.crop;
      photo.brushed
        ..clear()
        ..addAll(edit.brushed);
      final after = pickedWords(photo.units, photo.crop, photo.brushed);
      // Words this photo no longer picks leave the chosen list; newly picked
      // ones join. Words it already picked are left as they are, so one the
      // user unticked stays unticked after re-cropping.
      _chosen.removeAll(photo.picked.where((w) => !after.contains(w)));
      _chosen.addAll(after.where((w) => !photo.picked.contains(w)));
      photo.picked = after;
      if (isNew) _photos.add(photo);
    });
  }

  static bool _hasJapanese(String s) =>
      s.runes.any((c) => (c >= 0x3040 && c <= 0x30FF) || (c >= 0x4E00 && c <= 0x9FFF));

  void _toggle(String word) {
    setState(() => _chosen.contains(word) ? _chosen.remove(word) : _chosen.add(word));
  }

  void _addSelection(String text) {
    final word = text.trim();
    if (word.isEmpty) return;
    setState(() => _chosen.add(word));
  }

  Future<void> _next() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CaptureReviewScreen(terms: _chosen.toList())),
    );
    if (saved == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final hero = ref.watch(heroProvider);
    final body = _reading
        ? const LoadingScene(label: T.captureReading)
        : _photos.isEmpty
            ? HeroEmptyState(
                hero: hero,
                title: T.captureTitle,
                subtitle: T.captureIntro,
                action: _SourceButtons(onPick: _scan),
              )
            : _Picker(
                photos: _photos,
                chosen: _chosen,
                onToggle: _toggle,
                onAll: (words, on) => setState(() => on ? _chosen.addAll(words) : _chosen.removeAll(words)),
                onAddSelection: _addSelection,
                onRemovePhoto: (i) => setState(() => _photos.removeAt(i)),
                onEditPhoto: (i) => _edit(_photos[i]),
                onAnotherPhoto: _scan,
              );

    return Scaffold(
      appBar: AppBar(title: const Text(T.captureTitle)),
      body: body,
      bottomNavigationBar: _photos.isEmpty || _reading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _chosen.isEmpty ? null : _next,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(T.captureNext(_chosen.length)),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ),
    );
  }
}

class _SourceButtons extends StatelessWidget {
  const _SourceButtons({required this.onPick});
  final void Function(ImageSource) onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () => onPick(ImageSource.camera),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text(T.captureTakePhoto),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => onPick(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text(T.captureFromGallery),
        ),
      ],
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.photos,
    required this.chosen,
    required this.onToggle,
    required this.onAll,
    required this.onAddSelection,
    required this.onRemovePhoto,
    required this.onEditPhoto,
    required this.onAnotherPhoto,
  });

  final List<ScannedPhoto> photos;
  final Set<String> chosen;
  final ValueChanged<String> onToggle;
  final void Function(List<String> words, bool on) onAll;
  final ValueChanged<String> onAddSelection;
  final ValueChanged<int> onRemovePhoto;
  final ValueChanged<int> onEditPhoto;
  final void Function(ImageSource) onAnotherPhoto;

  @override
  Widget build(BuildContext context) {
    final lines = [for (final p in photos) linesIn(p.units, p.crop)];
    final suggestions = suggestWords(lines.expand((l) => l));
    // Hand-selected words that aren't suggestions still need a chip, or
    // there'd be no way to see or undo them.
    final chips = [...suggestions, ...chosen.where((w) => !suggestions.contains(w))];
    final muted = TextStyle(fontSize: 12, color: context.hk.inkMute);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Expanded(child: Text(T.captureSuggestions, style: Theme.of(context).textTheme.titleMedium)),
            if (chips.isNotEmpty)
              chips.every(chosen.contains)
                  ? TextButton(onPressed: () => onAll(chips, false), child: const Text(T.captureNone))
                  : TextButton(onPressed: () => onAll(chips, true), child: const Text(T.captureAll)),
          ],
        ),
        Text(T.captureSuggestionsHint, style: muted),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final w in chips)
              FilterChip(
                label: Text(w, style: const TextStyle(fontSize: 16)),
                selected: chosen.contains(w),
                onSelected: (_) => onToggle(w),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text(T.captureText, style: Theme.of(context).textTheme.titleMedium),
        Text(T.captureTextHint, style: muted),
        for (var i = 0; i < photos.length; i++) ...[
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 4, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(T.capturePhotoN(i + 1), style: muted)),
                      IconButton(
                        tooltip: T.captureEditPhoto,
                        icon: const Icon(Icons.crop, size: 18),
                        onPressed: () => onEditPhoto(i),
                      ),
                      IconButton(
                        tooltip: T.captureRemovePhoto,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => onRemovePhoto(i),
                      ),
                    ],
                  ),
                  for (final line in lines[i])
                    Padding(
                      padding: const EdgeInsets.only(right: 10, bottom: 4),
                      child: SelectableText(
                        line,
                        style: const TextStyle(fontSize: 20, height: 1.5),
                        contextMenuBuilder: (context, editable) {
                          final value = editable.textEditingValue;
                          final selected = value.selection.textInside(value.text);
                          return AdaptiveTextSelectionToolbar.buttonItems(
                            anchors: editable.contextMenuAnchors,
                            buttonItems: [
                              if (selected.trim().isNotEmpty)
                                ContextMenuButtonItem(
                                  label: T.captureAddSelection,
                                  onPressed: () {
                                    onAddSelection(selected);
                                    editable.hideToolbar();
                                  },
                                ),
                              ...editable.contextMenuButtonItems,
                            ],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onAnotherPhoto(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text(T.captureAnotherPhoto),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: T.captureFromGallery,
              onPressed: () => onAnotherPhoto(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
            ),
          ],
        ),
      ],
    );
  }
}

/// ML Kit's result flattened into [OcrUnit]s: one per character where ML Kit
/// reports characters, else one per element, in reading order.
List<OcrUnit> unitsFrom(RecognizedText result) {
  final units = <OcrUnit>[];
  var lineIndex = 0;
  for (final block in result.blocks) {
    for (final line in block.lines) {
      final height = line.boundingBox.height;
      Rect? previous;
      for (final element in line.elements) {
        final parts = element.symbols.isNotEmpty
            ? [for (final s in element.symbols) (s.text, s.boundingBox)]
            : [(element.text, element.boundingBox)];
        for (final (text, rect) in parts) {
          if (text.trim().isEmpty) continue;
          units.add(OcrUnit(
            line: lineIndex,
            text: text,
            rect: rect,
            gapBefore: previous != null && isGap(previous, rect, height),
          ));
          previous = rect;
        }
      }
      lineIndex++;
    }
  }
  return units;
}

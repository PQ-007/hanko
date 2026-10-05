import 'dart:typed_data';

/// Just enough MP3 to join speech clips into one file on the phone, with no
/// encoder: MP3 is a sequence of self-contained frames, so clips that share a
/// format can be concatenated frame for frame, and silence is frames whose
/// audio data is all zero.
///
/// Google's TTS clips (what audio decks are made of) are all MPEG-2 Layer III,
/// 24 kHz, mono, 64 kbps for both Japanese and English, which is what makes
/// this possible; [Mp3Format.of] checks it rather than assuming.

// Bitrates (kbps) by index, MPEG-1 Layer III and MPEG-2/2.5 Layer III.
const _bitratesV1 = [
  0,
  32,
  40,
  48,
  56,
  64,
  80,
  96,
  112,
  128,
  160,
  192,
  224,
  256,
  320,
];
const _bitratesV2 = [
  0,
  8,
  16,
  24,
  32,
  40,
  48,
  56,
  64,
  80,
  96,
  112,
  128,
  144,
  160,
];
// Sample rates (Hz) by index, for MPEG-1, MPEG-2, MPEG-2.5.
const _rates = {
  3: [44100, 48000, 32000],
  2: [22050, 24000, 16000],
  0: [11025, 12000, 8000],
};

/// One frame header, decoded.
class Mp3Frame {
  const Mp3Frame({
    required this.size,
    required this.sampleRate,
    required this.samples,
    required this.header,
  });

  /// Bytes in the whole frame, header included.
  final int size;
  final int sampleRate;

  /// Audio samples the frame holds (1152 for MPEG-1, 576 for MPEG-2/2.5).
  final int samples;

  /// The four header bytes, with the padding bit as found.
  final Uint8List header;

  double get ms => samples * 1000 / sampleRate;

  /// Decodes the header at [i], or null if there isn't a valid Layer III
  /// frame header there.
  static Mp3Frame? at(Uint8List b, int i) {
    if (i + 4 > b.length || b[i] != 0xFF || (b[i + 1] & 0xE0) != 0xE0) {
      return null;
    }
    final version =
        (b[i + 1] >> 3) & 0x3; // 3 = MPEG-1, 2 = MPEG-2, 0 = MPEG-2.5
    final layer = (b[i + 1] >> 1) & 0x3; // 1 = Layer III
    if (version == 1 || layer != 1) return null;
    final bitrateIndex = b[i + 2] >> 4;
    final rateIndex = (b[i + 2] >> 2) & 0x3;
    if (bitrateIndex == 0 || bitrateIndex == 15 || rateIndex == 3) return null;
    final padding = (b[i + 2] >> 1) & 0x1;
    final v1 = version == 3;
    final bitrate = (v1 ? _bitratesV1 : _bitratesV2)[bitrateIndex] * 1000;
    final sampleRate = _rates[version]![rateIndex];
    final samples = v1 ? 1152 : 576;
    final size = (samples ~/ 8) * bitrate ~/ sampleRate + padding;
    return Mp3Frame(
      size: size,
      sampleRate: sampleRate,
      samples: samples,
      header: Uint8List.fromList(b.sublist(i, i + 4)),
    );
  }

  /// Whether two frames can sit in one stream: same version, layer, bitrate,
  /// sample rate and channel mode (padding may differ frame to frame).
  bool sameFormat(Mp3Frame o) =>
      header[1] == o.header[1] &&
      (header[2] & 0xFC) == (o.header[2] & 0xFC) &&
      (header[3] & 0xC0) == (o.header[3] & 0xC0);
}

/// The audio frames of [bytes]: an ID3v2 tag at the front and an ID3v1 tag at
/// the end (either may be absent) are dropped, and only whole, valid frames
/// are kept — so a clip can be appended to another without its metadata
/// turning into a click.
Uint8List audioFrames(Uint8List bytes) {
  var start = 0;
  if (bytes.length >= 10 &&
      bytes[0] == 0x49 &&
      bytes[1] == 0x44 &&
      bytes[2] == 0x33) {
    // ID3v2: size is four 7-bit bytes, plus the 10-byte header (and a footer).
    final size =
        (bytes[6] << 21) | (bytes[7] << 14) | (bytes[8] << 7) | bytes[9];
    start = 10 + size + ((bytes[5] & 0x10) != 0 ? 10 : 0);
  }
  final out = BytesBuilder(copy: false);
  var i = start;
  while (i < bytes.length) {
    final f = Mp3Frame.at(bytes, i);
    if (f == null || i + f.size > bytes.length) break;
    out.add(Uint8List.sublistView(bytes, i, i + f.size));
    i += f.size;
  }
  return out.takeBytes();
}

/// The first frame of [bytes] (after any ID3v2 tag), describing its format.
Mp3Frame? firstFrame(Uint8List bytes) {
  final frames = audioFrames(bytes);
  return frames.isEmpty ? null : Mp3Frame.at(frames, 0);
}

/// Playing time of an MP3 stream, by walking its frames — exact, unlike a
/// bitrate estimate, which is what lets the player know which word it's on.
double mp3DurationMs(Uint8List bytes) {
  var ms = 0.0;
  var i = 0;
  while (i < bytes.length) {
    final f = Mp3Frame.at(bytes, i);
    if (f == null) break;
    ms += f.ms;
    i += f.size;
  }
  return ms;
}

/// About [ms] of silence in [format]: unpadded frames with zeroed side
/// information, which decoders play as silence.
Uint8List silence(Mp3Frame format, double ms) {
  final header = Uint8List.fromList(format.header)
    ..[2] &= 0xFD; // clear padding
  final frame = Mp3Frame.at(
    Uint8List.fromList([...header, ...Uint8List(1024)]),
    0,
  )!;
  final count = (ms / frame.ms).round();
  final out = Uint8List(frame.size * count);
  for (var k = 0; k < count; k++) {
    out.setRange(k * frame.size, k * frame.size + 4, header);
  }
  return out;
}

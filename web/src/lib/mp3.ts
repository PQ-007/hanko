// Just enough MP3 to join speech clips into one file in the browser, with no
// encoder: MP3 is a sequence of self-contained frames, so clips that share a
// format can be concatenated frame for frame, and silence is frames whose
// audio data is all zero.
//
// Google's TTS clips (what audio decks are made of) are all MPEG-2 Layer III,
// 24 kHz, mono, 64 kbps for both Japanese and English, which is what makes
// this possible; Mp3Frame.at checks it rather than assuming.
//
// A port of mobile/lib/features/audio/mp3.dart, pinned by the same cases on
// the same recorded clips (mp3.test.ts / mp3_test.dart).

// Bitrates (kbps) by index, MPEG-1 Layer III and MPEG-2/2.5 Layer III.
const BITRATES_V1 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320];
const BITRATES_V2 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160];
// Sample rates (Hz) by index, for MPEG-1, MPEG-2, MPEG-2.5.
const RATES: Record<number, number[]> = {
  3: [44100, 48000, 32000],
  2: [22050, 24000, 16000],
  0: [11025, 12000, 8000],
};

/** One frame header, decoded. */
export class Mp3Frame {
  /** Bytes in the whole frame, header included. */
  readonly size: number;
  readonly sampleRate: number;
  /** Audio samples the frame holds (1152 for MPEG-1, 576 for MPEG-2/2.5). */
  readonly samples: number;
  /** The four header bytes, with the padding bit as found. */
  readonly header: Uint8Array;

  // Fields spelled out rather than parameter properties: node's type
  // stripping, which runs the tests, can't run those.
  constructor(size: number, sampleRate: number, samples: number, header: Uint8Array) {
    this.size = size;
    this.sampleRate = sampleRate;
    this.samples = samples;
    this.header = header;
  }

  get ms(): number {
    return (this.samples * 1000) / this.sampleRate;
  }

  /** The header at `i`, or null if there isn't a valid Layer III frame header there. */
  static at(b: Uint8Array, i: number): Mp3Frame | null {
    if (i + 4 > b.length || b[i] !== 0xff || (b[i + 1] & 0xe0) !== 0xe0) return null;
    const version = (b[i + 1] >> 3) & 0x3; // 3 = MPEG-1, 2 = MPEG-2, 0 = MPEG-2.5
    const layer = (b[i + 1] >> 1) & 0x3; // 1 = Layer III
    if (version === 1 || layer !== 1) return null;
    const bitrateIndex = b[i + 2] >> 4;
    const rateIndex = (b[i + 2] >> 2) & 0x3;
    if (bitrateIndex === 0 || bitrateIndex === 15 || rateIndex === 3) return null;
    const padding = (b[i + 2] >> 1) & 0x1;
    const v1 = version === 3;
    const bitrate = (v1 ? BITRATES_V1 : BITRATES_V2)[bitrateIndex] * 1000;
    const sampleRate = RATES[version][rateIndex];
    const samples = v1 ? 1152 : 576;
    const size = Math.floor((Math.floor(samples / 8) * bitrate) / sampleRate) + padding;
    return new Mp3Frame(size, sampleRate, samples, b.slice(i, i + 4));
  }

  /**
   * Whether two frames can sit in one stream: same version, layer, bitrate,
   * sample rate and channel mode (padding may differ frame to frame).
   */
  sameFormat(o: Mp3Frame): boolean {
    return (
      this.header[1] === o.header[1] &&
      (this.header[2] & 0xfc) === (o.header[2] & 0xfc) &&
      (this.header[3] & 0xc0) === (o.header[3] & 0xc0)
    );
  }
}

/** Joins byte arrays into one. */
export function concat(parts: Uint8Array[]): Uint8Array<ArrayBuffer> {
  const out = new Uint8Array(new ArrayBuffer(parts.reduce((n, p) => n + p.length, 0)));
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}

/**
 * The audio frames of `bytes`: an ID3v2 tag at the front and an ID3v1 tag at
 * the end (either may be absent) are dropped, and only whole, valid frames are
 * kept — so a clip can be appended to another without its metadata turning
 * into a click.
 */
export function audioFrames(bytes: Uint8Array): Uint8Array {
  let start = 0;
  if (bytes.length >= 10 && bytes[0] === 0x49 && bytes[1] === 0x44 && bytes[2] === 0x33) {
    // ID3v2: size is four 7-bit bytes, plus the 10-byte header (and a footer).
    const size = (bytes[6] << 21) | (bytes[7] << 14) | (bytes[8] << 7) | bytes[9];
    start = 10 + size + ((bytes[5] & 0x10) !== 0 ? 10 : 0);
  }
  let i = start;
  while (i < bytes.length) {
    const f = Mp3Frame.at(bytes, i);
    if (!f || i + f.size > bytes.length) break;
    i += f.size;
  }
  return bytes.subarray(start, i);
}

/** The first frame of `bytes` (after any ID3v2 tag), describing its format. */
export function firstFrame(bytes: Uint8Array): Mp3Frame | null {
  const frames = audioFrames(bytes);
  return frames.length === 0 ? null : Mp3Frame.at(frames, 0);
}

/**
 * Playing time of an MP3 stream, by walking its frames — exact, unlike a
 * bitrate estimate, which is what lets the player know which word it's on.
 */
export function mp3DurationMs(bytes: Uint8Array): number {
  let ms = 0;
  let i = 0;
  while (i < bytes.length) {
    const f = Mp3Frame.at(bytes, i);
    if (!f) break;
    ms += f.ms;
    i += f.size;
  }
  return ms;
}

/** About `ms` of silence in `format`: unpadded frames with zeroed side information, which decoders play as silence. */
export function silence(format: Mp3Frame, ms: number): Uint8Array {
  const header = format.header.slice();
  header[2] &= 0xfd; // clear padding
  const probe = new Uint8Array(4 + 1024);
  probe.set(header);
  const frame = Mp3Frame.at(probe, 0)!;
  const count = Math.round(ms / frame.ms);
  const out = new Uint8Array(frame.size * count);
  for (let k = 0; k < count; k++) out.set(header, k * frame.size);
  return out;
}

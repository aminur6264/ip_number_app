// Generates the IP Call BD launcher icon assets:
//   assets/icon/app_icon.png            - full-bleed 1024x1024 master icon
//   assets/icon/app_icon_foreground.png - transparent glyph for Android adaptive icons
//
// Pure Dart (no packages): shapes are rasterized with 4x4 supersampling and
// encoded as PNG via a minimal hand-rolled writer (zlib comes from dart:io).
//
// Run:  dart run tool/generate_app_icon.dart

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int size = 1024;
const int ss = 4; // supersampling factor per axis

// Brand palette (matches the app theme seed 0xFF129E8F).
const List<int> bgTopLeft = [12, 74, 66]; // #0C4A42 deep teal
const List<int> bgBottomRight = [18, 158, 143]; // #129E8F brand teal

// Glyph geometry in 1024-space, centered on the icon.
const double c = 512.0;
const double knobDist = 205.0; // ear/mouth knob centers on the 225/45 diagonal
const double knobRadius = 118.0;
const double bandMid = 205.0, bandHalf = 52.0; // connecting grip band
const double wave1Mid = 350.0, wave1Half = 26.0; // signal arcs (top-right fan)
const double wave2Mid = 458.0, wave2Half = 30.0;
const double waveSpreadDeg = 32.0;

final double knobDx = knobDist / math.sqrt2; // 45deg offsets
final Offset knobA = Offset(c - knobDx, c - knobDx); // top-left (ear)
final Offset knobB = Offset(c + knobDx, c + knobDx); // bottom-right (mouth)

class Offset {
  final double x, y;
  const Offset(this.x, this.y);
}

bool insideGlyph(double x, double y) => insideHandset(x, y) || insideWaves(x, y);

/// Classic handset: two round knobs joined by an arc band bowing through the
/// bottom-left, leaving the top-right open for the signal waves.
bool insideHandset(double x, double y) {
  if (_inCircle(x, y, knobA.x, knobA.y, knobRadius)) return true;
  if (_inCircle(x, y, knobB.x, knobB.y, knobRadius)) return true;
  final dx = x - c, dy = y - c;
  final dist = math.sqrt(dx * dx + dy * dy);
  if (dist < bandMid - bandHalf || dist > bandMid + bandHalf) return false;
  // Sector from the mouth knob (45deg) round the bottom-left to the ear knob.
  return _angleIn(dx, dy, 45, 225);
}

bool insideWaves(double x, double y) {
  final dx = x - c, dy = y - c;
  final dist = math.sqrt(dx * dx + dy * dy);
  if (!_ring(dist, wave1Mid, wave1Half) && !_ring(dist, wave2Mid, wave2Half)) {
    return false;
  }
  return _angleIn(dx, dy, 315 - waveSpreadDeg, 315 + waveSpreadDeg);
}

bool _inCircle(double px, double py, double cx, double cy, double r) {
  final dx = px - cx, dy = py - cy;
  return dx * dx + dy * dy <= r * r;
}

bool _ring(double dist, double mid, double half) =>
    dist >= mid - half && dist <= mid + half;

bool _angleIn(double dx, double dy, double lo, double hi) {
  final a = (math.atan2(dy, dx) * 180 / math.pi + 360) % 360;
  return a >= lo && a <= hi;
}

Uint8List render(bool fullBleed, double glyphScale) {
  final px = Uint8List(size * size * 4);
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      // 4x4 supersampled glyph coverage.
      var cov = 0.0;
      for (int sy = 0; sy < ss; sy++) {
        for (int sx = 0; sx < ss; sx++) {
          final spx = x + (sx + 0.5) / ss, spy = y + (sy + 0.5) / ss;
          // Inverse-scale about the center for the adaptive foreground.
          final gx = c + (spx - c) / glyphScale;
          final gy = c + (spy - c) / glyphScale;
          if (insideGlyph(gx, gy)) cov += 1 / (ss * ss);
        }
      }

      final i = (y * size + x) * 4;
      if (fullBleed) {
        // Diagonal gradient background with the white glyph on top.
        final t = (x + y) / (2 * (size - 1));
        px[i] = _lerp(bgTopLeft[0], bgBottomRight[0], t);
        px[i + 1] = _lerp(bgTopLeft[1], bgBottomRight[1], t);
        px[i + 2] = _lerp(bgTopLeft[2], bgBottomRight[2], t);
        px[i + 3] = 255;
        px[i] = _over(px[i], 255, cov);
        px[i + 1] = _over(px[i + 1], 255, cov);
        px[i + 2] = _over(px[i + 2], 255, cov);
      } else {
        // Transparent foreground: white glyph only (straight alpha).
        px[i] = 255;
        px[i + 1] = 255;
        px[i + 2] = 255;
        px[i + 3] = (cov * 255).round().clamp(0, 255);
      }
    }
  }
  return px;
}

int _lerp(int a, int b, double t) => (a + (b - a) * t).round();
int _over(int bg, int fg, double cov) =>
    (bg * (1 - cov) + fg * cov).round().clamp(0, 255);

// ---------------------------------------------------------------------------
// Minimal PNG writer (RGBA8, filter 0).
// ---------------------------------------------------------------------------

void writePng(String path, Uint8List rgba) {
  final raw = BytesBuilder();
  for (int y = 0; y < size; y++) {
    raw.addByte(0); // filter: none
    raw.add(rgba.sublist(y * size * 4, (y + 1) * size * 4));
  }
  final idat = ZLibEncoder().convert(raw.toBytes());

  final ihdr = ByteData(13);
  ihdr.setUint32(0, size);
  ihdr.setUint32(4, size);
  ihdr.setUint8(8, 8); // bit depth
  ihdr.setUint8(9, 6); // color type: RGBA
  ihdr.setUint8(12, 0); // interlace: none

  final out = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_chunk('IHDR', ihdr.buffer.asUint8List()))
    ..add(_chunk('IDAT', idat))
    ..add(_chunk('IEND', const []));
  File(path).writeAsBytesSync(out.toBytes());
}

List<int> _chunk(String type, List<int> data) {
  final body = <int>[...type.codeUnits, ...data];
  final len = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, _crc32(body));
  return [...len.buffer.asUint8List(), ...body, ...crc.buffer.asUint8List()];
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >>> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

void main() {
  Directory('assets/icon').createSync(recursive: true);
  final sw = Stopwatch()..start();
  writePng('assets/icon/app_icon.png', render(true, 1.0));
  writePng('assets/icon/app_icon_foreground.png', render(false, 0.62));
  sw.stop();
  for (final f in ['app_icon.png', 'app_icon_foreground.png']) {
    final len = File('assets/icon/$f').lengthSync();
    print('wrote assets/icon/$f (${(len / 1024).toStringAsFixed(1)} KB)');
  }
  print('done in ${sw.elapsedMilliseconds} ms');
}

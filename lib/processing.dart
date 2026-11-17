// Image processing for the scanner: page detection, perspective flattening and
// the enhance filters. Values come from MECHANICS.md (read from the original's
// native scanner library); everything here is our own code and runs on-device.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

part 'scan_engine.dart';

/// The filters offered after a scan.
enum PageFilter { original, enhance, lighten, gray, bw }

extension PageFilterLabel on PageFilter {
  String get label => switch (this) {
        PageFilter.original => 'Original',
        PageFilter.enhance => 'Mejorar',
        PageFilter.lighten => 'Aclarar',
        PageFilter.gray => 'Grises',
        PageFilter.bw => 'B/N',
      };
}

/// Longest side kept for a page (estimated in MECHANICS.md).
const int maxPageSide = 2400;

/// An RGB picture as raw bytes, cheap to send between isolates.
class RgbImage {
  RgbImage(this.width, this.height, this.bytes);
  final int width;
  final int height;
  final Uint8List bytes; // r,g,b per pixel

  img.Image toImage() => img.Image.fromBytes(
      width: width, height: height, bytes: bytes.buffer, numChannels: 3);

  static RgbImage fromImage(img.Image src) {
    final rgb = src.convert(numChannels: 3, format: img.Format.uint8);
    return RgbImage(rgb.width, rgb.height,
        Uint8List.fromList(rgb.getBytes(order: img.ChannelOrder.rgb)));
  }
}

/// Decodes a photo, turns it upright (EXIF) and limits its size.
RgbImage? decodePhoto(Uint8List data) {
  final decoded = img.decodeImage(data);
  if (decoded == null) return null;
  var upright = img.bakeOrientation(decoded);
  final longSide = math.max(upright.width, upright.height);
  if (longSide > maxPageSide) {
    final scale = maxPageSide / longSide;
    upright = img.copyResize(upright,
        width: (upright.width * scale).round(),
        height: (upright.height * scale).round(),
        interpolation: img.Interpolation.average);
  }
  return RgbImage.fromImage(upright);
}

Uint8List encodeJpeg(RgbImage image, {int quality = 85}) =>
    Uint8List.fromList(img.encodeJpg(image.toImage(), quality: quality));

// Page detection lives in scan_engine.dart (same library).
// ---------------------------------------------------------------------------
// Perspective flattening
// ---------------------------------------------------------------------------

/// Cuts the quad (normalised corners TL,TR,BR,BL) out of [src] and flattens it
/// into a rectangle.
RgbImage flattenPage(RgbImage src, List<double> corners) {
  final pts = List.generate(4, (i) {
    return math.Point<double>(
        corners[i * 2].clamp(0.0, 1.0) * (src.width - 1),
        corners[i * 2 + 1].clamp(0.0, 1.0) * (src.height - 1));
  });
  double dist(math.Point<double> a, math.Point<double> b) => a.distanceTo(b);
  var outW = math.max(dist(pts[0], pts[1]), dist(pts[3], pts[2]));
  var outH = math.max(dist(pts[0], pts[3]), dist(pts[1], pts[2]));
  final longSide = math.max(outW, outH);
  if (longSide > maxPageSide) {
    outW *= maxPageSide / longSide;
    outH *= maxPageSide / longSide;
  }
  final w = math.max(16, outW.round());
  final h = math.max(16, outH.round());

  final hm = _homography([
    const math.Point(0.0, 0.0),
    math.Point(w - 1.0, 0.0),
    math.Point(w - 1.0, h - 1.0),
    math.Point(0.0, h - 1.0),
  ], pts);

  final out = Uint8List(w * h * 3);
  final sw = src.width, sh = src.height, sb = src.bytes;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final den = hm[6] * x + hm[7] * y + 1;
      final fx = (hm[0] * x + hm[1] * y + hm[2]) / den;
      final fy = (hm[3] * x + hm[4] * y + hm[5]) / den;
      final x0 = fx.floor().clamp(0, sw - 1);
      final y0 = fy.floor().clamp(0, sh - 1);
      final x1 = math.min(x0 + 1, sw - 1);
      final y1 = math.min(y0 + 1, sh - 1);
      final ax = (fx - x0).clamp(0.0, 1.0);
      final ay = (fy - y0).clamp(0.0, 1.0);
      final i00 = (y0 * sw + x0) * 3, i10 = (y0 * sw + x1) * 3;
      final i01 = (y1 * sw + x0) * 3, i11 = (y1 * sw + x1) * 3;
      final o = (y * w + x) * 3;
      for (var c = 0; c < 3; c++) {
        final top = sb[i00 + c] + (sb[i10 + c] - sb[i00 + c]) * ax;
        final bot = sb[i01 + c] + (sb[i11 + c] - sb[i01 + c]) * ax;
        out[o + c] = (top + (bot - top) * ay).round().clamp(0, 255);
      }
    }
  }
  return RgbImage(w, h, out);
}

/// Solves the 3x3 projective map (as 8 numbers) taking [from] to [to].
List<double> _homography(List<math.Point<double>> from, List<math.Point<double>> to) {
  final a = List.generate(8, (_) => List<double>.filled(9, 0));
  for (var i = 0; i < 4; i++) {
    final x = from[i].x, y = from[i].y, u = to[i].x, v = to[i].y;
    a[i * 2] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u];
    a[i * 2 + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v];
  }
  for (var col = 0; col < 8; col++) {
    var pivot = col;
    for (var r = col + 1; r < 8; r++) {
      if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
    }
    final tmp = a[col];
    a[col] = a[pivot];
    a[pivot] = tmp;
    final p = a[col][col];
    if (p.abs() < 1e-12) continue;
    for (var c = col; c < 9; c++) {
      a[col][c] /= p;
    }
    for (var r = 0; r < 8; r++) {
      if (r == col) continue;
      final f = a[r][col];
      if (f == 0) continue;
      for (var c = col; c < 9; c++) {
        a[r][c] -= f * a[col][c];
      }
    }
  }
  return List.generate(8, (i) => a[i][8]);
}

// ---------------------------------------------------------------------------
// Filters
// ---------------------------------------------------------------------------

/// Colour enhance curve (original 0x93044).
final Uint8List _colorLut = () {
  final lut = Uint8List(256);
  for (var v = 0; v < 256; v++) {
    if (v <= 32) {
      lut[v] = 0;
    } else if (v < 236) {
      lut[v] = math.min(255, (253.0 * math.pow((v - 32) / 203.0, 0.8333333) + 1.5).toInt());
    } else {
      lut[v] = 255;
    }
  }
  return lut;
}();

/// Black & white tone curve (original 0x91cc8, 0x92a20-0x92a80).
final Uint8List _bwLut = () {
  final lut = Uint8List(256);
  for (var v = 0; v < 256; v++) {
    if (v < 159) {
      lut[v] = 0;
    } else if (v > 230) {
      lut[v] = 255;
    } else {
      lut[v] = math.min(255, (253.0 * math.pow((v - 158) / 72.0, 0.5555556) + 1.5).toInt());
    }
  }
  return lut;
}();

Uint8List _toGray(RgbImage src) {
  final n = src.width * src.height;
  final g = Uint8List(n);
  final b = src.bytes;
  for (var p = 0; p < n; p++) {
    final i = p * 3;
    g[p] = ((b[i] * 299 + b[i + 1] * 587 + b[i + 2] * 114) ~/ 1000);
  }
  return g;
}

/// Low/high levels with the original's clip rule (0x91aa8).
(int, int) _clipLevels(Uint8List gray, int w, int h) {
  final hist = List<int>.filled(256, 0);
  for (var y = 0; y < h; y += 2) {
    for (var x = 0; x < w; x += 2) {
      hist[gray[y * w + x]]++;
    }
  }
  final clip = math.max(1, (w * h * 0.41 * (1 / 4096)).toInt());
  var low = 0, high = 255, acc = 0;
  for (var i = 0; i < 256; i++) {
    acc += hist[i];
    if (acc > clip) {
      low = i;
      break;
    }
  }
  acc = 0;
  for (var i = 255; i > low; i--) {
    acc += hist[i];
    if (acc > clip) {
      high = i;
      break;
    }
  }
  if (high <= low) high = math.min(255, low + 1);
  return (low, high);
}

RgbImage _grayToRgb(Uint8List g, int w, int h) {
  final out = Uint8List(w * h * 3);
  for (var p = 0; p < w * h; p++) {
    final v = g[p];
    out[p * 3] = v;
    out[p * 3 + 1] = v;
    out[p * 3 + 2] = v;
  }
  return RgbImage(w, h, out);
}

RgbImage applyFilter(RgbImage src, PageFilter filter) {
  switch (filter) {
    case PageFilter.original:
      return src;
    case PageFilter.enhance:
      // Magic colour: shadows out, paper white, colours kept, text sharp.
      return magicEnhance(src);
    case PageFilter.lighten:
      // Shadows out and paper evened, softer than Mejorar.
      final even = magicEnhance(src, strong: false);
      final gray = _toGray(even);
      final (low, high) = _clipLevels(gray, even.width, even.height);
      final lut = Uint8List(256);
      for (var v = 0; v < 256; v++) {
        final t = ((v - low) / (high - low)).clamp(0.0, 1.0);
        lut[v] = (255 * math.pow(t, 0.8)).round().clamp(0, 255);
      }
      final out = Uint8List(even.bytes.length);
      for (var i = 0; i < out.length; i++) {
        out[i] = lut[even.bytes[i]];
      }
      return RgbImage(even.width, even.height, out);
    case PageFilter.gray:
      final gray = _toGray(magicEnhance(src, strong: false));
      final (low, high) = _clipLevels(gray, src.width, src.height);
      for (var p = 0; p < gray.length; p++) {
        gray[p] = (((gray[p] - low) * 255) ~/ (high - low)).clamp(0, 255);
      }
      return _grayToRgb(gray, src.width, src.height);
    case PageFilter.bw:
      return _blackAndWhite(src);
  }
}

RgbImage _blackAndWhite(RgbImage src) {
  final w = src.width, h = src.height;
  final gray = _toGray(src);
  // Background: shrink, blur, grow back (estimated sizes).
  const bgSide = 64;
  final s = bgSide / math.max(w, h);
  final bw = math.max(4, (w * s).round()), bh = math.max(4, (h * s).round());
  var small = Float64List(bw * bh);
  // Box-average down-scale; a light percentile would also do, but paper is the
  // brightest large area so a max-of-mean keeps text out of the background.
  for (var y = 0; y < bh; y++) {
    final y0 = (y * h) ~/ bh, y1 = math.max(y0 + 1, ((y + 1) * h) ~/ bh);
    for (var x = 0; x < bw; x++) {
      final x0 = (x * w) ~/ bw, x1 = math.max(x0 + 1, ((x + 1) * w) ~/ bw);
      var maxV = 0;
      final stepY = math.max(1, (y1 - y0) ~/ 6), stepX = math.max(1, (x1 - x0) ~/ 6);
      for (var yy = y0; yy < y1; yy += stepY) {
        for (var xx = x0; xx < x1; xx += stepX) {
          final v = gray[yy * w + xx];
          if (v > maxV) maxV = v;
        }
      }
      small[y * bw + x] = maxV.toDouble();
    }
  }
  small = _gaussian(small, bw, bh, 2.0);
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final fy = (y + 0.5) * bh / h - 0.5;
    final y0 = fy.floor().clamp(0, bh - 1), y1 = math.min(y0 + 1, bh - 1);
    final ay = (fy - y0).clamp(0.0, 1.0);
    for (var x = 0; x < w; x++) {
      final fx = (x + 0.5) * bw / w - 0.5;
      final x0 = fx.floor().clamp(0, bw - 1), x1 = math.min(x0 + 1, bw - 1);
      final ax = (fx - x0).clamp(0.0, 1.0);
      final top = small[y0 * bw + x0] + (small[y0 * bw + x1] - small[y0 * bw + x0]) * ax;
      final bot = small[y1 * bw + x0] + (small[y1 * bw + x1] - small[y1 * bw + x0]) * ax;
      final back = math.max(1.0, top + (bot - top) * ay);
      final norm = (gray[y * w + x] * 255.0 / back).clamp(0, 255).toInt();
      out[y * w + x] = _bwLut[norm];
    }
  }
  return _grayToRgb(out, w, h);
}

Float64List _gaussian(Float64List src, int w, int h, double sigma) {
  final radius = (sigma * 3).ceil();
  final kernel = List<double>.generate(
      radius * 2 + 1, (i) => math.exp(-((i - radius) * (i - radius)) / (2 * sigma * sigma)));
  final sum = kernel.reduce((a, b) => a + b);
  for (var i = 0; i < kernel.length; i++) {
    kernel[i] /= sum;
  }
  final tmp = Float64List(w * h);
  final out = Float64List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      double acc = 0;
      for (var k = -radius; k <= radius; k++) {
        acc += src[y * w + (x + k).clamp(0, w - 1)] * kernel[k + radius];
      }
      tmp[y * w + x] = acc;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      double acc = 0;
      for (var k = -radius; k <= radius; k++) {
        acc += tmp[(y + k).clamp(0, h - 1) * w + x] * kernel[k + radius];
      }
      out[y * w + x] = acc;
    }
  }
  return out;
}

/// Rotates by quarter turns clockwise.
RgbImage rotateQuarter(RgbImage src, int turns) {
  final t = ((turns % 4) + 4) % 4;
  if (t == 0) return src;
  return RgbImage.fromImage(img.copyRotate(src.toImage(), angle: 90 * t));
}

/// Full page job: flatten, rotate, filter, encode. Runs inside an isolate.
class PageJob {
  PageJob(this.source, this.corners, this.rotation, this.filter, this.quality);
  final Uint8List source; // encoded original photo
  final List<double> corners;
  final int rotation;
  final PageFilter filter;
  final int quality;
}

Uint8List? runPageJob(PageJob job) {
  final src = decodePhoto(job.source);
  if (src == null) return null;
  var page = flattenPage(src, job.corners);
  page = rotateQuarter(page, job.rotation);
  page = applyFilter(page, job.filter);
  return encodeJpeg(page, quality: job.quality);
}

/// Small preview of a filter on an already flattened page.
Uint8List previewFilter((Uint8List, PageFilter) args) {
  final decoded = img.decodeImage(args.$1)!;
  final small = img.copyResize(decoded, width: math.min(decoded.width, 900));
  return encodeJpeg(applyFilter(RgbImage.fromImage(small), args.$2), quality: 80);
}

// "Looks really scanned": page detection, the magic enhance (shadow removal +
// paper whitening + text sharpening) and the blurry-photo check.
//
// What the original does (see MECHANICS.md):
// - Magic enhance (libmagicenhancer.so, scanet::enhance 0x25e00): a small
//   network predicts, per area of the page, a gain and an offset that are
//   applied to every pixel as out = in·gain/32 + 2·offset − 255
//   (scanet::enhance_pix 0x1d0b4), then colours are boosted
//   (scanet::enhance_color 0x21dec) and text is sharpened
//   (scanet::sharpEnhance 0x253f4, called with 4).
// - Blur (libpagescanner.so, getBlurValue 0xda910): grey, half size,
//   Laplacian, variance.
// - Page edges: a page mask plus candidate straight lines (findCandidateLines,
//   adjustRect), not the corners of a blob.
//
// We can't ship their network, so the gain/offset maps are computed here from
// the photo itself: the local paper brightness gives the gain, the global
// paper colour keeps colours true, and the original's colour curve sets the
// black and white points.
part of 'processing.dart';

// ───────────────────────── Magic enhance ─────────────────────────

/// Shadow-free, white-paper, sharp-text version of a flattened page.
RgbImage magicEnhance(RgbImage src, {bool strong = true}) {
  final w = src.width, h = src.height, b = src.bytes;
  final n = w * h;
  final lum = Uint8List(n);
  for (var p = 0; p < n; p++) {
    final i = p * 3;
    lum[p] = (b[i] * 299 + b[i + 1] * 587 + b[i + 2] * 114) ~/ 1000;
  }

  // 1. Paper brightness per area (the "gain" map): a high percentile per
  //    block, spread over dark blocks (text, pictures), smoothed.
  final block = math.max(8, (math.min(w, h) / 22).round());
  final gw = (w + block - 1) ~/ block, gh = (h + block - 1) ~/ block;
  var paper = Float64List(gw * gh);
  final hist = Int32List(256);
  for (var by = 0; by < gh; by++) {
    for (var bx = 0; bx < gw; bx++) {
      hist.fillRange(0, 256, 0);
      var count = 0;
      final y1 = math.min(h, (by + 1) * block), x1 = math.min(w, (bx + 1) * block);
      for (var y = by * block; y < y1; y += 2) {
        for (var x = bx * block; x < x1; x += 2) {
          hist[lum[y * w + x]]++;
          count++;
        }
      }
      // 90th percentile = the paper between letters.
      var acc = 0, v = 255;
      final target = count * 0.10;
      for (var i = 255; i >= 0; i--) {
        acc += hist[i];
        if (acc >= target) {
          v = i;
          break;
        }
      }
      paper[by * gw + bx] = v.toDouble();
    }
  }
  for (var k = 0; k < 3; k++) {
    paper = _fixInkBlocks(paper, gw, gh); // blocks full of ink, not shadow
  }
  paper = _gaussian(paper, gw, gh, 1.2);

  // 2. Paper colour per area (the original's maps are per channel): a lamp
  //    makes one corner yellow and another blue, so each area gets its own
  //    white balance, measured on its paper pixels only and smoothed, so
  //    logos and stamps keep their colour.
  final nb = gw * gh;
  final sr = Float64List(nb), sg = Float64List(nb), sbb = Float64List(nb), sl = Float64List(nb);
  for (var y = 0; y < h; y += 2) {
    final int by = math.min(gh - 1, y ~/ block);
    for (var x = 0; x < w; x += 2) {
      final p = y * w + x;
      final int k = by * gw + math.min<int>(gw - 1, x ~/ block);
      if (lum[p] >= paper[k] * 0.88) {
        final i = p * 3;
        sr[k] += b[i];
        sg[k] += b[i + 1];
        sbb[k] += b[i + 2];
        sl[k] += lum[p];
      }
    }
  }
  double tr = 0, tg = 0, tb = 0, tl = 0;
  for (var k = 0; k < nb; k++) {
    tr += sr[k];
    tg += sg[k];
    tb += sbb[k];
    tl += sl[k];
  }
  final gr = tl > 0 ? tr / tl : 1.0, gg = tl > 0 ? tg / tl : 1.0, gbl = tl > 0 ? tb / tl : 1.0;
  var mr = Float64List(nb), mg = Float64List(nb), mb = Float64List(nb);
  for (var k = 0; k < nb; k++) {
    // Little paper seen here (a picture, a dark heading): use the page's.
    final ok = sl[k] > block * block * 0.08 * 128;
    mr[k] = ok ? sr[k] / sl[k] : gr;
    mg[k] = ok ? sg[k] / sl[k] : gg;
    mb[k] = ok ? sbb[k] / sl[k] : gbl;
  }
  mr = _gaussian(mr, gw, gh, 1.6);
  mg = _gaussian(mg, gw, gh, 1.6);
  mb = _gaussian(mb, gw, gh, 1.6);

  // 3. Apply the per-pixel gain (paper → white), then the original's colour
  //    curve (0x93044) for the black and white points, then a colour boost.
  final out = Uint8List(n * 3);
  final push = strong ? 1.04 : 1.0;
  final sat = strong ? 1.25 : 1.1; // estimated (enhance_color 0x21dec)
  for (var y = 0; y < h; y++) {
    final gy = (y + 0.5) / block - 0.5;
    for (var x = 0; x < w; x++) {
      final p = y * w + x, i = p * 3;
      final gx = (x + 0.5) / block - 0.5;
      final bg = math.max(24.0, _bilinear(paper, gw, gh, gx, gy));
      final rr = math.max(0.2, _bilinear(mr, gw, gh, gx, gy));
      final rg = math.max(0.2, _bilinear(mg, gw, gh, gx, gy));
      final rb = math.max(0.2, _bilinear(mb, gw, gh, gx, gy));
      final kr = 255.0 * push / (bg * rr), kg = 255.0 * push / (bg * rg), kb = 255.0 * push / (bg * rb);
      var r = b[i] * kr, g = b[i + 1] * kg, bl = b[i + 2] * kb;
      final m = (r + g + bl) / 3;
      r = m + (r - m) * sat;
      g = m + (g - m) * sat;
      bl = m + (bl - m) * sat;
      out[i] = strong ? _inkLut[_colorLut[r.round().clamp(0, 255)]] : r.round().clamp(0, 255);
      out[i + 1] = strong ? _inkLut[_colorLut[g.round().clamp(0, 255)]] : g.round().clamp(0, 255);
      out[i + 2] = strong ? _inkLut[_colorLut[bl.round().clamp(0, 255)]] : bl.round().clamp(0, 255);
    }
  }
  final flat = RgbImage(w, h, out);
  return strong ? sharpEnhance(flat, 4) : flat;
}

/// Darker, bolder ink with the paper left white: the original's "Mejorar"
/// shows near-black text and saturated stamps (seen in its video), so
/// everything under 235 is pushed down by a 1.3 power (estimated).
final Uint8List _inkLut = () {
  final lut = Uint8List(256);
  for (var v = 0; v < 256; v++) {
    lut[v] = v >= 235 ? 255 : (255 * math.pow(v / 235, 1.3)).round().clamp(0, 255);
  }
  return lut;
}();

/// A block much darker than the median of its neighbours is ink (a heading,
/// a chart, a photo), not light falling off: give it its neighbours' paper
/// level. Shadows are wide, so their neighbours are dark too and they stay.
Float64List _fixInkBlocks(Float64List g, int w, int h) {
  final out = Float64List(w * h);
  final nb = <double>[];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      nb.clear();
      for (var dy = -1; dy <= 1; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx;
          if ((dx == 0 && dy == 0) || xx < 0 || xx >= w) continue;
          nb.add(g[yy * w + xx]);
        }
      }
      nb.sort();
      final med = nb[nb.length ~/ 2];
      final v = g[y * w + x];
      out[y * w + x] = v < med - 20 ? med : v;
    }
  }
  return out;
}

double _bilinear(Float64List g, int w, int h, double fx, double fy) {
  final x0 = fx.floor().clamp(0, w - 1), y0 = fy.floor().clamp(0, h - 1);
  final x1 = math.min(x0 + 1, w - 1), y1 = math.min(y0 + 1, h - 1);
  final ax = (fx - x0).clamp(0.0, 1.0), ay = (fy - y0).clamp(0.0, 1.0);
  final top = g[y0 * w + x0] + (g[y0 * w + x1] - g[y0 * w + x0]) * ax;
  final bot = g[y1 * w + x0] + (g[y1 * w + x1] - g[y1 * w + x0]) * ax;
  return top + (bot - top) * ay;
}

/// The original's text sharpening (scanet::sharpEnhance 0x253f4): compare
/// each pixel with a box-blurred copy; details darker than their
/// surroundings by more than 20 are doubled, by 10..20 kept, smaller ones
/// halved.
RgbImage sharpEnhance(RgbImage src, int base) {
  final w = src.width, h = src.height, s = src.bytes;
  final minSide = math.min(w, h);
  final k = ((base << (minSide > 400 ? 1 : 0)) << (minSide > 1600 ? 1 : 0)) - 1;
  final r = k ~/ 2;
  final out = Uint8List(s.length);
  // Integral image per channel.
  final stride = w + 1;
  final integ = Int32List(stride * (h + 1));
  for (var c = 0; c < 3; c++) {
    for (var y = 0; y < h; y++) {
      var row = 0;
      for (var x = 0; x < w; x++) {
        row += s[(y * w + x) * 3 + c];
        integ[(y + 1) * stride + x + 1] = integ[y * stride + x + 1] + row;
      }
    }
    for (var y = 0; y < h; y++) {
      final y0 = math.max(0, y - r), y1 = math.min(h, y + r + 1);
      for (var x = 0; x < w; x++) {
        final x0 = math.max(0, x - r), x1 = math.min(w, x + r + 1);
        final sum = integ[y1 * stride + x1] - integ[y0 * stride + x1] -
            integ[y1 * stride + x0] + integ[y0 * stride + x0];
        final blur = sum ~/ ((y1 - y0) * (x1 - x0));
        final i = (y * w + x) * 3 + c;
        final d = s[i] - blur;
        final adj = d < -20 ? d * 2 : (d < -9 ? d : d >> 1);
        out[i] = (s[i] + adj).clamp(0, 255);
      }
    }
  }
  return RgbImage(w, h, out);
}

// ───────────────────────── Blurry photo check ─────────────────────────

/// Sharpness of a page like the original's getBlurValue (0xda910): variance
/// of the Laplacian of the grey picture, measured at a fixed size so photos
/// from any phone compare. Pages with almost nothing on them return null
/// (no detail to judge).
double? blurScore(RgbImage page) {
  // Never enlarge: that would hide detail and make sharp photos look soft.
  final target = math.min(800, math.max(page.width, page.height));
  final scale = target / math.max(page.width, page.height);
  final w = math.max(16, (page.width * scale).round());
  final h = math.max(16, (page.height * scale).round());
  final g = Float64List(w * h);
  // Box-averaged grey at the target size.
  for (var y = 0; y < h; y++) {
    final sy0 = (y * page.height) ~/ h, sy1 = math.max(sy0 + 1, ((y + 1) * page.height) ~/ h);
    for (var x = 0; x < w; x++) {
      final sx0 = (x * page.width) ~/ w, sx1 = math.max(sx0 + 1, ((x + 1) * page.width) ~/ w);
      var sum = 0, cnt = 0;
      for (var yy = sy0; yy < sy1; yy++) {
        for (var xx = sx0; xx < sx1; xx++) {
          final i = (yy * page.width + xx) * 3;
          sum += (page.bytes[i] * 299 + page.bytes[i + 1] * 587 + page.bytes[i + 2] * 114) ~/ 1000;
          cnt++;
        }
      }
      g[y * w + x] = sum / cnt;
    }
  }
  // Inner 90 % only (edges of the crop may show the table).
  final mx = w ~/ 20, my = h ~/ 20;
  double s = 0, s2 = 0, gs = 0, gs2 = 0;
  var cnt = 0;
  for (var y = math.max(1, my); y < h - math.max(1, my); y++) {
    for (var x = math.max(1, mx); x < w - math.max(1, mx); x++) {
      final p = y * w + x;
      final lap = g[p - 1] + g[p + 1] + g[p - w] + g[p + w] - 4 * g[p];
      s += lap;
      s2 += lap * lap;
      gs += g[p];
      gs2 += g[p] * g[p];
      cnt++;
    }
  }
  if (cnt == 0) return null;
  final contrast = math.sqrt(math.max(0, gs2 / cnt - (gs / cnt) * (gs / cnt)));
  if (contrast < 4) return null; // blank page: can't tell
  final mean = s / cnt;
  return s2 / cnt - mean * mean;
}

/// Below this sharpness a photo is treated as moved/blurry (estimated from
/// the sample photos; the original compares frames with each other instead).
const double blurThreshold = 30;

bool isBlurry(RgbImage page) {
  final s = blurScore(page);
  return s != null && s < blurThreshold;
}

// ───────────────────────── Page detection ─────────────────────────

const _fallbackInset = 0.045;
const List<double> _fallback = [
  _fallbackInset, _fallbackInset, 1 - _fallbackInset, _fallbackInset,
  1 - _fallbackInset, 1 - _fallbackInset, _fallbackInset, 1 - _fallbackInset,
];

/// Finds the page and returns its 4 corners, normalised to 0..1, in order
/// top-left, top-right, bottom-right, bottom-left. Works in dim light: the
/// small copy is averaged (less noise) and levelled, thin bridges to the
/// background are cut, and each side is a straight line fitted to the
/// page's outline, so a dark corner can't pull a corner outwards.
List<double> detectCorners(RgbImage src) {
  const target = 300;
  final scale = target / math.max(src.width, src.height);
  final w = math.max(16, (src.width * scale).round());
  final h = math.max(16, (src.height * scale).round());
  final n = w * h;

  // Area-averaged small copy.
  final small = Float64List(n * 3);
  for (var y = 0; y < h; y++) {
    final sy0 = (y * src.height) ~/ h, sy1 = math.max(sy0 + 1, ((y + 1) * src.height) ~/ h);
    final stepY = math.max(1, (sy1 - sy0) ~/ 3);
    for (var x = 0; x < w; x++) {
      final sx0 = (x * src.width) ~/ w, sx1 = math.max(sx0 + 1, ((x + 1) * src.width) ~/ w);
      final stepX = math.max(1, (sx1 - sx0) ~/ 3);
      double r = 0, g = 0, b = 0;
      var cnt = 0;
      for (var yy = sy0; yy < sy1; yy += stepY) {
        for (var xx = sx0; xx < sx1; xx += stepX) {
          final i = (yy * src.width + xx) * 3;
          r += src.bytes[i];
          g += src.bytes[i + 1];
          b += src.bytes[i + 2];
          cnt++;
        }
      }
      final o = (y * w + x) * 3;
      small[o] = r / cnt;
      small[o + 1] = g / cnt;
      small[o + 2] = b / cnt;
    }
  }

  // Level each channel (1 % / 99 %) so dim photos get full contrast.
  for (var c = 0; c < 3; c++) {
    final hist = Int32List(256);
    for (var p = 0; p < n; p++) {
      hist[small[p * 3 + c].round().clamp(0, 255)]++;
    }
    var lo = 0, hi = 255, acc = 0;
    for (var i = 0; i < 256; i++) {
      acc += hist[i];
      if (acc > n * 0.01) {
        lo = i;
        break;
      }
    }
    acc = 0;
    for (var i = 255; i >= 0; i--) {
      acc += hist[i];
      if (acc > n * 0.01) {
        hi = i;
        break;
      }
    }
    final span = math.max(16, hi - lo);
    for (var p = 0; p < n; p++) {
      small[p * 3 + c] = ((small[p * 3 + c] - lo) * 255 / span).clamp(0, 255);
    }
  }

  // Smooth (noise in dim light).
  for (var c = 0; c < 3; c++) {
    final ch = Float64List(n);
    for (var p = 0; p < n; p++) {
      ch[p] = small[p * 3 + c];
    }
    final sm = _gaussian(ch, w, h, 1.2);
    for (var p = 0; p < n; p++) {
      small[p * 3 + c] = sm[p];
    }
  }

  // Candidate 1 (like the original's findCandidateLines + adjustRect):
  // straight edge lines, every top/bottom/left/right combination scored by
  // how much of each side really is an edge with paper on one side.
  final gray = Float64List(n);
  for (var p = 0; p < n; p++) {
    gray[p] = 0.299 * small[p * 3] + 0.587 * small[p * 3 + 1] + 0.114 * small[p * 3 + 2];
  }
  final edges = _EdgeMap.build(small, w, h);
  List<double>? best;
  var bestScore = 0.0;
  final byLines = _lineQuad(edges, gray, w, h);
  if (byLines != null) {
    best = byLines.$1;
    bestScore = byLines.$2;
  }
  // Candidate 2: the page as a coloured region (helps when an edge is faint).
  final byRegion = _regionQuad(small, w, h);
  if (byRegion != null) {
    final s = _quadScore(byRegion, edges, gray, w, h, const [false, false, false, false]);
    if (s > bestScore * 1.08) {
      best = byRegion;
      bestScore = s;
    }
  }
  if (best == null || bestScore < 0.42) return List.of(_fallback);
  // Final touch: least-squares line through the edge pixels along each side.
  final refined = _fitCornersPx(edges.xs, edges.ys, best, w, h, const [0.012, 0.008]);
  return _finish(_quadScore(refined, edges, gray, w, h, const [false, false, false, false]) >=
          bestScore * 0.95
      ? refined
      : best, w, h);
}

/// The region method from before: pass 1 against one table colour, pass 2
/// against a smooth table model (dim light), then lines through the outline.
List<double>? _regionQuad(Float64List small, int w, int h) {
  final first = _pageRegion(small, w, h, null);
  if (first == null) return null;
  final model = _backgroundModel(small, w, h, _dilate(first, w, h, math.max(2, w ~/ 40)));
  final region = (model == null ? null : _pageRegion(small, w, h, model)) ?? first;

  // Outline points and a first guess from the extreme points.
  final xs = <double>[], ys = <double>[];
  var tl = 1 << 30, br2 = -(1 << 30), tr = -(1 << 30), bl = 1 << 30;
  var c = List<double>.filled(8, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = y * w + x;
      if (region[p] == 0) continue;
      final edge = x == 0 || y == 0 || x == w - 1 || y == h - 1 ||
          region[p - 1] == 0 || region[p + 1] == 0 || region[p - w] == 0 || region[p + w] == 0;
      if (edge) {
        xs.add(x.toDouble());
        ys.add(y.toDouble());
      }
      final s = x + y, d = x - y;
      if (s < tl) { tl = s; c[0] = x.toDouble(); c[1] = y.toDouble(); }
      if (d > tr) { tr = d; c[2] = x.toDouble(); c[3] = y.toDouble(); }
      if (s > br2) { br2 = s; c[4] = x.toDouble(); c[5] = y.toDouble(); }
      if (d < bl) { bl = d; c[6] = x.toDouble(); c[7] = y.toDouble(); }
    }
  }
  final px = _fitCornersPx(xs, ys, c, w, h);
  final norm = [for (var k = 0; k < 4; k++) ...[px[k * 2] / (w - 1), px[k * 2 + 1] / (h - 1)]];
  if (_quadArea(norm) < 0.08 || !_isConvex(norm)) return null;
  return px;
}

// ───────────────────────── Edge lines ─────────────────────────

/// Thin edges of the small picture: strength, direction, and a 1-px
/// dilated copy for checking sides.
class _EdgeMap {
  _EdgeMap(this.w, this.h, this.mag, this.dir, this.edge, this.near, this.xs, this.ys);
  final int w, h;
  final Float64List mag; // gradient strength
  final Float64List dir; // gradient angle (radians)
  final Uint8List edge; // thin edge pixels
  final Uint8List near; // within 1 px of an edge
  final List<double> xs, ys;

  static _EdgeMap build(Float64List small, int w, int h) {
    final n = w * h;
    final mag = Float64List(n), dir = Float64List(n);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        var best = 0.0, bgx = 0.0, bgy = 0.0;
        for (var c = 0; c < 3; c++) {
          double v(int xx, int yy) => small[(yy * w + xx) * 3 + c];
          final gx = (v(x + 1, y - 1) + 2 * v(x + 1, y) + v(x + 1, y + 1)) -
              (v(x - 1, y - 1) + 2 * v(x - 1, y) + v(x - 1, y + 1));
          final gy = (v(x - 1, y + 1) + 2 * v(x, y + 1) + v(x + 1, y + 1)) -
              (v(x - 1, y - 1) + 2 * v(x, y - 1) + v(x + 1, y - 1));
          final m = gx * gx + gy * gy;
          if (m > best) {
            best = m;
            bgx = gx;
            bgy = gy;
          }
        }
        final p = y * w + x;
        mag[p] = math.sqrt(best);
        dir[p] = math.atan2(bgy, bgx);
      }
    }
    // Threshold: the strongest ~12 % of gradients, never below a floor.
    final sorted = Float64List.fromList(mag)..sort();
    final thr = math.max(40.0, sorted[(n * 0.88).floor()]);
    final edge = Uint8List(n);
    final xs = <double>[], ys = <double>[];
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final p = y * w + x;
        final m = mag[p];
        if (m < thr) continue;
        // Non-maximum suppression across the edge.
        final a = dir[p];
        final dx = math.cos(a).round(), dy = math.sin(a).round();
        if (m < mag[(y + dy) * w + x + dx] || m < mag[(y - dy) * w + x - dx]) continue;
        edge[p] = 1;
        xs.add(x.toDouble());
        ys.add(y.toDouble());
      }
    }
    final near = Uint8List(n);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (edge[y * w + x] == 0) continue;
        for (var dy = -1; dy <= 1; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx >= 0 && xx < w) near[yy * w + xx] = 1;
          }
        }
      }
    }
    return _EdgeMap(w, h, mag, dir, edge, near, xs, ys);
  }
}

/// A line in normal form x·cosθ + y·sinθ = ρ; [border] marks a picture edge
/// (the page runs off the photo there).
class _Line {
  _Line(this.theta, this.rho, {this.border = false});
  final double theta, rho;
  final bool border;
  double get ct => math.cos(theta);
  double get st => math.sin(theta);
}

(double, double)? _cross(_Line a, _Line b) {
  final det = a.ct * b.st - a.st * b.ct;
  if (det.abs() < 1e-6) return null;
  return ((a.rho * b.st - a.st * b.rho) / det, (a.ct * b.rho - a.rho * b.ct) / det);
}

/// Hough lines from the edge pixels (each pixel votes only near its own
/// direction), strongest first, with neighbours suppressed.
List<_Line> _houghLines(_EdgeMap e, int maxLines) {
  final w = e.w, h = e.h;
  final diag = math.sqrt(w * w + h * h.toDouble()).ceil();
  const nT = 180;
  final nR = diag * 2 + 1;
  final acc = Int32List(nT * nR);
  final cosT = Float64List(nT), sinT = Float64List(nT);
  for (var t = 0; t < nT; t++) {
    cosT[t] = math.cos(t * math.pi / nT);
    sinT[t] = math.sin(t * math.pi / nT);
  }
  for (var i = 0; i < e.xs.length; i++) {
    final x = e.xs[i], y = e.ys[i];
    var a = e.dir[y.toInt() * w + x.toInt()];
    if (a < 0) a += math.pi;
    final t0 = (a / math.pi * nT).round();
    for (var dt = -6; dt <= 6; dt++) {
      final t = (t0 + dt) % nT;
      final tt = t < 0 ? t + nT : t;
      final r = (x * cosT[tt] + y * sinT[tt]).round() + diag;
      acc[tt * nR + r]++;
    }
  }
  final minVotes = (math.min(w, h) * 0.18).round();
  final lines = <_Line>[];
  final used = Uint8List(nT * nR);
  for (var k = 0; k < maxLines; k++) {
    var bestV = 0, bestI = -1;
    for (var i = 0; i < acc.length; i++) {
      if (used[i] == 0 && acc[i] > bestV) {
        bestV = acc[i];
        bestI = i;
      }
    }
    if (bestI < 0 || bestV < minVotes) break;
    final t = bestI ~/ nR, r = bestI % nR;
    lines.add(_Line(t * math.pi / nT, (r - diag).toDouble()));
    // Suppress the neighbourhood (±5°, ±7 px).
    for (var dt = -5; dt <= 5; dt++) {
      var tt = t + dt;
      var rr0 = r;
      if (tt < 0) {
        tt += nT;
        rr0 = 2 * diag - r;
      } else if (tt >= nT) {
        tt -= nT;
        rr0 = 2 * diag - r;
      }
      for (var dr = -7; dr <= 7; dr++) {
        final rr = rr0 + dr;
        if (rr >= 0 && rr < nR) used[tt * nR + rr] = 1;
      }
    }
  }
  return lines;
}

/// Best quad from the lines: (pixel corners TL,TR,BR,BL, score).
(List<double>, double)? _lineQuad(_EdgeMap e, Float64List gray, int w, int h) {
  final lines = _houghLines(e, 26);
  final hor = <_Line>[], ver = <_Line>[];
  for (final l in lines) {
    // θ near 90° → the line itself runs left-right.
    final deg = l.theta * 180 / math.pi;
    if ((deg - 90).abs() < 40) {
      hor.add(l);
    } else if (deg < 40 || deg > 140) {
      ver.add(l);
    }
  }
  if (hor.length > 12) hor.removeRange(12, hor.length);
  if (ver.length > 12) ver.removeRange(12, ver.length);
  hor..add(_Line(math.pi / 2, 0, border: true))..add(_Line(math.pi / 2, h - 1.0, border: true));
  ver..add(_Line(0, 0, border: true))..add(_Line(0, w - 1.0, border: true));

  double yAt(_Line l, double x) => (l.rho - x * l.ct) / l.st;
  double xAt(_Line l, double y) => (l.rho - y * l.st) / l.ct;

  List<double>? bestC;
  var bestS = 0.0;
  final minSide = math.min(w, h) * 0.2;
  for (var i = 0; i < hor.length; i++) {
    for (var j = i + 1; j < hor.length; j++) {
      var top = hor[i], bot = hor[j];
      if (yAt(top, w / 2) > yAt(bot, w / 2)) {
        final t = top;
        top = bot;
        bot = t;
      }
      if (yAt(bot, w / 2) - yAt(top, w / 2) < minSide) continue;
      for (var k = 0; k < ver.length; k++) {
        for (var m = k + 1; m < ver.length; m++) {
          var left = ver[k], right = ver[m];
          if (xAt(left, h / 2) > xAt(right, h / 2)) {
            final t = left;
            left = right;
            right = t;
          }
          if (xAt(right, h / 2) - xAt(left, h / 2) < minSide) continue;
          final tl = _cross(top, left), tr = _cross(top, right);
          final br = _cross(bot, right), bl = _cross(bot, left);
          if (tl == null || tr == null || br == null || bl == null) continue;
          final c = [tl.$1, tl.$2, tr.$1, tr.$2, br.$1, br.$2, bl.$1, bl.$2];
          var inside = true;
          for (var q = 0; q < 4; q++) {
            if (c[q * 2] < -0.04 * w || c[q * 2] > 1.04 * w || c[q * 2 + 1] < -0.04 * h ||
                c[q * 2 + 1] > 1.04 * h) {
              inside = false;
              break;
            }
          }
          if (!inside) continue;
          final norm = [for (var q = 0; q < 4; q++) ...[c[q * 2] / w, c[q * 2 + 1] / h]];
          if (_quadArea(norm) < 0.1 || !_isConvex(norm)) continue;
          final s = _quadScore(c, e, gray, w, h, [top.border, right.border, bot.border, left.border]);
          if (s > bestS) {
            bestS = s;
            bestC = c;
          }
        }
      }
    }
  }
  if (bestC == null) return null;
  for (var q = 0; q < 4; q++) {
    bestC[q * 2] = bestC[q * 2].clamp(0, w - 1.0);
    bestC[q * 2 + 1] = bestC[q * 2 + 1].clamp(0, h - 1.0);
  }
  return (bestC, bestS);
}

/// How much the quad looks like a page: for each side, the share of points
/// that lie on an edge running the same way, and the share with a clear
/// brightness step across it (paper on one side). Bigger pages win ties.
/// [border] sides lie on the photo's edge (page runs off): neutral score.
double _quadScore(List<double> c, _EdgeMap e, Float64List gray, int w, int h, List<bool> border) {
  var total = 0.0, perim = 0.0, weakest = 1.0;
  final cx = (c[0] + c[2] + c[4] + c[6]) / 4, cy = (c[1] + c[3] + c[5] + c[7]) / 4;
  for (var s = 0; s < 4; s++) {
    final ax = c[s * 2], ay = c[s * 2 + 1];
    final bx = c[((s + 1) % 4) * 2], by = c[((s + 1) % 4) * 2 + 1];
    final len = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
    if (len < 4) return 0;
    double sideScore;
    if (border[s]) {
      sideScore = 0.5;
    } else {
      final ux = (bx - ax) / len, uy = (by - ay) / len;
      // Normal pointing into the page.
      var nx = -uy, ny = ux;
      final mx = (ax + bx) / 2, my = (ay + by) / 2;
      if ((cx - mx) * nx + (cy - my) * ny < 0) {
        nx = -nx;
        ny = -ny;
      }
      final sideAngle = math.atan2(ny, nx);
      var samples = 0, onEdge = 0, step = 0, sign = 0;
      final count = math.max(8, (len / 2).round());
      for (var k = 1; k < count; k++) {
        final t = k / count;
        final x = ax + (bx - ax) * t, y = ay + (by - ay) * t;
        final xi = x.round(), yi = y.round();
        if (xi < 3 || yi < 3 || xi >= w - 3 || yi >= h - 3) continue;
        samples++;
        final p = yi * w + xi;
        if (e.near[p] == 1) {
          // Gradient across the side (either way round).
          final d = (e.dir[p] - sideAngle).abs() % math.pi;
          final diff = math.min(d, math.pi - d);
          if (diff < 0.35) onEdge++;
        }
        final ix = (x + nx * 3).round(), iy = (y + ny * 3).round();
        final ox = (x - nx * 3).round(), oy = (y - ny * 3).round();
        if (ix < 0 || iy < 0 || ix >= w || iy >= h || ox < 0 || oy < 0 || ox >= w || oy >= h) continue;
        final diff = gray[iy * w + ix] - gray[oy * w + ox];
        if (diff.abs() > 14) {
          step++;
          sign += diff > 0 ? 1 : -1;
        }
      }
      if (samples < 4) {
        sideScore = 0.5;
      } else {
        final edgeFrac = onEdge / samples;
        // A step that's mostly the same way round: one side is the page.
        final stepFrac = step == 0 ? 0.0 : (step / samples) * (sign.abs() / step);
        sideScore = 0.6 * edgeFrac + 0.4 * stepFrac;
      }
    }
    weakest = math.min(weakest, sideScore);
    total += sideScore * len;
    perim += len;
  }
  if (weakest < 0.22) return 0;
  final mean = total / perim;
  final norm = [for (var q = 0; q < 4; q++) ...[c[q * 2] / w, c[q * 2 + 1] / h]];
  return mean * (0.75 + 0.25 * math.sqrt(_quadArea(norm))) + 0.15 * weakest;
}

/// Expected table colour at every pixel: a quadratic surface per channel
/// fitted to the pixels outside [page]. Null when there's too little table.
Float64List? _backgroundModel(Float64List small, int w, int h, Uint8List page) {
  // Normal equations for a + bx + cy + dx² + ey² + fxy.
  final ata = List.generate(6, (_) => Float64List(6));
  final atb = List.generate(3, (_) => Float64List(6));
  var count = 0;
  final f = Float64List(6);
  for (var y = 0; y < h; y += 2) {
    for (var x = 0; x < w; x += 2) {
      final p = y * w + x;
      if (page[p] == 1) continue;
      final u = x / w - 0.5, v = y / h - 0.5;
      f[0] = 1; f[1] = u; f[2] = v; f[3] = u * u; f[4] = v * v; f[5] = u * v;
      for (var i = 0; i < 6; i++) {
        for (var j = 0; j < 6; j++) {
          ata[i][j] += f[i] * f[j];
        }
        for (var c = 0; c < 3; c++) {
          atb[c][i] += f[i] * small[p * 3 + c];
        }
      }
      count++;
    }
  }
  if (count < w * h / 40) return null;
  final coef = <Float64List>[];
  for (var c = 0; c < 3; c++) {
    final s = _solve(ata, atb[c]);
    if (s == null) return null;
    coef.add(s);
  }
  final out = Float64List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final u = x / w - 0.5, v = y / h - 0.5;
      for (var c = 0; c < 3; c++) {
        final k = coef[c];
        out[(y * w + x) * 3 + c] =
            k[0] + k[1] * u + k[2] * v + k[3] * u * u + k[4] * v * v + k[5] * u * v;
      }
    }
  }
  return out;
}

Float64List? _solve(List<Float64List> a0, Float64List b0) {
  final n = b0.length;
  final a = [for (final r in a0) Float64List.fromList(r)];
  final b = Float64List.fromList(b0);
  for (var i = 0; i < n; i++) {
    a[i][i] += 1e-6; // keep it solvable
  }
  for (var col = 0; col < n; col++) {
    var piv = col;
    for (var r = col + 1; r < n; r++) {
      if (a[r][col].abs() > a[piv][col].abs()) piv = r;
    }
    if (a[piv][col].abs() < 1e-12) return null;
    final t = a[col]; a[col] = a[piv]; a[piv] = t;
    final tb = b[col]; b[col] = b[piv]; b[piv] = tb;
    for (var r = 0; r < n; r++) {
      if (r == col) continue;
      final fct = a[r][col] / a[col][col];
      for (var c = col; c < n; c++) {
        a[r][c] -= fct * a[col][c];
      }
      b[r] -= fct * b[col];
    }
  }
  return Float64List.fromList([for (var i = 0; i < n; i++) b[i] / a[i][i]]);
}

/// The page as a filled region: pixels far from the table colour (one colour,
/// or [model] per pixel), thin bridges cut, largest piece, holes filled.
Uint8List? _pageRegion(Float64List small, int w, int h, Float64List? model) {
  final n = w * h;
  double br = 0, bg = 0, bb = 0;
  if (model == null) {
    final band = math.max(2, (math.min(w, h) * 0.05).round());
    final rs = <double>[], gs = <double>[], bs = <double>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (x < band || y < band || x >= w - band || y >= h - band) {
          final i = (y * w + x) * 3;
          rs.add(small[i]);
          gs.add(small[i + 1]);
          bs.add(small[i + 2]);
        }
      }
    }
    double median(List<double> v) => (v..sort())[v.length ~/ 2];
    br = median(rs);
    bg = median(gs);
    bb = median(bs);
  }

  final dist = Uint8List(n);
  final hist = List<int>.filled(256, 0);
  for (var p = 0; p < n; p++) {
    final i = p * 3;
    if (model != null) {
      br = model[i];
      bg = model[i + 1];
      bb = model[i + 2];
    }
    final bgLum = 0.299 * br + 0.587 * bg + 0.114 * bb;
    final r = small[i], g = small[i + 1], b = small[i + 2];
    final dr = r - br, dg = g - bg, db = b - bb;
    var d = math.sqrt(dr * dr + dg * dg + db * db);
    final lum = 0.299 * r + 0.587 * g + 0.114 * b;
    // Paper is brighter and less saturated than tables and floors.
    if (lum > bgLum) d *= 1.25;
    // With a local table colour, judge the difference relative to how bright
    // the table is there (a dark corner shrinks every difference).
    if (model != null) d = d * 110 / math.max(30.0, bgLum);
    final v = d.clamp(0, 255).round();
    dist[p] = v;
    hist[v]++;
  }
  final threshold = math.max(28, _otsu(hist, n));

  var mask = Uint8List(n);
  for (var p = 0; p < n; p++) {
    mask[p] = dist[p] > threshold ? 1 : 0;
  }
  // Opening cuts thin bridges into the background (the "corner leak" in dim
  // light); closing then fills the gaps between letters.
  final rad = math.max(2, (math.min(w, h) / 70).round());
  mask = _dilate(_erode(mask, w, h, rad), w, h, rad);
  mask = _erode(_dilate(mask, w, h, rad), w, h, rad);

  // Largest region, with its holes filled.
  final label = Int32List(n);
  var bestLabel = 0, bestSize = 0, next = 0;
  final stack = <int>[];
  for (var p = 0; p < n; p++) {
    if (mask[p] == 0 || label[p] != 0) continue;
    next++;
    var size = 0;
    stack.add(p);
    label[p] = next;
    while (stack.isNotEmpty) {
      final q = stack.removeLast();
      size++;
      final qx = q % w, qy = q ~/ w;
      if (qx + 1 < w && mask[q + 1] == 1 && label[q + 1] == 0) { label[q + 1] = next; stack.add(q + 1); }
      if (qx > 0 && mask[q - 1] == 1 && label[q - 1] == 0) { label[q - 1] = next; stack.add(q - 1); }
      if (qy + 1 < h && mask[q + w] == 1 && label[q + w] == 0) { label[q + w] = next; stack.add(q + w); }
      if (qy > 0 && mask[q - w] == 1 && label[q - w] == 0) { label[q - w] = next; stack.add(q - w); }
    }
    if (size > bestSize) {
      bestSize = size;
      bestLabel = next;
    }
  }
  if (bestSize < n * 0.08 || bestSize > n * 0.97) return null;
  final region = Uint8List(n);
  for (var p = 0; p < n; p++) {
    if (label[p] == bestLabel) region[p] = 1;
  }
  // Fill holes: whatever the outside can't reach belongs to the page.
  final outside = Uint8List(n);
  for (var x = 0; x < w; x++) {
    for (final p in [x, (h - 1) * w + x]) {
      if (region[p] == 0 && outside[p] == 0) { outside[p] = 1; stack.add(p); }
    }
  }
  for (var y = 0; y < h; y++) {
    for (final p in [y * w, y * w + w - 1]) {
      if (region[p] == 0 && outside[p] == 0) { outside[p] = 1; stack.add(p); }
    }
  }
  while (stack.isNotEmpty) {
    final q = stack.removeLast();
    final qx = q % w, qy = q ~/ w;
    for (final nb in [if (qx + 1 < w) q + 1, if (qx > 0) q - 1, if (qy + 1 < h) q + w, if (qy > 0) q - w]) {
      if (region[nb] == 0 && outside[nb] == 0) { outside[nb] = 1; stack.add(nb); }
    }
  }
  for (var p = 0; p < n; p++) {
    if (outside[p] == 0) region[p] = 1;
  }
  return region;
}

/// Fits a straight line to each side of the outline and intersects them
/// (pixel corners of the small picture).
List<double> _fitCornersPx(List<double> xs, List<double> ys, List<double> c0, int w, int h,
    [List<double> bands = const [0.05, 0.03, 0.02]]) {
  var c = c0;
  final diag = math.sqrt(w * w + h * h.toDouble());
  for (final bandFrac in bands) {
    final lines = <List<double>?>[];
    for (var s = 0; s < 4; s++) {
      final ax = c[s * 2], ay = c[s * 2 + 1];
      final bx2 = c[((s + 1) % 4) * 2], by2 = c[((s + 1) % 4) * 2 + 1];
      lines.add(_fitSide(xs, ys, ax, ay, bx2, by2, diag * bandFrac));
    }
    final nc = List<double>.of(c);
    for (var k = 0; k < 4; k++) {
      final l1 = lines[(k + 3) % 4], l2 = lines[k];
      if (l1 == null || l2 == null) continue;
      final pt = _intersect(l1, l2);
      if (pt == null) continue;
      final moved = math.sqrt(math.pow(pt.$1 - c[k * 2], 2) + math.pow(pt.$2 - c[k * 2 + 1], 2));
      if (moved > diag * 0.2) continue;
      nc[k * 2] = pt.$1.clamp(0, w - 1.0);
      nc[k * 2 + 1] = pt.$2.clamp(0, h - 1.0);
    }
    c = nc;
  }
  return c;
}

/// Pixel corners → normalised, checked, pulled a hair inwards.
List<double> _finish(List<double> c, int w, int h) {
  final corners = [
    for (var k = 0; k < 4; k++) ...[c[k * 2] / (w - 1), c[k * 2 + 1] / (h - 1)]
  ];
  if (_quadArea(corners) < 0.08 || !_isConvex(corners)) return List.of(_fallback);
  // A hair inwards so no table edge shows.
  final cx = (corners[0] + corners[2] + corners[4] + corners[6]) / 4;
  final cy = (corners[1] + corners[3] + corners[5] + corners[7]) / 4;
  return [
    for (var k = 0; k < 4; k++) ...[
      corners[k * 2] + (cx - corners[k * 2]) * 0.008,
      corners[k * 2 + 1] + (cy - corners[k * 2 + 1]) * 0.008,
    ]
  ];
}

/// Total-least-squares line (a, b, c with a·x + b·y = c) through the outline
/// points near side A→B, ignoring the ends of the side (where corners and
/// leaks are). Null when too few points.
List<double>? _fitSide(List<double> xs, List<double> ys, double ax, double ay, double bx,
    double by, double band) {
  final dx = bx - ax, dy = by - ay;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 4) return null;
  final ux = dx / len, uy = dy / len;
  final nx = -uy, ny = ux;
  var sx = 0.0, sy = 0.0;
  final px = <double>[], py = <double>[];
  for (var i = 0; i < xs.length; i++) {
    final rx = xs[i] - ax, ry = ys[i] - ay;
    final t = (rx * ux + ry * uy) / len;
    if (t < 0.15 || t > 0.85) continue;
    if ((rx * nx + ry * ny).abs() > band) continue;
    px.add(xs[i]);
    py.add(ys[i]);
    sx += xs[i];
    sy += ys[i];
  }
  if (px.length < 8) return null;
  final mx = sx / px.length, my = sy / py.length;
  double sxx = 0, syy = 0, sxy = 0;
  for (var i = 0; i < px.length; i++) {
    final a = px[i] - mx, b = py[i] - my;
    sxx += a * a;
    syy += b * b;
    sxy += a * b;
  }
  // Direction = main axis of the points.
  final angle = 0.5 * math.atan2(2 * sxy, sxx - syy);
  final lx = math.cos(angle), ly = math.sin(angle);
  final na = -ly, nb = lx;
  return [na, nb, na * mx + nb * my];
}

(double, double)? _intersect(List<double> l1, List<double> l2) {
  final det = l1[0] * l2[1] - l1[1] * l2[0];
  if (det.abs() < 1e-9) return null;
  final x = (l1[2] * l2[1] - l1[1] * l2[2]) / det;
  final y = (l1[0] * l2[2] - l1[2] * l2[0]) / det;
  return (x, y);
}

bool _isConvex(List<double> c) {
  var sign = 0;
  for (var i = 0; i < 4; i++) {
    final ax = c[i * 2], ay = c[i * 2 + 1];
    final bx = c[((i + 1) % 4) * 2], by = c[((i + 1) % 4) * 2 + 1];
    final cx = c[((i + 2) % 4) * 2], cy = c[((i + 2) % 4) * 2 + 1];
    final cross = (bx - ax) * (cy - by) - (by - ay) * (cx - bx);
    final s = cross > 0 ? 1 : (cross < 0 ? -1 : 0);
    if (s == 0) continue;
    if (sign == 0) sign = s;
    if (s != sign) return false;
  }
  return true;
}

Uint8List _erode(Uint8List m, int w, int h, int r) => _morph(m, w, h, r, erode: true);
Uint8List _dilate(Uint8List m, int w, int h, int r) => _morph(m, w, h, r, erode: false);

/// Square erosion/dilation, done as a row pass then a column pass.
Uint8List _morph(Uint8List m, int w, int h, int r, {required bool erode}) {
  final want = erode ? 0 : 1; // value that spreads
  final tmp = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    var last = -1 << 20; // last x where `want` was seen
    final row = y * w;
    // forward then backward pass for nearest `want` within r
    final near = Int32List(w)..fillRange(0, w, 1 << 20);
    for (var x = 0; x < w; x++) {
      if (m[row + x] == want) last = x;
      near[x] = x - last;
    }
    last = 1 << 20;
    for (var x = w - 1; x >= 0; x--) {
      if (m[row + x] == want) last = x;
      near[x] = math.min(near[x], last - x);
      tmp[row + x] = near[x] <= r ? want : 1 - want;
    }
  }
  final out = Uint8List(w * h);
  final near = Int32List(h);
  for (var x = 0; x < w; x++) {
    var last = -1 << 20;
    for (var y = 0; y < h; y++) {
      if (tmp[y * w + x] == want) last = y;
      near[y] = y - last;
    }
    last = 1 << 20;
    for (var y = h - 1; y >= 0; y--) {
      if (tmp[y * w + x] == want) last = y;
      final d = math.min(near[y], last - y);
      out[y * w + x] = d <= r ? want : 1 - want;
    }
  }
  return out;
}

int _otsu(List<int> hist, int total) {
  double sum = 0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  double sumB = 0, best = -1;
  var wB = 0, threshold = 0;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB, mF = (sum - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      threshold = t;
    }
  }
  return threshold;
}

double _quadArea(List<double> c) {
  double a = 0;
  for (var i = 0; i < 4; i++) {
    final j = (i + 1) % 4;
    a += c[i * 2] * c[j * 2 + 1] - c[j * 2] * c[i * 2 + 1];
  }
  return a.abs() / 2;
}

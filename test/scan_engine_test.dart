import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:escaner_local/processing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const samples = 'design/assets/samples';

/// The same photo in dim light: darker, noisy, a dark corner (vignette).
RgbImage dim(RgbImage src, int seed) {
  final rnd = math.Random(seed);
  final out = Uint8List(src.bytes.length);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final dx = (x / src.width - 0.15), dy = (y / src.height - 0.9);
      final vig = (1 - 0.75 * math.min(1, math.sqrt(dx * dx + dy * dy) < 0.55 ? (0.55 - math.sqrt(dx * dx + dy * dy)) / 0.55 : 0)) * 0.32;
      for (var c = 0; c < 3; c++) {
        final i = (y * src.width + x) * 3 + c;
        out[i] = (src.bytes[i] * vig + (rnd.nextDouble() - 0.5) * 14).round().clamp(0, 255);
      }
    }
  }
  return RgbImage(src.width, src.height, out);
}

RgbImage load(String name) => decodePhoto(File('$samples/$name').readAsBytesSync())!;

void save(String name, RgbImage im) {
  Directory('shots').createSync(recursive: true);
  File('shots/$name').writeAsBytesSync(encodeJpeg(im, quality: 88));
}

void overlay(String name, RgbImage im, List<double> c) {
  final image = im.toImage();
  for (var k = 0; k < 4; k++) {
    final j = (k + 1) % 4;
    img.drawLine(image,
        x1: (c[k * 2] * im.width).round(), y1: (c[k * 2 + 1] * im.height).round(),
        x2: (c[j * 2] * im.width).round(), y2: (c[j * 2 + 1] * im.height).round(),
        color: img.ColorRgb8(0, 220, 255), thickness: 6);
  }
  Directory('shots').createSync(recursive: true);
  File('shots/$name').writeAsBytesSync(img.encodeJpg(img.copyResize(image, width: 500)));
}

double maxDiff(List<double> a, List<double> b) {
  var m = 0.0;
  for (var i = 0; i < 8; i++) {
    m = math.max(m, (a[i] - b[i]).abs());
  }
  return m;
}

void main() {
  // Page corners in cam_factura.jpg (1179x2556), measured on the picture.
  final facturaCorners = [
    249 / 1179, 640 / 2556, 932 / 1179, 593 / 2556,
    1011 / 1179, 1696 / 2556, 170 / 1179, 1761 / 2556,
  ];

  test('finds the page in normal and dim light', () {
    for (final name in ['cam_factura.jpg', 'cam_factura2.jpg', 'cam_contrato2.jpg']) {
      final photo = load(name);
      final c = detectCorners(photo);
      final d = detectCorners(dim(photo, 7));
      overlay('detect_$name', photo, c);
      overlay('detect_dim_$name', dim(photo, 7), d);
      // ignore: avoid_print
      print('$name normal=${c.map((v) => v.toStringAsFixed(3)).join(',')}');
      // ignore: avoid_print
      print('$name dim   =${d.map((v) => v.toStringAsFixed(3)).join(',')} diff=${maxDiff(c, d).toStringAsFixed(3)}');
      expect(maxDiff(c, d), lessThan(0.03), reason: '$name: dim light moved the corners');
      if (name == 'cam_factura.jpg') {
        expect(maxDiff(c, facturaCorners), lessThan(0.025), reason: 'factura corners $c');
      }
    }
  });

  test('finds the sheet on the cluttered desk under the lamp', () {
    // Corners of the sheet in the original app's video frames (checked on the
    // overlays in shots/detect_desk_lamp_*.jpg).
    const expected = {
      'desk_lamp_a.jpg': [0.160, 0.192, 0.752, 0.200, 0.850, 0.792, 0.130, 0.838],
      'desk_lamp_b.jpg': [0.165, 0.195, 0.753, 0.203, 0.850, 0.795, 0.135, 0.832],
      'desk_lamp_c.jpg': [0.152, 0.185, 0.737, 0.193, 0.834, 0.779, 0.122, 0.826],
    };
    for (final name in expected.keys) {
      final photo = decodePhoto(File('test/fixtures/$name').readAsBytesSync())!;
      final c = detectCorners(photo);
      overlay('detect_$name', photo, c);
      // ignore: avoid_print
      print('$name ${c.map((v) => v.toStringAsFixed(3)).join(',')} diff=${maxDiff(c, expected[name]!).toStringAsFixed(3)}');
      expect(maxDiff(c, expected[name]!), lessThan(0.02), reason: name);
      // Same frame as the live preview sees it: grey only, 160 px.
      final g = Uint8List(photo.bytes.length);
      for (var p = 0; p < photo.width * photo.height; p++) {
        final v = (photo.bytes[p * 3] * 299 + photo.bytes[p * 3 + 1] * 587 + photo.bytes[p * 3 + 2] * 114) ~/ 1000;
        g[p * 3] = v;
        g[p * 3 + 1] = v;
        g[p * 3 + 2] = v;
      }
      final small = RgbImage.fromImage(img.copyResize(RgbImage(photo.width, photo.height, g).toImage(),
          width: (photo.width * 160 / photo.height).round(), height: 160));
      final live = detectCorners(small);
      // ignore: avoid_print
      print('  live ${live.map((v) => v.toStringAsFixed(3)).join(',')} diff=${maxDiff(live, expected[name]!).toStringAsFixed(3)}');
      expect(maxDiff(live, expected[name]!), lessThan(0.04), reason: '$name live');
    }
  });

  test('magic enhance whitens paper and keeps text dark', () {
    final photo = load('cam_factura.jpg');
    final flat = flattenPage(photo, detectCorners(photo));
    final enhanced = applyFilter(flat, PageFilter.enhance);
    save('magic_factura.jpg', enhanced);
    save('magic_factura_dim.jpg', applyFilter(flattenPage(dim(photo, 3), detectCorners(dim(photo, 3))), PageFilter.enhance));
    for (final f in PageFilter.values) {
      save('filter_${f.name}.jpg', applyFilter(flat, f));
    }
    // Under a warm desk lamp: yellow on one side, cooler and darker on the
    // other, plus a hand's soft shadow in the lower left.
    final lamp = Uint8List(flat.bytes.length);
    for (var y = 0; y < flat.height; y++) {
      for (var x = 0; x < flat.width; x++) {
        final u = x / flat.width, v = y / flat.height;
        final warm = 1 - u * 0.6;
        final dx = u - 0.1, dy = v - 0.95;
        final shade = 1 - 0.45 * math.max(0, 1 - math.sqrt(dx * dx + dy * dy) / 0.45);
        final k = (0.75 - 0.25 * v) * shade;
        final i = (y * flat.width + x) * 3;
        lamp[i] = (flat.bytes[i] * k * (1.0 + 0.12 * warm)).round().clamp(0, 255);
        lamp[i + 1] = (flat.bytes[i + 1] * k * (1.0 + 0.02 * warm)).round().clamp(0, 255);
        lamp[i + 2] = (flat.bytes[i + 2] * k * (1.0 - 0.30 * warm)).round().clamp(0, 255);
      }
    }
    final lampIn = RgbImage(flat.width, flat.height, lamp);
    save('lamp_in.jpg', lampIn);
    final lampOut = applyFilter(lampIn, PageFilter.enhance);
    save('lamp_mejorar.jpg', lampOut);
    // Paper comes out white and neutral everywhere (no yellow left).
    var cast = 0.0, paperN = 0;
    for (var p = 0; p < lampOut.width * lampOut.height; p += 7) {
      final i = p * 3;
      final l = (lampOut.bytes[i] + lampOut.bytes[i + 1] + lampOut.bytes[i + 2]) / 3;
      if (l > 200) {
        cast += (lampOut.bytes[i] - lampOut.bytes[i + 2]).abs();
        paperN++;
      }
    }
    // ignore: avoid_print
    print('lamp paper share=${(paperN * 7 / (lampOut.width * lampOut.height)).toStringAsFixed(2)} cast=${(cast / paperN).toStringAsFixed(1)}');
    expect(cast / paperN, lessThan(8));
    // Paper: most pixels are white.
    var white = 0, dark = 0;
    for (var p = 0; p < enhanced.width * enhanced.height; p++) {
      final i = p * 3;
      final l = (enhanced.bytes[i] + enhanced.bytes[i + 1] + enhanced.bytes[i + 2]) / 3;
      if (l > 245) white++;
      if (l < 70) dark++;
    }
    final total = enhanced.width * enhanced.height;
    // ignore: avoid_print
    print('white=${(white / total).toStringAsFixed(2)} dark=${(dark / total).toStringAsFixed(3)}');
    expect(white / total, greaterThan(0.55));
    expect(dark / total, greaterThan(0.005));
  });

  test('blurry photos are caught, sharp ones pass', () {
    final sharp = load('cam_factura.jpg');
    final c = detectCorners(sharp);
    final flatSharp = flattenPage(sharp, c);
    final blurPhoto = load('cam_factura_blur.jpg');
    final flatBlur = flattenPage(blurPhoto, detectCorners(blurPhoto));
    final light = RgbImage.fromImage(img.gaussianBlur(flatSharp.toImage(), radius: 3));
    final dimSharp = flattenPage(dim(sharp, 5), c);
    final scores = {
      'sharp': blurScore(flatSharp),
      'sharp-dim': blurScore(dimSharp),
      'shake-r3': blurScore(light),
      'blur-sample': blurScore(flatBlur),
      'contrato': blurScore(flattenPage(load('cam_contrato2.jpg'), detectCorners(load('cam_contrato2.jpg')))),
    };
    // ignore: avoid_print
    print(scores);
    expect(isBlurry(flatSharp), isFalse);
    expect(isBlurry(dimSharp), isFalse);
    expect(isBlurry(flatBlur), isTrue);
    expect(isBlurry(light), isTrue);
  });
}

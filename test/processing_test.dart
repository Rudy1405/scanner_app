import 'dart:io';
import 'dart:typed_data';

import 'package:escaner_local/processing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A photo of a tilted sheet on a dark table, with a shadow across it.
Uint8List samplePhoto() {
  final photo = img.Image(width: 900, height: 1200, numChannels: 3);
  img.fill(photo, color: img.ColorRgb8(70, 55, 45));
  final corners = [
    img.Point(180, 140), img.Point(760, 210), img.Point(700, 1080), img.Point(120, 1010),
  ];
  img.fillPolygon(photo, vertices: corners, color: img.ColorRgb8(236, 232, 222));
  for (var i = 0; i < 24; i++) {
    final y = 260 + i * 30;
    img.drawLine(photo,
        x1: 210 + i, y1: y, x2: 640 + i, y2: y + 40, color: img.ColorRgb8(50, 50, 60), thickness: 4);
  }
  // Soft shadow on the left half.
  for (var y = 0; y < photo.height; y++) {
    for (var x = 0; x < 420; x++) {
      final p = photo.getPixel(x, y);
      final f = 0.72 + 0.28 * (x / 420);
      photo.setPixelRgb(x, y, (p.r * f).round(), (p.g * f).round(), (p.b * f).round());
    }
  }
  return Uint8List.fromList(img.encodeJpg(photo, quality: 92));
}

void main() {
  test('finds the sheet, flattens it and applies every filter', () {
    final photo = decodePhoto(samplePhoto())!;
    final c = detectCorners(photo);
    final expected = [180 / 899, 140 / 1199, 760 / 899, 210 / 1199, 700 / 899, 1080 / 1199, 120 / 899, 1010 / 1199];
    for (var i = 0; i < 8; i++) {
      expect((c[i] - expected[i]).abs(), lessThan(0.03), reason: 'corner value $i: ${c[i]}');
    }
    final flat = flattenPage(photo, c);
    expect(flat.width, greaterThan(500));
    expect(flat.height, greaterThan(800));
    final dir = Directory('shots')..createSync(recursive: true);
    File('${dir.path}/test_photo.jpg').writeAsBytesSync(samplePhoto());
    for (final f in PageFilter.values) {
      final out = applyFilter(flat, f);
      File('${dir.path}/test_${f.name}.jpg').writeAsBytesSync(encodeJpeg(out));
    }
    // B&W turns paper white and text black.
    final bw = applyFilter(flat, PageFilter.bw);
    final white = bw.bytes.where((v) => v == 255).length / bw.bytes.length;
    expect(white, greaterThan(0.6));
  });

  test('text sharpening follows the original rule', () {
    // 5x5 grey 200 with one dark dot of 150: box mean (3x3) = 194.4 → 194,
    // d = -44 < -20 → doubled → 150 - 88 = 62.
    final bytes = Uint8List(5 * 5 * 3)..fillRange(0, 75, 200);
    for (var c = 0; c < 3; c++) {
      bytes[(2 * 5 + 2) * 3 + c] = 150;
    }
    final out = sharpEnhance(RgbImage(5, 5, bytes), 4).bytes;
    expect(out[(2 * 5 + 2) * 3], 62);
    // A neighbour 6 brighter than its blurred surroundings gets half of it.
    expect(out[(2 * 5 + 1) * 3], 203);
  });
}

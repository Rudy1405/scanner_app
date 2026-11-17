import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../processing.dart';
import 'scanner_ffi.dart';

/// Page corners of a whole photo (0..1, TL,TR,BR,BL): the OpenCV detector when
/// it is available and sure of itself, else the Dart detector. Safe to call
/// from any isolate.
List<double> findCorners(RgbImage im) {
  final native = _nativeCorners(im);
  return native ?? detectCorners(im);
}

NativeScanner? _scanner;
bool _scannerTried = false;

List<double>? _nativeCorners(RgbImage im) {
  if (!_scannerTried) {
    _scannerTried = true;
    _scanner = NativeScanner.tryCreate(workWidth: 480);
  }
  final s = _scanner;
  if (s == null) return null;
  final px = malloc<Uint8>(im.bytes.length);
  try {
    px.asTypedList(im.bytes.length).setAll(0, im.bytes);
    final r = s.detectImage(px, im.width, im.height, im.width * 3, 3);
    return r.confidence >= 0.5 ? r.quad : null;
  } catch (_) {
    return null;
  } finally {
    malloc.free(px);
  }
}

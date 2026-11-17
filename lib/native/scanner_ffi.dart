import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// Bindings of libscanner.so (android/app/src/main/cpp/scanner.h).
typedef _CreateC = Pointer<Void> Function(Int32);
typedef _CreateD = Pointer<Void> Function(int);
typedef _DestroyC = Void Function(Pointer<Void>);
typedef _DestroyD = void Function(Pointer<Void>);
typedef _DetectYC = Float Function(
    Pointer<Void>, Pointer<Uint8>, Int32, Int32, Int32, Int32, Pointer<Float>);
typedef _DetectYD = double Function(
    Pointer<Void>, Pointer<Uint8>, int, int, int, int, Pointer<Float>);
typedef _DetectImgC = Float Function(
    Pointer<Void>, Pointer<Uint8>, Int32, Int32, Int32, Int32, Pointer<Float>);
typedef _DetectImgD = double Function(
    Pointer<Void>, Pointer<Uint8>, int, int, int, int, Pointer<Float>);
typedef _VersionC = Pointer<Utf8> Function();
typedef _VersionD = Pointer<Utf8> Function();

/// Result of one detection: normalised corners (TL,TR,BR,BL) and confidence.
class ScanResult {
  const ScanResult(this.quad, this.confidence);
  final List<double>? quad; // 8 values, 0..1, upright; null = no page
  final double confidence;
}

/// A loaded native scanner. Each isolate loads its own instance
/// (the library is shared, the handle is not).
class NativeScanner {
  NativeScanner._(DynamicLibrary lib, this._handle, this._out)
      : _detectY = lib.lookupFunction<_DetectYC, _DetectYD>('scanner_detect_y'),
        _detectImg = lib.lookupFunction<_DetectImgC, _DetectImgD>('scanner_detect_image'),
        _destroy = lib.lookupFunction<_DestroyC, _DestroyD>('scanner_destroy');

  final Pointer<Void> _handle;
  final Pointer<Float> _out;
  final _DetectYD _detectY;
  final _DetectImgD _detectImg;
  final _DestroyD _destroy;

  static bool get supported => Platform.isAndroid;

  /// The native version string, or null when the library can't be loaded.
  static String? version() {
    if (!supported) return null;
    try {
      final lib = DynamicLibrary.open('libscanner.so');
      return lib.lookupFunction<_VersionC, _VersionD>('scanner_version')().toDartString();
    } catch (_) {
      return null;
    }
  }

  /// Loads the library and creates a detector; null if that is not possible.
  static NativeScanner? tryCreate({int workWidth = 320}) {
    if (!supported) return null;
    try {
      final lib = DynamicLibrary.open('libscanner.so');
      final create = lib.lookupFunction<_CreateC, _CreateD>('scanner_create');
      final h = create(workWidth);
      if (h == nullptr) return null;
      return NativeScanner._(lib, h, calloc<Float>(8));
    } catch (_) {
      return null;
    }
  }

  ScanResult _result(double c) {
    if (c <= 0) return const ScanResult(null, 0);
    return ScanResult([for (var i = 0; i < 8; i++) _out[i]], c);
  }

  /// [y] points at a luminance plane that stays valid during the call.
  ScanResult detectY(Pointer<Uint8> y, int w, int h, int stride, int rotation) =>
      _result(_detectY(_handle, y, w, h, stride, rotation, _out));

  /// Whole upright picture with 3 (RGB) or 4 (RGBA) channels per pixel.
  ScanResult detectImage(Pointer<Uint8> px, int w, int h, int stride, int channels) =>
      _result(_detectImg(_handle, px, w, h, stride, channels, _out));

  void dispose() {
    _destroy(_handle);
    calloc.free(_out);
  }
}

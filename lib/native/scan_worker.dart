import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'scanner_ffi.dart';

/// Long-lived worker isolate that runs the native page detector.
///
/// The UI isolate copies the Y plane of a camera frame into a native buffer
/// and sends only its address; the worker calls OpenCV through FFI and sends
/// back the corners. While the worker is busy new frames are skipped
/// ([submit] returns false), so a slow detection never queues work or blocks
/// the camera preview.
class ScanWorker {
  ScanWorker._(this._isolate, this._port, this._rx, this._send);

  final Isolate _isolate;
  final ReceivePort _port; // replies from the worker
  final ReceivePort _rx; // exit/error notifications
  final SendPort _send;

  Pointer<Uint8>? _buf;
  int _cap = 0;
  int _seq = 0;
  bool _busy = false;
  bool _closed = false;
  Timer? _bye;

  /// Called on the UI isolate with every answer of the worker.
  void Function(ScanResult result, int micros)? onResult;

  /// Called if the worker stops unexpectedly (the caller should fall back).
  void Function()? onDead;

  /// True while a frame is being processed: skip frames until it answers.
  bool get busy => _busy;

  /// Starts the worker; null when the native library isn't available.
  static Future<ScanWorker?> start() async {
    if (!NativeScanner.supported) return null;
    final port = ReceivePort();
    final rx = ReceivePort();
    final ready = Completer<SendPort?>();
    ScanWorker? worker;
    port.listen((m) {
      if (!ready.isCompleted) {
        ready.complete(m is SendPort ? m : null);
      } else {
        worker?._handle(m);
      }
    });
    Isolate isolate;
    try {
      isolate = await Isolate.spawn(_workerMain, port.sendPort,
          onError: rx.sendPort, onExit: rx.sendPort, debugName: 'scan-worker');
    } catch (_) {
      port.close();
      rx.close();
      return null;
    }
    final sp = await ready.future.timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (sp == null) {
      isolate.kill(priority: Isolate.immediate);
      port.close();
      rx.close();
      return null;
    }
    worker = ScanWorker._(isolate, port, rx, sp);
    rx.listen((_) => worker!._died());
    return worker;
  }

  /// Copies the luminance plane and starts a detection. Returns false when the
  /// frame was skipped (worker busy or closed).
  bool submit(Uint8List y, int w, int h, int stride, int rotation) {
    if (_busy || _closed) return false;
    if (_buf == null || y.length > _cap) {
      final old = _buf;
      if (old != null) malloc.free(old);
      _buf = malloc<Uint8>(y.length);
      _cap = y.length;
    }
    _buf!.asTypedList(y.length).setAll(0, y);
    _busy = true;
    _send.send([++_seq, _buf!.address, w, h, stride, rotation]);
    return true;
  }

  void _handle(Object? m) {
    if (m is List) {
      _busy = false;
      if (_closed) return;
      final conf = (m[1] as num).toDouble();
      final q = m[2] == null ? null : (m[2] as List).cast<double>();
      onResult?.call(ScanResult(q, conf), m[3] as int);
    } else if (m == 'bye') {
      _finish();
    }
  }

  void _died() {
    if (_closed) return;
    _busy = false;
    _closed = true;
    onDead?.call();
    _release(freeBuffer: false); // the native call may still own the buffer
  }

  /// Stops the worker. The buffer is freed only after the worker confirms,
  /// because a native call may still be reading it.
  void dispose() {
    if (_closed) return;
    _closed = true;
    onResult = null;
    onDead = null;
    _send.send('stop');
    _bye = Timer(const Duration(seconds: 3), () => _release(freeBuffer: false));
  }

  void _finish() => _release(freeBuffer: true);

  void _release({required bool freeBuffer}) {
    _bye?.cancel();
    if (freeBuffer && _buf != null) {
      malloc.free(_buf!);
      _buf = null;
    }
    _isolate.kill(priority: Isolate.beforeNextEvent);
    _port.close();
    _rx.close();
  }
}

void _workerMain(SendPort main) {
  final rp = ReceivePort();
  final scanner = NativeScanner.tryCreate();
  if (scanner == null) {
    main.send(null);
    return;
  }
  main.send(rp.sendPort);
  rp.listen((m) {
    if (m is List) {
      final sw = Stopwatch()..start();
      final r = scanner.detectY(Pointer<Uint8>.fromAddress(m[1] as int), m[2] as int,
          m[3] as int, m[4] as int, m[5] as int);
      main.send([m[0], r.confidence, r.quad, sw.elapsedMicroseconds]);
    } else {
      scanner.dispose();
      main.send('bye');
      rp.close();
    }
  });
}

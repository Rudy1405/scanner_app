# Plan: native OpenCV page detector (FFI + worker isolate)

Status: **proposed, next feature**. Nothing here is implemented.
Scope: live page detection in the camera, plus the same detector on the captured photo.

## 1. Why

What the app does today (read from `lib/ui_camera.dart` and `lib/scan_engine.dart`):

- `_onFrame` copies the Y plane (`Uint8List.fromList`, about 2 MB at 1080p) on the UI isolate.
- It then calls `compute(_detectLive, frame)`. `compute` **spawns a new isolate for every frame** and sends the frame to it. That costs a spawn plus a copy at every detection.
- `_detectLive` downsamples and rotates in pure Dart, then `detectCorners` runs a Dart edge/line-fit pipeline on a 300 px image.
- Backpressure already exists (`detecting` flag plus a 300 ms throttle), so frames are dropped while busy. That part is fine and is kept.

Problems this feature addresses:

1. Isolate spawn and copy at every frame; per-frame Dart loops over boxed pixel data.
2. A pure-Dart detector is weaker than contour-based detection (`Canny`, `findContours`, `approxPolyDP`) on cluttered backgrounds.
3. `setState` on the whole camera screen at every detection.

Not a goal: replacing the capture pipeline, filters, PDF export or storage.

## 2. Answers to the questions asked

**Can we do OpenCV through FFI with no platform channels?**
Yes for *our* code. We write a small C++ library `libscanner.so` that exposes a C API, and Dart loads it with `DynamicLibrary.open` and `dart:ffi`. No MethodChannel is involved in detection.
Caveat: the `camera` package still delivers `CameraImage` frames through its own channel internally. We can't remove that without writing our own camera plugin. Our detection path after that point is channel-free. Camera frame delivery costs one copy of the Y plane per processed frame.

**Frame to isolate, result back, skip frames until it answers?**
Yes. One long-lived worker isolate (spawned once, not per frame) with a latest-wins slot. See section 4.

**OCR: will it make the processor run better?**
No. OCR is not an edge detector and is far heavier than OpenCV contour detection, so running it per frame would *add* CPU and heat. Use OCR only where it adds value (section 6). Keep ML Kit, which is already in the app.

## 3. Native library

Layout (all new, nothing in existing Dart files changes in phase 1):

```
android/app/src/main/cpp/
  CMakeLists.txt
  scanner.h            // extern "C" API
  scanner.cpp
native/
  build_opencv.ps1     // builds the static OpenCV once (section 3.2)
lib/native/
  scanner_ffi.dart     // bindings + DynamicLibrary loader
  scan_worker.dart     // isolate + slot protocol
```

### 3.1 C API (stable surface)

```c
typedef struct Scanner Scanner;
Scanner* scanner_create(int work_width);                // e.g. 320
void     scanner_destroy(Scanner*);
// y: luminance plane, stride in bytes, rotation 0/90/180/270 clockwise to upright.
// out8: 4 corners x,y normalised 0..1 in upright space, order TL,TR,BR,BL.
// Returns confidence 0..1 (0 = no page). Never throws.
float    scanner_detect_y(Scanner*, const uint8_t* y, int w, int h,
                          int stride, int rotation, float* out8);
// Same detector on a full photo (RGBA or gray) for the post-capture pass.
float    scanner_detect_rgba(Scanner*, const uint8_t* px, int w, int h,
                             int stride, float* out8);
const char* scanner_version(void);
```

Rules: no C++ exceptions across the boundary, no allocation visible to Dart (the worker owns its buffers), results are plain floats.

### 3.2 OpenCV build

- Build OpenCV **from source with only `core` and `imgproc`**, static (`BUILD_SHARED_LIBS=OFF`, no Java, no `dnn`, no `videoio`), with the NDK that Flutter already pins (`flutter.ndkVersion`), for `arm64-v8a` first.
- Reason: the full prebuilt SDK is large; a core+imgproc static link into `libscanner.so` keeps only the pulled-in objects. Expected size is a few MB per ABI. **This is an estimate and must be measured** in phase 0.
- Pin the OpenCV version and record it in `native/README.md`. (The version isn't chosen yet; take the latest stable 4.x when implementing.)
- The static OpenCV output is cached under `native/opencv-android/` (git-ignored). `build_opencv.ps1` is a one-time step; Gradle only runs our small CMake project.

### 3.3 Gradle wiring

- `externalNativeBuild { cmake { path "src/main/cpp/CMakeLists.txt" } }` in `android/app/build.gradle.kts`.
- `ndk { abiFilters += listOf("arm64-v8a") }` for release at first. Add `armeabi-v7a` only if the test devices need it; 32-bit devices double the library size.
- The Redmi Note 9S is arm64.

### 3.4 Why not `opencv_dart` or native assets hooks

Research shows `opencv_dart` 2.x relies on the experimental native assets feature and builds through Conan with an NDK path, and `dartcv4` needs Dart 3.10 for hooks. Those add tooling that is still moving.
Also, this machine's Craft Anything folder **blocks symlinks** (os error 448, see memory note `symlink-redirection-guard`), which already broke Flutter plugin links and the cargo proxy. Plugin and Conan setups create links in their build trees. A plain Gradle CMake project that we own and that does not rely on plugin symlinks is the lowest-risk path. `opencv_dart` stays as a fallback to evaluate only if our own build is blocked.

## 4. Isolate and frame protocol

```
camera stream (UI isolate)                      worker isolate (long-lived)
  _onFrame(image)
    if worker.busy or shooting -> return        // drop frame
    copy Y plane -> native buffer[k]            // 1 memcpy, no Dart object per pixel
    busy = true
    send [seq, addr(buffer[k]), w,h,stride,rot] ------------>  detect_y(...)  (sync FFI, ~ms)
                                                <------------  [seq, quad|null, conf, ms]
    busy = false; if seq is stale -> ignore
    update ValueNotifier<Quad?>                 // no setState on the whole screen
```

Design rules:

1. **One worker, spawned once** at camera start (`Isolate.spawn`), killed at dispose and on `paused`. Replaces `compute` per frame.
2. **Two native buffers (ping-pong)** allocated with `malloc` once, size = frame bytes. The UI isolate writes into the free one; the worker reads it through `Pointer.fromAddress`. A buffer belongs to exactly one side between send and reply, so there is no lock.
3. **Messages carry only ints/addresses**, not pixel data. The only pixel copy is the one memcpy into the native buffer.
4. **Frame skip until response**: `busy` flag. The existing 300 ms throttle becomes a target rate (about 8–10 Hz), not a guard against overload.
5. **Sequence numbers** drop stale or out-of-order replies (for example after a resolution change).
6. **Failure handling**: if the library fails to load, or the worker dies, or `scanner_detect_y` returns an error, restart the worker once, then fall back to the current Dart `detectCorners` path. Keep that path in the code behind a flag (`useNativeDetector`).
7. **Rotation and downscale are done in C++** (`cv::resize` with `INTER_AREA`, `cv::rotate`), replacing the Dart per-pixel loops in `_detectLive`.
8. `scanner_detect_y` works on the **Y plane only**. No YUV to RGB conversion is needed, which is the common OpenCV cost with camera frames.

## 5. Detection algorithm (C++)

1. Y plane to work size (about 320 px long side), rotate upright.
2. `GaussianBlur`, then `Canny` with thresholds from the median brightness (adaptive).
3. `dilate` or `morphologyEx(CLOSE)` to join broken edges.
4. `findContours` (external), keep the largest convex ones, `approxPolyDP`.
5. Accept a 4-point convex polygon covering about 15–95% of the frame; order corners TL, TR, BR, BL.
6. Fallback pass for low contrast (white page on a light table): adaptive threshold plus the same contour step.
7. Confidence = area ratio times angle sanity times edge-support ratio. Return 0 below a threshold, so Dart shows "no page".
8. Temporal smoothing and the 1 s auto-capture stability check **stay in Dart** (`_updateQuad`, `_moved`), unchanged.

The dim-light behaviour of the current Dart detector ("works in dim light", channel levelling) must be matched: add a percentile contrast stretch on the Y plane before Canny. Test with the same low-light cases.

## 6. OCR: where it helps

| Use | Phase | Verdict |
|---|---|---|
| Per-frame OCR to find the page | none | **No.** Slow, battery-heavy, wrong tool. |
| Post-capture orientation check (text upright?) | 4, optional | Good: run ML Kit once on the flattened page and rotate by 90° if the text lines are vertical. |
| Readability / blur gate ("Foto movida") | 4, optional | Cheaper without OCR: Laplacian variance in `libscanner`. Use that first. |
| Searchable text index | existing | Already shipped via `google_mlkit_text_recognition` (`OcrScreen`). Keep. |

Engine comparison (sources in section 10; no solid head-to-head benchmarks found, numbers below are anecdotal):

- **ML Kit** (already a dependency): easiest, best accuracy in the comparisons found, runs on-device. Proprietary terms.
- **Tesseract**: open source, needs bundled `traineddata`, reported larger size increase and slower per image in one app test.
- **PaddleOCR via ONNX Runtime**: promising on-device, but there are no verified size/latency numbers and it needs a second native runtime. Out of scope.

Recommendation: keep ML Kit, post-capture and in the background only, never in the live loop. Decide on orientation detection after phase 3 measurements.

## 7. UI changes (small)

- Replace `quad`/`shownQuad` `setState` with a `ValueNotifier<List<double>?>` and a `ValueListenableBuilder` around the outline painter only.
- Keep the existing copy and states (`noFrames`, `dark`, "Poca luz").
- No visual redesign. Follow `design/specs/04-06-camara.md` for any overlay change.

## 8. Rules from `CLAUDE.md` to respect

- `processing.dart`, `store.dart`, `export.dart` stay untouched in phases 0–3. Phase 5 (native warp and filters) would change the image engine, so **it needs explicit approval first**.
- `scan_engine.dart` (`detectCorners`) is kept as the fallback.
- Accent colours stay within `#00B4D8` / `#0089A7` / `#48CAE4`.

## 9. Phases and acceptance

| Phase | Work | Done when |
|---|---|---|
| 0. Spike | Build OpenCV core+imgproc static for arm64; a hello-world `scanner_version()` called from Dart on the phone | Release APK installs and runs; APK size delta recorded (target: under about 10 MB over the current 82.4 MB, **to be confirmed**) |
| 1. Detector | `scanner_detect_y` + test images (`Test_files/` and photos with clutter, low light, a tilted page, no page) | Detects the same or better than the Dart detector on the set; returns confidence 0 when no page |
| 2. Worker | Isolate, ping-pong buffers, sequence numbers, drop-while-busy, lifecycle, Dart fallback | Preview stays smooth: no dropped UI frames in a 60 s run; killing the worker falls back without crashing |
| 3. UI + measure | `ValueNotifier` overlay, timing counters (detect ms, effective Hz) behind a debug flag | On the Redmi Note 9S: detect time and rate recorded before/after; auto-capture still fires after 1 s stable |
| 4. Optional | Photo-level `scanner_detect_rgba` for the crop screen; Laplacian blur score; ML Kit orientation | Crop screen opens with a good initial quad faster than today |
| 5. Optional, needs approval | `warpPerspective` + adaptive threshold in native, replacing the Dart homography and filters | A/B images match or beat the current filters; user approves touching `processing.dart` |

Performance targets (**goals to verify**, not measured): live detect ≤ 25 ms per frame at 320 px work size on the Snapdragon 720G, 8–10 detections per second, no jank on the preview.

## 10. Risks

| Risk | Mitigation |
|---|---|
| Symlink block (os error 448) hits the native build | Own CMake project, no plugin symlinks; build OpenCV out-of-tree; keep `opencv_dart` as the last fallback |
| NDK/STL mismatch between OpenCV static libs and `libscanner.so` | Build both with the same NDK and `c++_static` |
| APK size grows | Only `core`+`imgproc`, arm64 only, `-O2 -fvisibility=hidden`, `--gc-sections`; measure in phase 0 |
| Camera package copy cost at 1080p (`ResolutionPreset.veryHigh`) | One Y-plane memcpy per processed frame (about 2 MB); if it shows up in traces, try a lower stream preset and re-check still quality |
| Buffer reuse race | Strict ownership: UI writes only the free buffer, worker only the sent one |
| Worker crash or library missing | Fallback to the Dart detector behind the flag |
| iOS | Not covered: this plan is Android arm64. The iOS build needs a Mac and a separate static OpenCV; FFI code is shared, the build glue is not |

## 11. Sources

- [opencv_dart on pub.dev](https://pub.dev/packages/opencv_dart/versions/2.0.0-dev.8): native assets, Conan/NDK build, experimental.
- [dartcv4 docs](https://pub.dev/documentation/dartcv4/2.3.0/): Dart 3.10 / hooks requirement.
- [Scanbot: Flutter plugin with native OpenCV via dart:ffi, part 2](https://scanbot.io/techblog/implementing-a-flutter-plugin-with-native-opencv-support-via-dartffi-part-2-2/): `!_isDetecting` frame skipping pattern.
- [Scanbot: ML Kit vs OpenCV for document scanning](https://scanbot.io/blog/ml-kit-vs-opencv-document-scanning-software/)
- [Simon Binder, native assets talk handout](https://www.simonbinder.eu/native_assets_talk_handout.pdf): `hook/build.dart` and `@Native` pattern.
- [Fritz: choosing an on-device OCR SDK on Android](https://fritz.ai/choose-the-right-on-device-text-recognition-sdk-on-android-using-deltaml-9b4b3e409b6e): ML Kit vs Tesseract size and accuracy (older, single-app tests).
- [Ente: the best open-source Android OCR](https://community.ente.io/blog/ocr): PaddleOCR on ONNX Runtime, no numbers.
- [Nitro Camera docs](https://pub.dev/documentation/nitro_camera/latest/) and [flutter_native_vision_camera](https://pub.dev/documentation/flutter_native_vision_camera/0.1.0/): plugin notes on direct FFI frame access, buffer lifetime, drop-latest backpressure (vendor claims, not benchmarks).

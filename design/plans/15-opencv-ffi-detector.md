# Plan 15: native OpenCV page detector (FFI, native worker thread)

Status: **ready to implement**. Nothing here is implemented yet.
Revision 2 (2026-11-17). This replaces revision 1. Section 13 lists what changed and why.
Scope: live page detection in the camera, the capture path after the shutter, and the
hand-off between them. Android arm64 first. Every other platform falls back to the
current Dart code, with no change in behaviour.

---

## 0. How Claude Code should use this plan

- Work one **work package (WP)** per session, in order. Each WP lists the files it touches,
  the steps, and a **Done when** check that can be run. Don't start a WP before the
  previous one's check passes.
- Values marked **(measure)** are unknown until a WP measures them. Write each measured
  value into `native/README.md` under "Measurements", with the date. Don't invent numbers.
- Values marked **(verified)** were read from source code or official docs on 2026-11-17
  (section 12).
- Steps that need the phone (Redmi Note 9S, Snapdragon 720G, arm64, 60 Hz) are marked
  **[device]**. If no device is connected (`adb devices` is empty), stop and ask the user
  to connect it. Don't skip the step or mark it done. adb is at
  `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe` (it isn't on PATH).
- Follow `app/CLAUDE.md`. Don't touch `processing.dart`, `store.dart`, `export.dart` or
  `scan_engine.dart` (scan_engine is `part of 'processing.dart'`). WP9 is the only
  exception and it needs explicit user approval.
- This machine blocks symlinks and junctions under `Craft Anything` (os error 448, memory
  note `symlink-redirection-guard`). Don't use tools that create links: no Conan, no
  native-assets hooks, no `mklink`, no `git clone` of repos that rely on symlinks. If a
  build fails with os error 448, see section 11.

---

## 1. What the app does today (verified)

### 1.1 Live preview (`lib/ui_camera.dart`)

| Step | Where | Cost |
|---|---|---|
| `CameraController(back, ResolutionPreset.veryHigh, imageFormatGroup: yuv420)` | `_init` | camera_android caps the **preview and image stream at `high` = 1280×720** whatever preset is asked (`ResolutionFeature.computeBestPreviewSize`, `camera_android-0.10.13`, line 127). The stream is 720p, not 1080p. |
| Plugin copies **all 3 YUV planes** into new `byte[]`s for **every** frame | `ImageStreamReader.onImageAvailable` / `parsePlanesForYuvOrJpeg` (Java, camera background thread) | About 1.4 MB allocated per frame at 30 fps, even for frames Dart then drops. |
| Plugin posts each frame map to the **main looper**, then `EventChannel.success` | `ImageStreamReader` line ~150 | Since Flutter 3.29 the Android **platform and UI threads are merged**, so the encode and send of each frame runs on the same thread as Dart build and layout. This is a per-frame cost that a Dart-side frame skip can't remove. |
| `_onFrame`: `setState` once, then a sparse brightness loop, then a 300 ms throttle | UI isolate | Cheap. |
| `Uint8List.fromList(plane.bytes)` | UI isolate | About 0.9 MB memcpy. |
| `compute(_detectLive, frame)` | spawns a **new isolate per detection** | Spawn plus a message copy every 300 ms. |
| `_detectLive`: nearest-neighbour resize to 200 px, rotate, expand to RGB in Dart loops, then `detectCorners`, which **resizes again to 300 px** | worker isolate | Pure Dart per-pixel loops (measure). |
| `_updateQuad` → `setState` on the **whole camera screen** at each result | UI isolate | Rebuilds the full Stack: preview, glass, gradients, bottom bar. |

### 1.2 Shutter (`_shoot`, `_captureJob`)

| Step | Cost |
|---|---|
| `stopImageStream()` → camera_android rebuilds the capture session without the stream surface | Preview stall (measure). |
| `takePicture()` → JPEG at the preset's **video profile size**: `veryHigh` = 1920×1080, 16:9, about 2 MP (verified in `ResolutionFeature`; actual size: measure) | Low resolution for text. |
| `startImageStream()` → **second session rebuild** | Second preview stall. |
| `compute(_captureJob)`: full JPEG decode in **pure Dart** (`img.decodeImage`), `bakeOrientation`, two resizes (2400, then 1600), `detectCorners`, `flattenPage`, `isBlurry`, `applyFilter`, two JPEG encodes | Seconds-scale (measure). This is the "freeze" the user sees after the shutter. |

### 1.3 The existing Dart detector (`lib/scan_engine.dart`, `detectCorners`)

It isn't a naive detector. It mirrors the original app's `findCandidateLines` + `adjustRect`
(`MECHANICS.md`, "Round 3") and has regression tests with measured corners
(`test/scan_engine_test.dart`: `cam_factura`, `cam_contrato2`, the lamp/desk frames, dim-light
variants, and the 200 px grey live frame within 0.04). It works like this:

1. Area-averaged copy at 300 px long side.
2. Per-channel levels at 1 % / 99 %.
3. Gaussian σ 1.2.
4. **Candidate 1, lines**: Sobel on the strongest channel, non-maximum suppression, top 12 %
   of edges, oriented Hough (±6°, 26 lines, ±5°/±7 px suppression), every
   top/bottom/left/right combination scored as edge support 60 % plus brightness step 40 %
   (`_quadScore`).
5. **Candidate 2, region**: two passes against the table colour and a quadratic table model,
   opening/closing radius min(w,h)/70, largest region with holes filled, total-least-squares
   sides.
6. Region wins if its score is > 1.08× the line score. Reject if the best score is < 0.42.
7. Least-squares refinement, then `_finish`: area ≥ 0.08, convex, pulled 0.8 % inward.
   "Nothing found" is the `_fallback` inset quad (4.5 %).

**Consequence:** the native detector must be a **port** of this algorithm, so the existing
tests keep passing, plus an extra OpenCV contour candidate. Swapping in a generic
Canny + findContours detector (as revision 1 planned) would drop tuned behaviour such as
pages that run off the frame or dim corners.

---

## 2. Goals and non-goals

Goals, all measured in WP0 (before) and WP6/WP7 (after) on the Redmi Note 9S:

| ID | Goal | Target |
|---|---|---|
| G1 | Preview fluidity during live detection | Janky UI frames ≤ 1 % over 60 s (janky = build or raster > 16.7 ms), and at most half of the WP0 baseline |
| G2 | UI-isolate time spent per camera frame (`_onFrame`) | p95 ≤ 1.0 ms |
| G3 | Native detection latency, 720p Y plane → corners | p95 ≤ 15 ms (measure; revise once after WP3 if the 720G can't reach it, and record why) |
| G4 | Effective detection rate | 8–12 Hz, capped by `minIntervalMs` |
| G5 | Detection quality | All existing `scan_engine_test.dart` corner expectations pass on the native port; "no page" images return no page |
| G6 | Time from shutter to processed thumbnail | ≥ 40 % less than the WP0 baseline (WP7) |
| G7 | Photo quality | Capture resolution raised (WP7 A/B, user sign-off) without losing G6 |
| G8 | Safety | Library missing, wrong ABI, bad args or a failed self-test → the Dart path runs, with no crash and no UI change |

Non-goals: replacing `camera` with our own camera plugin (only WP8, and only if its gate
trips), OCR in the live loop, iOS native (it falls back to Dart), and visual redesign.

---

## 3. Architecture decision

### 3.1 Chosen: the C++ library owns the worker thread

```
 camera_android (Java bg thread) ──EventChannel──▶ UI isolate (merged main thread)
                                                     _onFrame(CameraImage)
                                                       │ scanner_submit_gray(...)   ← leaf FFI call
                                                       │   busy? → return 0 (frame skipped, no copy)
                                                       │   idle? → memcpy Y plane into the input slot,
                                                       │           signal the worker, return seq
                                                       ▼
                                       libscanner.so worker std::thread (one per live Scanner)
                                         resize → rotate → detect → score
                                         calls result_cb(seq, status, conf, 8 corners,
                                                         luma, sharpness, micros)
                                                       │  NativeCallable.listener (posts to the UI isolate)
                                                       ▼
                                     UI isolate: LiveDetector → ValueNotifier<LiveQuad?>
                                       → only the outline painter repaints
```

This matches the requested API (init, submit a frame, get the result) and the
"isolated thread + frame skip" requirement. It's better than a Dart worker isolate for five
reasons:

1. **No Dart isolate, no ports, no pointer hand-off between isolates.** The frame skip is
   one atomic flag in C++ (`busy`). A skipped frame costs about 1 µs and copies nothing.
2. **Zero intermediate copies.** `plane.bytes.address` is passed straight to a leaf FFI
   call (Dart ≥ 3.5, verified), and C++ copies into its own slot only when it accepts the
   frame. Revision 1 needed a copy into a malloc buffer plus an isolate message.
3. **No GC on the worker.** All working buffers (`cv::Mat`) are allocated once and reused.
4. **Result push without polling.** `NativeCallable.listener` can be called from any native
   thread. Dart gets the result on its event loop (verified, Dart ≥ 3.1).
5. The same library and code run on Windows as `scanner.dll`, so `flutter test` can test
   the whole engine (sync and async) on the PC with no phone.

The sync API (`scanner_detect_gray` / `_rgb`) is also exported. It's used by tests, by the
capture path (inside the existing `compute` isolate) and by the self-test. If the async
engine ever needs replacing with a Dart worker isolate, that Dart isolate can call the sync
API instead. The C API doesn't change.

### 3.2 Rejected options (keep them rejected unless a WP gate says otherwise)

| Option | Why not |
|---|---|
| Dart worker isolate + ping-pong buffers (revision 1) | More moving parts (two-sided buffer ownership, isolate messages) for the same work. A native crash kills the process either way, so an isolate doesn't add safety. |
| `compute()` per frame (today) | Isolate spawn and message copy at every detection. |
| `opencv_dart` / `dartcv4` | Native-assets hooks and Conan build trees create links (os error 448). Large prebuilt binaries. |
| Official OpenCV Android SDK / Maven AAR | Full shared `libopencv_java4.so` (tens of MB). The 5.0 notes say the original SDK zip needs a "16kb-page-fix" package for Google Play (verified). |
| Switching to `camera_android_camerax` | The app pins `camera_android` 0.10.13 on purpose (direct dependency). CameraX still sends every analysed frame to Dart. Not worth the risk now. |
| Our own camera plugin, or vendoring `camera_android` with a JNI frame tap | Removes the per-frame channel cost (section 1.1), but it's a fork to maintain. **Kept as WP8, behind a measured gate.** |
| `opencv-mobile` prebuilt packages | Good **fallback** if building OpenCV from source is blocked (section 11). Not the default, because we want a pinned and reproducible build with KleidiCV. |

### 3.3 Why OpenCV, and the "library that runs directly on the processor"

- On Android arm64, OpenCV's imgproc runs through two CPU acceleration layers: **Carotene**
  (NEON) and **Arm KleidiCV** (NEON/SVE/SME HAL). KleidiCV is on by default for Android
  AArch64 builds since OpenCV 4.11, and OpenCV downloads it at configure time (verified).
  Arm reports up to 5× speedups on some core functions. This is the "runs directly on the
  processor" acceleration for edge and page detection. No GPU and no extra runtime.
- **OCR is not a page detector.** Running OCR per frame would add CPU and heat. See
  section 10 for where OCR fits.

---

## 4. Native library

### 4.1 Layout (all new)

```
app/native/
  README.md                   versions, build commands, measurements, troubleshooting
  build_opencv.ps1            -Target android-arm64 | windows-x64  (idempotent)
  build_host.ps1              builds scanner.dll for flutter test
  check_alignment.ps1         16 KB checks on the built APK (WP2)
  scanner/
    CMakeLists.txt            shared by Gradle (Android) and the host build
    include/scanner.h         the C API, the only header Dart mirrors
    src/api.cpp               extern "C" wrappers: arg checks, try/catch, error codes
    src/types.hpp             internal structs (Quad, Candidate, Work buffers)
    src/prep.cpp              downscale, rotate, levels, blur, grey
    src/edges.cpp             EdgeMap: Sobel on the strongest channel, NMS, top 12 %
    src/lines.cpp             oriented Hough, lineQuad
    src/region.cpp            backgroundModel, pageRegion, regionQuad
    src/contour.cpp           NEW candidate 3: Canny + findContours + approxPolyDP
    src/score.cpp             quadScore (shared by all candidates)
    src/fit.cpp               fitSide (TLS), fitCornersPx, finish, isConvex, quadArea
    src/detector.cpp          detect(): orchestrates the candidates (mirrors detectCorners)
    src/metrics.cpp           mean luma, Laplacian-variance sharpness
    src/engine.cpp            worker thread, input slot, callback, rate cap
    src/photo.cpp             JPEG decode (EXIF), reduced decode, resize, RGB out
    src/stub.cpp              built instead of src/*.cpp when OpenCV for the ABI is missing
  third_party/                git-ignored: OpenCV source and the built static libraries
    opencv-src/               shallow clone at the pinned tag
    opencv/<ver>/android-arm64-v8a/   install prefix
    opencv/<ver>/windows-x64/         install prefix
  build/                      git-ignored: host build output (scanner.dll)
lib/native/
  scanner_bindings.dart       hand-written dart:ffi bindings (no ffigen) and the loader
  live_detector.dart          LiveDetector interface + Native and Dart implementations
  photo_prep.dart             native JPEG → RgbImage + corners, with a Dart fallback
  scan_stats.dart             debug counters (SCAN_DEBUG)
test/
  native_scanner_test.dart    parity and robustness on scanner.dll (skips if it's missing)
  native_engine_test.dart     async engine on scanner.dll (skips if it's missing)
```

Add to `app/.gitignore`: `/native/third_party/` and `/native/build/`.

### 4.2 C API: `native/scanner/include/scanner.h` (stable surface)

```c
#pragma once
#include <stdint.h>
#ifdef _WIN32
#  define SCANNER_API __declspec(dllexport)
#else
#  define SCANNER_API __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif

#define SCANNER_ABI_VERSION 1

/* Status codes (int32). >= 0 is success. */
enum {
  SCANNER_OK         =  0,  /* page found (confidence >= threshold) */
  SCANNER_NO_PAGE    =  1,  /* ran fine, no page; corners undefined, confidence < threshold */
  SCANNER_E_ARGS     = -1,  /* null pointer, w/h/stride/len inconsistent, rotation not 0/90/180/270 */
  SCANNER_E_INTERNAL = -2,  /* caught cv::Exception / std::exception / bad_alloc */
  SCANNER_E_STATE    = -3,  /* e.g. submit on a Scanner that isn't started */
  SCANNER_E_DECODE   = -4,  /* JPEG could not be decoded */
  SCANNER_E_STUB     = -5,  /* library built without OpenCV for this ABI */
};

typedef struct ScanResult {
  float corners[8];    /* x0,y0..x3,y3 normalised 0..1 in UPRIGHT space, order TL,TR,BR,BL */
  float confidence;    /* 0..1; the best quadScore of detectCorners (same scale as the 0.42 cut) */
  float mean_luma;     /* 0..255, whole frame */
  float sharpness;     /* Laplacian variance inside the quad (0 when no page) */
  int32_t micros;      /* time spent in detect, microseconds */
  int32_t candidate;   /* 1 lines, 2 region, 3 contour, 0 none (for debugging) */
} ScanResult;

typedef struct ScannerConfig {
  int32_t work_long_side;   /* default 300, the same as detectCorners */
  float   min_confidence;   /* default 0.42 */
  int32_t min_interval_ms;  /* async engine rate cap, default 90 (≈11 Hz) */
  int32_t enable_contour;   /* candidate 3 on/off, default 1 */
} ScannerConfig;

typedef void (*scanner_result_cb)(int32_t seq, int32_t status, float confidence,
    float x0, float y0, float x1, float y1, float x2, float y2, float x3, float y3,
    float mean_luma, float sharpness, int32_t micros);

SCANNER_API int32_t     scanner_abi_version(void);       /* SCANNER_ABI_VERSION, or SCANNER_E_STUB */
SCANNER_API const char* scanner_version(void);           /* "scanner 1.0.0; opencv 4.14.0; kleidicv on" (static string) */
SCANNER_API void        scanner_default_config(ScannerConfig* out);
SCANNER_API void*       scanner_create(const ScannerConfig* cfg);   /* NULL on failure */
SCANNER_API void        scanner_destroy(void* s);                    /* stops the engine if started */

/* Sync detection. Safe on any thread, but one call at a time per Scanner. */
SCANNER_API int32_t scanner_detect_gray(void* s, const uint8_t* px, int32_t len,
    int32_t w, int32_t h, int32_t stride, int32_t rotation_cw, ScanResult* out);
SCANNER_API int32_t scanner_detect_rgb(void* s, const uint8_t* px, int32_t len,
    int32_t w, int32_t h, int32_t stride, ScanResult* out);

/* Async live engine. One worker thread per started Scanner. */
SCANNER_API int32_t scanner_start(void* s, scanner_result_cb cb);   /* idempotent */
/* Leaf-safe: never calls back into Dart, never blocks on the worker.
   Returns seq > 0 if accepted, 0 if skipped (busy or rate cap), < 0 on error. */
SCANNER_API int32_t scanner_submit_gray(void* s, const uint8_t* y, int32_t len,
    int32_t w, int32_t h, int32_t stride, int32_t rotation_cw);
/* Blocks until the worker has exited. No callback runs after this returns. */
SCANNER_API void    scanner_stop(void* s);
/* Stops and destroys every Scanner still alive (debug hot restart). */
SCANNER_API void    scanner_shutdown_all(void);

/* Capture path. Decodes the JPEG, applies EXIF orientation, scales the long side to <= max_side
   (uses reduced DCT decode when the source is >= 2x), optionally detects on the colour image. */
typedef struct PhotoResult {
  uint8_t* rgb;        /* w*h*3, owned by the library; free with scanner_free_photo */
  int32_t  w, h;
  ScanResult scan;     /* filled when detect != 0 */
  int32_t  status;     /* status of the detection part */
} PhotoResult;
SCANNER_API int32_t scanner_prepare_jpeg(void* s, const uint8_t* jpeg, int32_t len,
    int32_t max_side, int32_t detect, PhotoResult* out);
SCANNER_API void    scanner_free_photo(PhotoResult* p);

#ifdef __cplusplus
}
#endif
```

Hard rules for `api.cpp`:

1. Wrap every exported body in `try { … } catch (...) { return SCANNER_E_INTERNAL; }`.
   Exceptions never cross the boundary.
2. Check arguments **before** reading memory: `px && out && w >= 16 && h >= 16 && w <= 8192 &&
   h <= 8192 && stride >= w (×3 for RGB) && len >= stride*(h-1) + w*bpp`, and the rotation
   is one of 0/90/180/270. This is the only defence against a segfault. A native crash
   **can't be caught** by Dart or by an isolate; it kills the app.
3. `cv::setNumThreads(1)` once, inside `scanner_create`. Images are small, and an OpenCV
   thread pool would compete with the UI and raster threads. Also set `cv::setUseOptimized(true)`.
4. Keep `scanner_submit_gray` leaf-safe: no locks held for longer than the memcpy, no
   allocation after warm-up, no callback.
5. Pre-allocate every working `cv::Mat` in the Scanner and reuse it (`Mat::create` with the
   same size is a no-op).

### 4.3 Engine (`engine.cpp`)

```
struct Engine {
  std::thread worker; std::mutex m; std::condition_variable cv;
  std::atomic<bool> busy{false}, running{false};
  std::vector<uint8_t> slot;      // tightly packed Y (w*h), resized only on a size change
  int w,h,rot; int32_t seq=0;     // seq increments per accepted frame
  int64_t last_start_ms=0;        // rate cap
  scanner_result_cb cb;
};
submit:  if (!running) return E_STATE;
         if (now - last_start_ms < min_interval_ms) return 0;
         if (busy.exchange(true)) return 0;              // drop: worker still on the previous frame
         copy rows (stride → packed) into slot; set w,h,rot; ++seq; last_start_ms = now;
         {lock; pending = true;} cv.notify_one(); return seq;
worker:  loop { wait(pending || !running); if (!running) break; pending=false;
                status = detect_gray(slot…, &r); cb(seq, status, r…); busy=false; }
stop:    {lock; running=false;} cv.notify_one(); worker.join();
```

- **Frame skip** happens in two places: Dart doesn't call submit while `shooting`, and C++
  returns 0 while busy or inside the rate cap. A dropped frame isn't queued, so the worker
  always processes the freshest frame that arrived after it went idle.
- **Ordering:** results come back in `seq` order because there's one worker. Dart still
  ignores a `seq` lower than the last one it applied (it can happen after `stop()`/`start()`).
- **Thread priority:** leave the default (nice 0). Flutter's UI and raster threads already
  run above it. Revisit only if WP6 shows the worker starving the UI.
- **Global registry:** keep a static `std::mutex` plus a `std::set<Scanner*>`.
  `scanner_shutdown_all()` stops and destroys every entry. Dart calls it once, at the first
  load of the library in an isolate (see 5.1), so a **debug hot restart** (old isolate gone,
  native thread still alive, `NativeCallable` closed) can't call a dead callback.

### 4.4 Detector port (`detector.cpp` and friends)

Port function by function from `lib/scan_engine.dart`. Keep the names close
(`edgeMapBuild`, `houghLines`, `lineQuad`, `quadScore`, `regionQuad`, `backgroundModel`,
`pageRegion`, `fitSide`, `fitCornersPx`, `finish`), keep every constant, and add a comment
with the Dart line it came from.

| Dart | C++ implementation | Exactness note |
|---|---|---|
| Area-averaged 300 px copy (RGB) | `cv::resize(..., INTER_AREA)` | Small numeric difference. Accepted if the parity tests pass. |
| Live input (grey Y) | `cv::resize(INTER_AREA)` of the Y plane, then `cv::rotate` to upright | Replaces the 200 px nearest-neighbour + RGB expansion in `_detectLive`. Live and photo run the same 300 px detector. Grey input → the edge map uses the single channel (same as Dart on a grey image). |
| Rotation mapping | sensor 90 → `ROTATE_90_CLOCKWISE`; 270 → `ROTATE_90_COUNTERCLOCKWISE`; 180 → `ROTATE_180` | Must match `_detectLive` (sensor 90: `px = sh-1-y, py = x`). A unit test covers it (WP3). |
| Levels 1 % / 99 % per channel | Manual 256-bin histogram per channel, then `convertTo` with alpha/beta | Port exactly (`span = max(16, hi-lo)`). |
| `_gaussian(σ 1.2)` | `cv::GaussianBlur(src, dst, {0,0}, 1.2, 1.2, BORDER_REPLICATE)` | Check the Dart border handling in `processing.dart:317`, and pick the matching `BORDER_*`. |
| Grey 0.299/0.587/0.114 | Float math on the levelled small image (not `cvtColor` on 8-bit) | Avoids rounding drift. |
| `_EdgeMap.build` (Sobel on the strongest channel, direction, NMS, top 12 %, `near`) | `cv::Sobel` (ksize 3, `CV_32F`) per channel → choose the max magnitude per pixel → manual NMS loop → `std::nth_element` for the 88th percentile | The Dart Sobel is a plain 3×3, the same as OpenCV ksize 3. |
| `_houghLines` (oriented voting ±6°, 26 lines, suppression) | Manual port (`cv::HoughLines` has no per-pixel orientation window) | Plain loops on about 300×225; cheap in C++. |
| `_lineQuad`, `_quadScore` | Manual port | Shared by every candidate. |
| `_backgroundModel` + `_solve` | `cv::solve(A, b, x, DECOMP_SVD)` | Same least squares. |
| `_pageRegion`: Otsu, opening/closing radius min(w,h)/70, largest region, fill holes | Port `_otsu` exactly on the same histogram. Morphology = `cv::erode`/`cv::dilate` with `MORPH_RECT` size 2r+1 (the Dart `_morph` is separable nearest-within-r, a square/Chebyshev kernel). Largest region = `connectedComponentsWithStats`. Holes = `floodFill` from the border on the inverted mask. | Check that `_morph` treats the border as "not want". OpenCV's default border for erode/dilate has the same effect. |
| `_fitSide` (TLS, ends ignored) | `cv::fitLine(DIST_L2)` is total least squares | Keep the "ignore the ends" selection before fitting. |
| `_finish`, `_isConvex`, `_quadArea` | Manual port | Area ≥ 0.08, convex, 0.8 % inward pull. |
| `_fallback` sentinel | Not used. Return `SCANNER_NO_PAGE` | Dart maps NO_PAGE to `null` (the same meaning as `_isFallback`). |
| **New: candidate 3, contour** | Canny with thresholds 0.66/1.33 × the median of the blurred grey → `morphologyEx(CLOSE, 3×3)` → `findContours(RETR_LIST)` → for each contour with area ≥ 8 %: `approxPolyDP(0.02·perimeter)` → convex 4-gon → order the corners → score with **the same** `quadScore` | Wins only if its score is > 1.08× the current best (the same rule as the region candidate). Behind `enable_contour` so it can be A/B'd. |

`metrics.cpp`: `mean_luma` from a strided sample of the full-resolution Y plane (every 8th
pixel). `sharpness` = variance of `cv::Laplacian(CV_16S, ksize 1)` on the work-size grey
inside the quad's bounding box, shrunk by 10 %. It's informative until WP7 calibrates a
threshold. It's **not** on the same scale as `isBlurry`'s 30, which is measured on the
flattened page at ≤ 800 px.

### 4.5 Capture path (`photo.cpp`)

- `cv::imdecode(buf, IMREAD_COLOR)` honours EXIF orientation by default (opt out with
  `IMREAD_IGNORE_ORIENTATION`). If `max(src) >= 2*max_side`, use `IMREAD_REDUCED_COLOR_2`
  (or `_4`), which scales in the DCT domain and is much faster. **Check that the reduced
  flags also apply EXIF**: WP7 has a test with an orientation-6 JPEG. If they don't, decode
  reduced, then rotate manually from the EXIF tag read by our own 30-line parser.
- Resize with `INTER_AREA` to `max_side` (1600, the same as `_captureJob`), convert BGR→RGB,
  and copy into a `malloc`'d buffer that Dart frees with `scanner_free_photo`.
- If `detect != 0`, run `detect_rgb` on the result (colour, the same detector).

### 4.6 `CMakeLists.txt` (shared)

```cmake
cmake_minimum_required(VERSION 3.22)
project(scanner CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(OPENCV_VER 4.14.0)
if(ANDROID)
  set(OCV_PREFIX "${CMAKE_CURRENT_LIST_DIR}/../third_party/opencv/${OPENCV_VER}/android-${ANDROID_ABI}")
else()
  set(OCV_PREFIX "${CMAKE_CURRENT_LIST_DIR}/../third_party/opencv/${OPENCV_VER}/windows-x64")
endif()
find_package(OpenCV CONFIG QUIET
  PATHS "${OCV_PREFIX}" "${OCV_PREFIX}/sdk/native/jni" "${OCV_PREFIX}/lib/cmake/opencv4"
  NO_DEFAULT_PATH COMPONENTS core imgproc imgcodecs)
if(OpenCV_FOUND)
  file(GLOB SRC src/*.cpp)
  list(FILTER SRC EXCLUDE REGEX "stub\\.cpp$")
  add_library(scanner SHARED ${SRC})
  target_link_libraries(scanner PRIVATE opencv_imgcodecs opencv_imgproc opencv_core)
else()
  message(WARNING "OpenCV not found at ${OCV_PREFIX}: building the stub library")
  add_library(scanner SHARED src/stub.cpp)
endif()
target_include_directories(scanner PRIVATE include)
if(ANDROID)
  target_compile_options(scanner PRIVATE -O2 -fvisibility=hidden -fvisibility-inlines-hidden
                         -ffunction-sections -fdata-sections)
  target_link_options(scanner PRIVATE -Wl,--gc-sections -Wl,--exclude-libs,ALL
                      -Wl,-z,max-page-size=16384 -Wl,--build-id=sha1)
  target_link_libraries(scanner PRIVATE log)
endif()
```

- `stub.cpp` exports the same symbols. `scanner_abi_version()` returns `SCANNER_E_STUB`;
  everything else returns `SCANNER_E_STUB`, NULL or does nothing. This keeps the **fat APK**
  building (Flutter's default `flutter build apk --release` builds armeabi-v7a, arm64-v8a
  and x86_64). Those ABIs get the stub, so Dart falls back. No `abiFilters` fight with the
  Flutter Gradle plugin.
- The path of the OpenCV config file in the install prefix differs by platform. WP1 records
  the real path in `native/README.md` and fixes the `PATHS` list.

### 4.7 OpenCV build (`native/build_opencv.ps1`)

- **Version: pin 4.14.0** (the latest 4.x, 2026-07-19, verified on GitHub releases). The
  4.x line is in maintenance and stable. 5.0/5.1 exist (5.1.0, 2026-11-06), but only a
  core/imgproc/imgcodecs subset is needed and 4.x carries less churn. Upgrading later is a
  one-line change plus re-running the tests.
- Source: `git clone --depth 1 --branch 4.14.0 https://github.com/opencv/opencv.git
  native/third_party/opencv-src` (skip if it's already there). No contrib.
- Toolchain: NDK **28.2.13676358** (= `flutter.ndkVersion` in Flutter 3.47.2; installed;
  r28+ links with 16 KB alignment by default). CMake and Ninja from
  `%LOCALAPPDATA%\Android\Sdk\cmake\3.22.1\bin`.
- Configure flags (android-arm64):

```
-G Ninja -DCMAKE_MAKE_PROGRAM=<sdk>/cmake/3.22.1/bin/ninja.exe
-DCMAKE_TOOLCHAIN_FILE=<sdk>/ndk/28.2.13676358/build/cmake/android.toolchain.cmake
-DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 -DANDROID_STL=c++_static
-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=<prefix>
-DBUILD_LIST=core,imgproc,imgcodecs
-DBUILD_JAVA=OFF -DBUILD_opencv_java=OFF -DBUILD_ANDROID_PROJECTS=OFF -DBUILD_ANDROID_EXAMPLES=OFF
-DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOCS=OFF -DBUILD_opencv_apps=OFF
-DWITH_KLEIDICV=ON -DWITH_CAROTENE=ON
-DWITH_JPEG=ON -DBUILD_JPEG=ON -DBUILD_ZLIB=ON
-DWITH_PNG=OFF -DWITH_TIFF=OFF -DWITH_WEBP=OFF -DWITH_OPENJPEG=OFF -DWITH_JASPER=OFF
-DWITH_OPENEXR=OFF -DWITH_AVIF=OFF -DWITH_SPNG=OFF -DWITH_IMGCODEC_HDR=OFF
-DWITH_IMGCODEC_SUNRASTER=OFF -DWITH_IMGCODEC_PXM=OFF -DWITH_IMGCODEC_PFM=OFF
-DWITH_OPENCL=OFF -DWITH_IPP=OFF -DWITH_ITT=OFF -DWITH_TBB=OFF -DWITH_OPENMP=OFF
-DWITH_EIGEN=OFF -DWITH_LAPACK=OFF -DWITH_PROTOBUF=OFF -DWITH_ADE=OFF -DWITH_FFMPEG=OFF
-DWITH_ANDROID_MEDIANDK=OFF -DWITH_VULKAN=OFF -DOPENCV_ENABLE_NONFREE=OFF
-DCMAKE_C_FLAGS="-ffunction-sections -fdata-sections"
-DCMAKE_CXX_FLAGS="-ffunction-sections -fdata-sections"
```

- windows-x64 host: the same `BUILD_LIST` and codec flags, `-G "Visual Studio 17 2022" -A x64`
  (VS 2022 Community is installed), static `/MT` runtime (`-DBUILD_WITH_STATIC_CRT=ON`) so
  `scanner.dll` has no extra DLL dependencies. KleidiCV and Carotene are ARM-only, so they're
  ignored on x64.
- The script prints and saves to `native/README.md`: the configure summary lines for
  `KleidiCV`, `Carotene`, `JPEG`, and `Parallel framework` (must read "none" or "pthreads"
  with `setNumThreads(1)` used at runtime), plus the size of every `.a`/`.lib`.
- **Network:** configuring downloads KleidiCV (and libjpeg-turbo comes from the
  3rdparty tree). If the download fails, re-run once. If it still fails, set
  `-DWITH_KLEIDICV=OFF`, note it in the README, and continue (Carotene still accelerates).

---

## 5. Dart side

### 5.1 `lib/native/scanner_bindings.dart`

- `ScannerLib? ScannerLib.instance`, loaded lazily **once per isolate**:
  - Android → `DynamicLibrary.open('libscanner.so')`.
  - Windows → only if `Platform.environment['SCANNER_DLL']` is set or
    `native/build/host/bin/scanner.dll` exists relative to `Directory.current` (tests).
    The Windows desktop app doesn't bundle it, so it uses the Dart path.
  - Anything else, or any exception, or `scanner_abi_version() != 1` → `null`.
- After the first successful load **in the root isolate**, call `scanner_shutdown_all()`
  (hot-restart safety, 4.3). Don't call it from `compute` isolates (they'd stop the live
  engine): pass `isRoot: true` only from `LiveDetector`.
- `lookupFunction<…>(…, isLeaf: true)` for `scanner_submit_gray` and `scanner_detect_*`.
  Not leaf for `scanner_stop` / `scanner_start` (they may block).
- `final class ScanResult extends Struct` mirrors the C struct field by field.
  `@Array(8) external Array<Float> corners;`.
- **Self-test** at first load (`ScannerLib.selfTest()`): build a 320×240 grey image with a
  bright rotated rectangle (draw it in Dart), call `scanner_detect_gray`, expect status
  `OK` and every corner within 0.03 of the drawn ones. If it fails, `instance = null` for
  this run and log `SCANNER selftest failed`. Cost < 5 ms, once.
- Build flags: `const kNativeDetector = bool.fromEnvironment('NATIVE_DETECTOR', defaultValue: true);`
  When false, never load (forces the Dart path for A/B runs).

### 5.2 `lib/native/live_detector.dart`

```dart
class LiveQuad { final List<double> c; final double conf; const LiveQuad(this.c, this.conf); }
class LiveResult { final int seq; final LiveQuad? quad; final double luma, sharpness; final int micros; }

abstract class LiveDetector {
  /// Native if the library loaded and passed its self-test, else Dart.
  factory LiveDetector.create(void Function(LiveResult) onResult);
  bool get isNative;
  /// Called from _onFrame for every frame. Returns true if the frame was taken.
  bool offer(CameraImage image, int sensorOrientation);
  void dispose();
}
```

- `_NativeLiveDetector`:
  - Constructor: `scanner_create(defaults)`, then
    `NativeCallable<ResultCbNative>.listener(_onNative)`, then
    `scanner_start(s, callable.nativeFunction)`.
  - `offer`: `final p = image.planes.first; scanner_submit_gray(s, p.bytes.address,
    p.bytes.length, image.width, image.height, p.bytesPerRow, sensorOrientation)`.
    If the analyzer rejects `.address` on that view, fall back to a reused
    `calloc<Uint8>(len)`: `ptr.asTypedList(len).setAll(0, p.bytes)` and pass `ptr`
    (one 0.9 MB memcpy, only when the frame is accepted: check `scanner_is_busy` first,
    so add that export too in that case).
  - `_onNative(seq, status, conf, x0..y3, luma, sharp, micros)`: ignore if disposed or
    `seq <= lastSeq`; else build a `LiveResult` (quad null unless status == 0) and call
    `onResult`.
  - `dispose`: set `disposed`, `scanner_stop(s)` (joins; no callback after),
    `callable.close()`, `scanner_destroy(s)`. **This order is mandatory.**
- `_DartLiveDetector`: the current behaviour moved out of `ui_camera.dart` unchanged
  (`_Frame`, `_detectLive`, `_isFallback`, the 300 ms throttle, the busy flag,
  `compute`). It also computes `luma` with the existing sparse loop so the "dark" hint keeps
  working.
- Both implementations report `luma` in every result. The native one computes it in C++,
  so `_onFrame` no longer loops over the plane.

### 5.3 `lib/ui_camera.dart` changes (the only existing file changed until WP7)

1. Fields: replace `List<double>? quad, shownQuad; bool detecting; DateTime lastDetect;`
   with `late final LiveDetector detector;` and
   `final ValueNotifier<List<double>?> quadN = ValueNotifier(null);`. Keep `bool hasQuad`
   (state) for the hint and the overlay's visibility.
2. `initState`: `detector = LiveDetector.create(_onResult);`. `dispose`:
   `detector.dispose(); quadN.dispose();` **before** `cam.dispose()`.
3. `_onFrame`: keep the `gotFrame` first-frame `setState`. Then
   `if (shooting || processing != null) return; detector.offer(image, sensor);`. Nothing else.
4. `_onResult(LiveResult r)`:
   - `brightness = r.luma`. `setState` **only** when `_dark` flips (the same rule as today)
     or when `hasQuad` flips (quad null ↔ non-null).
   - `quadN.value = r.quad?.c` (keep the last non-null value for painting, as `shownQuad`
     did).
   - Run the stability and auto-capture logic of `_updateQuad` unchanged (`_moved < 0.04`,
     stable > 1000 ms → `_shoot()`).
5. Overlay: replace the `TweenAnimationBuilder` block with
   `ValueListenableBuilder<List<double>?>(valueListenable: quadN, builder: …)` wrapping the
   **same** `TweenAnimationBuilder<_QuadValue>` + `_DetectPainter`. Wrap it in a
   `RepaintBoundary`. The visibility condition stays
   `hasQuad && processing == null && shotQuad == null`.
6. Keep every Spanish string and every visual value. No design change
   (`design/specs/04-06-camara.md`).
7. `_shoot` uses the last `quadN.value` where it used `quad`.

### 5.4 `lib/native/photo_prep.dart` (WP7)

```dart
/// Inside a compute isolate. Native when available, else decodePhoto + resize (today's code).
(RgbImage, List<double>?)? preparePhoto(Uint8List jpeg, {required int maxSide, required bool detect});
```

- Native: creates its own Scanner (not started), calls `scanner_prepare_jpeg`, copies
  `rgb` into a Dart `Uint8List` (`Uint8List.fromList(ptr.asTypedList(w*h*3))`), calls
  `scanner_free_photo`, destroys the Scanner, and returns `RgbImage(w, h, bytes)` plus the
  corners (null if NO_PAGE).
- `_captureJob` in `ui_camera.dart`: replace `decodePhoto` + the 1600 resize + `detectCorners`
  with `preparePhoto`. On a null result, run today's code unchanged. `flattenPage`,
  `isBlurry`, `applyFilter` and `encodeJpeg` stay (`processing.dart` isn't touched).
- `_import` uses the same `_captureJob`, so it gains the speed-up for free.
- `ui_edit.dart`'s `detectCornersAsync` may switch to `preparePhoto` too (optional, WP7
  step 6).

### 5.5 `lib/native/scan_stats.dart` (WP0, debug only)

- `const kScanDebug = bool.fromEnvironment('SCAN_DEBUG');` All code is behind it. Zero cost
  in normal builds.
- Counters: frames in (`_onFrame` calls/s), frames offered and accepted, detection
  results/s, detect µs (native: `micros`; Dart: a stopwatch around `compute`), `_onFrame`
  duration (a `Stopwatch` around the body), shutter → thumbnail ms (from `_shoot` start to
  `pages.add`), UI frames from `SchedulerBinding.instance.addTimingsCallback` (janky if
  `buildDuration` or `rasterDuration` > 16.7 ms).
- Every 5 s it prints one line to logcat:
  `SCANSTATS path=native fps_in=29.7 det_hz=10.9 det_ms_p50=5.8 det_ms_p95=9.4 onframe_ms_p95=0.31 jank=2/300 worst_ms=21.0 skipped=187`.
  After each shot it prints `SCANSHOT ms=1234 w=1920 h=1080`.
- On the first frame it prints `SCANCAM stream=1280x720 sensor=90` (verifies section 1.1).
  After each picture it prints the JPEG width and height.

---

## 6. Android build wiring (`android/app/build.gradle.kts`)

```kotlin
android {
    // ...existing...
    externalNativeBuild {
        cmake {
            path = file("../../native/scanner/CMakeLists.txt")
            version = "3.22.1"
        }
    }
    defaultConfig {
        // ...existing...
        externalNativeBuild {
            cmake {
                arguments += listOf("-DANDROID_STL=c++_static")
                cppFlags += listOf("-std=c++17")
            }
        }
    }
}
```

- `ndkVersion = flutter.ndkVersion` already pins NDK 28.2.13676358, the same NDK
  `build_opencv.ps1` uses, so the STL and ABI match.
- Don't add `abiFilters` (the stub handles other ABIs, 4.6).
- No ProGuard change (no JNI or Java symbols until WP8).
- **16 KB pages:** NDK r28 + AGP 9.1 align by default. `native/check_alignment.ps1`
  verifies it: `llvm-readelf -l` on every `lib/arm64-v8a/*.so` in the APK (every `LOAD`
  segment `Align` must be `0x4000`), plus `zipalign -c -P 16 -v 4 app-release.apk`. Google
  Play's deadline for apps targeting Android 15+ was 2025-11-01 (verified), so this is a
  release blocker. Check `libscanner.so` **and** the existing plugin libraries; report any
  of the others to the user without fixing them here.
- **APK size:** AGP stores native libraries uncompressed by default (`useLegacyPackaging =
  false`), so the APK grows by the full `.so` size. Expected a few MB for
  core+imgproc+imgcodecs(JPEG)+KleidiCV after `--gc-sections` (measure). If the delta is
  > 8 MB, try `-DWITH_KLEIDICV=OFF` and compare the size against the G3 latency before
  deciding, and record both in the README.

---

## 7. Work packages

Each WP ends with `flutter analyze` clean and `flutter test` green (native tests skip when
`scanner.dll` is missing, so the suite stays green on any PC).

### WP0: Baseline measurements (Dart only, no native code)

Files: `lib/native/scan_stats.dart` (new), `lib/ui_camera.dart` (stats hooks only, behind
`kScanDebug`).
Steps:
1. Add `scan_stats.dart` (5.5). Hook it into `_onFrame`, the `compute` callback, `_shoot`,
   and `_animateCapture`'s `pages.add`. Add the `SCANCAM` logging.
2. **[device]** `flutter run --profile --dart-define=SCAN_DEBUG=true`. Run three sessions
   and save the logcat lines (`adb logcat -s flutter | findstr SCAN`):
   a) 60 s pointed at a page on a desk; b) 60 s at a cluttered desk with no page; c) 5 shots
   in Auto mode.
3. **[device]** Channel-cost probe: the same as (a) but with detection disabled
   (`--dart-define=SCAN_PROBE=stream_only`: `_onFrame` returns right after `gotFrame`),
   then with the stream not started at all (`SCAN_PROBE=no_stream`). The jank difference
   between `no_stream` and `stream_only` is the camera plugin's channel cost. It decides
   WP8.
4. Write every number into `native/README.md` → "Measurements → Baseline (Dart)".

Done when: the README has the stream size, JPEG size, `det_ms` p50/p95, `det_hz`,
`onframe_ms_p95`, jank % for all three probes, and shutter→thumbnail ms for 5 shots.

### WP1: OpenCV static builds

Files: `native/build_opencv.ps1`, `native/README.md`, `app/.gitignore`.
Steps: as in 4.7. Build both `android-arm64-v8a` and `windows-x64`.
Done when: both install prefixes exist; the README lists the exact `OpenCVConfig.cmake`
paths, the configure summary (KleidiCV YES/NO, Carotene, JPEG) and the library sizes;
re-running the script without `-Force` is a no-op.

### WP2: Hello-world library on the phone + alignment

Files: `native/scanner/{CMakeLists.txt, include/scanner.h, src/api.cpp, src/stub.cpp}`
(only `scanner_abi_version`, `scanner_version`, `scanner_default_config`,
`scanner_create`/`destroy` and `scanner_shutdown_all` for now), `native/build_host.ps1`,
`native/check_alignment.ps1`, `android/app/build.gradle.kts`,
`lib/native/scanner_bindings.dart`.
Steps:
1. Implement the files above. `scanner_version()` includes `cv::getVersionString()` and
   whether KleidiCV is in `cv::getBuildInformation()`.
2. `build_host.ps1`: `cmake -S native/scanner -B native/build/host -G "Visual Studio 17 2022"
   -A x64` + `--config Release`, then copy `scanner.dll` to `native/build/host/bin/`.
3. Add `test/native_scanner_test.dart` with one test: the library loads and
   `scanner_abi_version() == 1`.
4. `flutter build apk --release`. Run `check_alignment.ps1`. Record the APK size vs the
   last recorded size (82.4 MB) in the README.
5. **[device]** Install. On the camera screen, in a debug build, log `scanner_version()`.

Done when: the host test passes; `libscanner.so` (arm64) is in the APK and 16 KB aligned;
the armeabi-v7a/x86_64 entries are the stub; the phone logs the version string with
OpenCV 4.14.0.

### WP3: Sync detector port + parity tests (host only, no phone)

Files: `native/scanner/src/{types.hpp, prep.cpp, edges.cpp, lines.cpp, region.cpp, score.cpp,
fit.cpp, detector.cpp, metrics.cpp, api.cpp}`, `lib/native/scanner_bindings.dart`,
`test/native_scanner_test.dart`.
Steps:
1. Port in this order, rebuilding the DLL and running the tests after each step:
   prep → edges → lines → score → fit/finish (candidate 1 alone) → region (candidate 2)
   → the orchestration in `detector.cpp`.
2. Export `scanner_detect_gray` and `scanner_detect_rgb`.
3. Tests in `native_scanner_test.dart`, reusing the fixtures and expected corners of
   `scan_engine_test.dart` (copy the constants, don't import test files):
   - Parity, colour: for each photo in `design/assets/samples/cam_*.jpg` (except `_blur`)
     and `test/fixtures/desk_lamp_*.jpg`: decode with `decodePhoto`, call
     `scanner_detect_rgb`, then require the same tolerance as the Dart test against the
     expected corners **and** `maxDiff(native, detectCorners(photo)) < 0.02`.
   - Parity, dim light: the `dim()` variants (copy the helper) with the same tolerances.
   - Live grey: build a 1280×720 **landscape** Y plane from each fixture (rotate the
     upright photo 90° counter-clockwise, take luma 0.299/0.587/0.114, add a stride
     padding of 64 bytes) → `scanner_detect_gray(..., rotation 90)` → expected within 0.04
     (the same as the Dart live test). Repeat with rotation 270 on the opposite rotation,
     and with 0.
   - No page: `filter_*.png` and `page_*.png` crops that show no table edge, a uniform grey
     image, and seeded random noise → `SCANNER_NO_PAGE`. If a sample really contains a
     page, drop it from this list and say so in a comment.
   - Robustness: null pointer, w=0, stride<w, len too small, rotation 45, a 16×16 image,
     an 8192×8192 image → never crashes, correct error codes.
   - Timing (informational, never fails): print the µs per call on the host.
4. Port note: wherever a numeric choice was needed (border mode, rounding), write it as a
   comment `// Dart: scan_engine.dart:<line>`.

Done when: every parity test passes. If one fails by a small margin and the cause is a
documented numeric difference (INTER_AREA vs the Dart sampling), it's allowed only if the
**Dart-expected** tolerance still passes. Never loosen the expected-corner tolerances.

### WP4: Contour candidate + photo metrics

Files: `native/scanner/src/{contour.cpp, metrics.cpp, detector.cpp}`, the tests.
Steps: implement candidate 3 (4.4) behind `enable_contour`, plus `mean_luma` and
`sharpness`. Add tests: every WP3 parity test passes with `enable_contour = 1` and `= 0`;
add 3 synthetic cases where the contour candidate must win (a white page on a light-grey
table with a soft shadow, and a thick-bordered page drawn in Dart with `package:image`).
Done when: all tests pass both ways; the `candidate` field shows 3 on the synthetic cases.

### WP5: Async engine (host tests)

Files: `native/scanner/src/engine.cpp`, `api.cpp`, `lib/native/scanner_bindings.dart`,
`lib/native/live_detector.dart` (native + Dart implementations), `test/native_engine_test.dart`.
Steps: implement 4.3 and 5.1–5.2. Tests (Dart VM on Windows, real thread):
- start → submit 1 frame → the callback arrives within 2 s with status OK and the right
  corners.
- Submit 100 frames in a tight loop → most return 0 (skipped); every callback `seq` is
  increasing; no crash.
- `min_interval_ms = 200`: 2 s of submits every 10 ms → 8–11 callbacks.
- stop while busy → returns; no callback after stop (the counter doesn't change for 500 ms).
- `scanner_shutdown_all` with 3 started scanners → all threads joined (test returns).
- submit before start → `SCANNER_E_STATE`.
- `_DartLiveDetector` against the same frame → the same quad within 0.04.
Done when: all pass 20 times in a row (a PowerShell loop:
`1..20 | % { flutter test test/native_engine_test.dart; if (-not $?) { throw "run $_ failed" } }`),
so there are no flaky thread races.

### WP6: Camera integration + device measurement

Files: `lib/ui_camera.dart` (5.3).
Steps:
1. Apply 5.3. The Dart path must keep working (`--dart-define=NATIVE_DETECTOR=false`).
2. Existing tests and `flutter analyze` pass.
3. **[device]** Repeat WP0 sessions a–c with the native path. Then repeat (a) with
   `NATIVE_DETECTOR=false`, to check that the ValueNotifier change alone didn't break the
   Dart path.
4. **[device]** Manual checks: the outline follows the page smoothly; auto-capture fires
   after about 1 s steady; "Buscando el documento…" shows with no page; the "Poca luz" hint
   in a dark room; flash toggle; lock/unlock the phone on the camera screen (lifecycle);
   leave and re-enter the camera 10 times (no thread leak: `adb shell ps -T -p <pid> | find /c "scanner"`
   should stay at most 1 while the camera is open, and 0 after it closes).
5. **[device] Experiment (flag `SCAN_KEEP_STREAM`, default off):** don't call
   `stopImageStream`/`startImageStream` around `takePicture` (frames are already ignored
   while `shooting`). Camera2 guarantees PRIV preview + YUV + JPEG for LIMITED/FULL devices.
   Measure the shutter→thumbnail time and watch the preview for the stall. If 10 shots
   work and the stall is gone, make it the default. If `takePicture` errors on the device,
   keep the stop/start.

Done when: G1–G5 are met and recorded (or the misses are recorded with their cause); the
manual checklist passes; the experiment result is recorded and the default is set.

### WP7: Capture path and photo quality

Files: `native/scanner/src/photo.cpp`, `api.cpp`, `lib/native/photo_prep.dart`,
`lib/ui_camera.dart` (`_captureJob` only, plus the preset A/B), tests.
Steps:
1. Implement 4.5 and 5.4.
2. Tests (host): `scanner_prepare_jpeg` on every `cam_*.jpg` → size equals
   `decodePhoto` + the 1600 resize ±1 px, and the mean absolute pixel difference ≤ 3. Make
   an orientation-6 JPEG in the test (`package:image`: rotate + set the EXIF orientation,
   `encodeJpg`) → it must decode upright and match the Dart decode. A corrupt JPEG →
   `SCANNER_E_DECODE`, no crash.
3. Switch `_captureJob` to `preparePhoto` with the Dart fallback.
4. **[device]** Measure shutter→thumbnail (G6), 5 shots, vs the baseline.
5. **[device] Photo quality A/B (needs the user's sign-off):** change the preset to
   `ResolutionPreset.max`. In camera_android 0.10.13 the preview and stream stay capped at
   720p, so live detection cost doesn't change, while the JPEG goes to the largest video
   profile (likely 3840×2160; measure). The aspect stays 16:9, so the live quad still maps
   onto the photo. Record the JPEG size, shutter→thumbnail ms, and a crop of small text from
   both presets into `shots/`. Ask the user to choose. Storage isn't affected much:
   `_captureJob` saves the page at ≤ 1600 px, but `CapturedPage.photo` keeps the original
   JPEG, so check the size growth of a saved document and report it.
6. Optional: `ui_edit.dart` `detectCornersAsync` → native.
7. Optional, calibrated: the **sharp-before-shoot gate**. Log `sharpness` from live results
   while holding the phone steady vs moving it (10 s each) → pick a threshold → Auto mode
   only shoots when stable for 1 s **and** sharpness ≥ the threshold. That cuts the
   "La foto salió movida" retries. Behind a constant, off until calibrated.

Done when: the tests pass; G6 is met or the miss is recorded; the A/B decision is recorded.

### WP8: Native frame tap (conditional)

Gate: do this **only if** the WP6 measurements show that the channel delivery of frames
still causes janky frames (WP0 probe `stream_only` minus `no_stream` > 1 % jank, or G1
missed with native detection on). Otherwise skip it, and record "not needed" with the
numbers.

Design (summary; write a separate plan 16 before implementing):
- Vendor `camera_android` 0.10.13 into `app/packages/camera_android/` (a path dependency,
  same version and license header kept). Path plugins on Android don't use `.plugin_symlinks`.
- In `ImageStreamReader.onImageAvailable`: if `ScannerTap.isActive()`, hand the Y plane's
  direct `ByteBuffer` to `ScannerTap.submit(buffer, w, h, rowStride, rotation)` (JNI into
  `libscanner.so`, `GetDirectBufferAddress`, the same `scanner_submit_gray` on the
  registered live Scanner), and send Dart only every 10th frame and **without plane bytes**
  (so `gotFrame` and the camera health checks keep working).
- `libscanner` gains `scanner_tap_register(void* s)` (called from Dart) and
  `Java_…_ScannerTap_submit`. The result path (`NativeCallable.listener`) doesn't change.
- Result: no per-frame `byte[]` allocation, codec or main-thread work.

### WP9: Native warp and filters (needs explicit user approval)

Unchanged from revision 1: `warpPerspective` + filters in native, replacing the Dart
homography and filters in `processing.dart`. Not started without the user's written
approval (CLAUDE.md). A/B images must match or beat the current filters.

---

## 8. Error handling and fallback matrix

| Situation | Behaviour |
|---|---|
| `libscanner.so` missing / `dlopen` fails | `ScannerLib.instance == null` → `_DartLiveDetector`; `preparePhoto` → Dart code |
| Stub ABI (armeabi-v7a, x86_64 emulator) | `scanner_abi_version() == SCANNER_E_STUB` → the same as missing |
| Self-test fails | The same as missing, for this run; log `SCANNER selftest failed` |
| `scanner_create` returns NULL | `LiveDetector.create` returns the Dart implementation |
| A result with status < 0 | Treated as "no page" for this frame. After 5 consecutive errors, dispose the native detector and switch to Dart for the rest of the screen's life (log it) |
| No callback within 2 s while frames are being offered (stuck worker) | The same switch to Dart. Don't call `scanner_stop` (it could block on a stuck thread); leak that one Scanner on purpose and log it |
| Native segfault | Can't be caught. Prevented by the argument checks, the robustness tests, and running the host tests under the MSVC debug runtime with `/RTC1` once per WP (add a `-Debug` switch to `build_host.ps1`) |
| Debug hot restart | `scanner_shutdown_all()` on the first root-isolate load |
| App goes to background | Unchanged: the camera is disposed, frames stop, and the worker waits idle on its condition variable (0 % CPU) |
| Screen disposed | `detector.dispose()` (stop → close callable → destroy) before `cam.dispose()` |

---

## 9. Performance budget (to validate in WP6/WP7)

| Item | Budget |
|---|---|
| `_onFrame` (UI isolate): offer = leaf call; skip ≈ 1 µs; accept = 0.9 MB row copy | ≤ 0.5 ms p95 |
| Worker: resize 1280×720 → 300×169 (INTER_AREA, KleidiCV) + rotate | ≤ 1.5 ms (measure) |
| Detector at 300 px: candidates 1+2(+3) + refinement | ≤ 12 ms p95 (measure) |
| Callback → UI: one listener message, `ValueNotifier` → overlay repaint only | ≤ 1 ms |
| Rate | `min_interval_ms` 90 → ≤ 11 Hz. Raise to 120 (≈8 Hz) if battery or heat is a problem |
| Memory | Slot 0.9 MB + work Mats < 1 MB. No per-frame allocation after the first frame |

---

## 10. OCR: where it fits, and the research behind it

| Use | Verdict |
|---|---|
| Per-frame OCR to find the page | **No.** OCR finds text, not page borders. It's 10–100× heavier than the detector and would add heat and jank. |
| Searchable text (`OcrScreen`) | Already shipped with `google_mlkit_text_recognition` (on-device, CPU). Keep it. |
| Post-capture orientation (is the text sideways or upside down?) | Optional follow-up after WP7: run ML Kit **once** on the flattened page in the background, and rotate by 90°/180° if the text lines are vertical or upside down. A separate small plan. |
| Blur gate | Not OCR: Laplacian variance (already in `isBlurry`, plus the live `sharpness`, WP7 step 7). |

Engines considered for on-device OCR on the CPU:
- **ML Kit Text Recognition v2** (already a dependency): on-device, the easiest, good
  accuracy on Latin script. Proprietary terms. **Keep it.**
- **PP-OCRv5 mobile** (PaddleOCR, about 5 M parameters, published 2026): strong accuracy
  for its size. Deployable on Android through Paddle Lite (NDK) or ONNX Runtime. No phone
  latency figures were found, and it needs a second native runtime plus models (several
  MB). **Not now**; revisit only if ML Kit's accuracy on Spanish documents falls short.
- **Tesseract**: open source, but heavier `traineddata` and slower in the comparisons found.
  **No.**
- **ML-based page-corner models** (small TFLite/ONNX keypoint networks): could beat
  classic CV on hard backgrounds, but they need a runtime (LiteRT/ONNX) and a model with a
  clear licence. **Not in this plan**; reconsider only if WP3/WP4 detection quality on real
  photos is the bottleneck.

---

## 11. Risks and mitigations

| Risk | Mitigation |
|---|---|
| os error 448 (symlinks) during the native build | The OpenCV build is plain CMake + Ninja in `native/third_party` with no links. Gradle's CMake doesn't use the plugin symlinks. If Gradle's `.cxx` folder still hits 448, set `buildStagingDirectory = file("C:/Users/rudy1/.escaner-cxx")` in `externalNativeBuild.cmake` (outside `Craft Anything`) and record it. |
| Building OpenCV from source is blocked (network, toolchain) | Fallback 1: `-DWITH_KLEIDICV=OFF`. Fallback 2: the nihui `opencv-mobile` prebuilt static package for Android arm64 (core+imgproc, its own JPEG via stb), pinned by release tag. Record which one was used. |
| Numeric drift between the port and Dart breaks the tight corner tests | Port order with tests after each step (WP3); `// Dart:` line comments; documented border and rounding choices. |
| `.address` on the `CameraImage` bytes view is rejected by the analyzer | The `calloc` buffer fallback in 5.2 (one memcpy). |
| `NativeCallable.listener` called after close → undefined behaviour | Mandatory dispose order; `scanner_stop` joins first; `scanner_shutdown_all` on hot restart; the WP5 tests. |
| `IMREAD_REDUCED_*` ignores EXIF orientation | The WP7 orientation-6 test; a manual EXIF parse + rotate as the fallback. |
| APK size | `BUILD_LIST` with three modules, codecs off, gc-sections, exclude-libs; measured in WP2; KleidiCV toggle. |
| 16 KB alignment | NDK r28 + `-z max-page-size=16384` + `check_alignment.ps1` in WP2 and before every release build. |
| The `max` preset slows the capture path | It's coupled with WP7's native decode (reduced DCT decode) and gated by the A/B and the user's sign-off. |
| Keeping the stream during `takePicture` fails on some devices | Behind a flag; measured in WP6; stop/start kept as the fallback. |
| iOS | Out of scope. The loader returns null on iOS, so the Dart path runs. A later port needs a static `libscanner.a` + `DynamicLibrary.process()` and a Mac. The C API and the Dart bindings are shared. |

---

## 12. Sources (checked 2026-11-17)

Code (verified locally):
- `camera_android-0.10.13`: `features/resolution/ResolutionFeature.java` (preview capped at
  `high`, line 127; capture size = the video profile); `media/ImageStreamReader.java` (every
  plane copied to `byte[]`, posted to the main looper); `Camera.java`
  (`startPreviewWithImageStream` → `startCapture` → a new capture session).
- Flutter 3.47.2 / Dart 3.13.2 (`flutter.version.json`); `FlutterExtension.kt`:
  `ndkVersion = "28.2.13676358"`, `minSdk 24`, `compileSdk/targetSdk 36`.
- `lib/ui_camera.dart`, `lib/scan_engine.dart`, `lib/processing.dart`,
  `test/scan_engine_test.dart`, `MECHANICS.md`.

Web:
- [OpenCV releases on GitHub](https://github.com/opencv/opencv/releases): 4.14.0 (19 Jul),
  5.0.0 (6 Jun), 5.1.0 (6 Nov); the 5.0 note on the "16kb-page-fix" Android SDK package.
- [What's new in Flutter 3.29](https://flutter.dev/blog/whats-new-in-flutter-3-29) and
  [the itsallwidgets thread on the thread merge](https://forum.itsallwidgets.com/t/how-does-flutter-s-ui-platform-thread-merge-impact-platform-api-calls/2653):
  the platform and UI threads are merged on Android.
- [Improving platform channel performance in Flutter](https://flutter.dev/blog/improving-platform-channel-performance-in-flutter):
  the channel cost scales with the payload.
- [Arm: KleidiCV and OpenCV integration](https://newsroom.arm.com/blog/arm-kleidicv-opencv-integration),
  [KleidiCV 26.03 notes](https://developer.arm.com/community/arm-community-blogs/b/ai-blog/posts/what-s-new-in-kleidicv-26-03-for-computer-vision-on-arm-cpus),
  [Arm learning path: OpenCV + KleidiCV build](https://learn.arm.com/learning-paths/embedded-and-microcontrollers/opencv-onnx-kleidicv-static-detection/2-build-opencv/):
  on by default for Android AArch64 since 4.11, `WITH_KLEIDICV`, downloaded at configure time.
- [Android Developers: transition to 16 KB page sizes](https://android-developers.googleblog.com/2025/07/transition-to-16-kb-page-sizes-android-apps-games-android-studio.html),
  [Supporting 16 KB pages in Flutter apps](https://proandroiddev.com/supporting-16kb-page-sizes-in-your-android-flutter-application-361c6de7bb62).
- [`NativeCallable.listener`](https://api.flutter.dev/flutter/dart-ffi/NativeCallable/NativeCallable.listener.html):
  callable from any thread, void only, undefined behaviour after `close`.
- [Dart SDK: `.address` for FFI leaf calls](https://dart.googlesource.com/sdk.git/+/4b66657b984d41c34250e1e7b80030fcfb6a82a8%5E%21/)
  and the [`address_receiver` diagnostic](https://dart.dev/tools/diagnostics/address_receiver).
- [PP-OCRv5 paper](https://arxiv.org/pdf/2603.24373) and the
  [PaddleOCR on-device deployment docs](https://www.paddleocr.ai/v3.6.0/en/version3.x/inference_deployment/cross_platform/on_device_deployment.html).
- [opencv-mobile](https://github.com/nihui/opencv-mobile): minimal prebuilt OpenCV packages
  (fallback only; check its current release for 16 KB alignment before using it).
- Revision 1 sources still relevant: [Scanbot: Flutter plugin with OpenCV via dart:ffi](https://scanbot.io/techblog/implementing-a-flutter-plugin-with-native-opencv-support-via-dartffi-part-2-2/),
  [opencv_dart](https://pub.dev/packages/opencv_dart/versions/2.0.0-dev.8) (rejected).

---

## 13. What changed from revision 1, and why

| Revision 1 | Revision 2 | Reason |
|---|---|---|
| "Y plane about 2 MB at 1080p" | 720p stream (about 0.9 MB Y) | camera_android caps the preview and stream at `high` (verified in the source). |
| Detection was the main cost | The camera plugin also copies all planes and sends **every** frame through the main thread, which is now the UI thread | The plugin source + Flutter 3.29 thread merge. Measured in WP0; WP8 is the conditional fix. |
| Dart worker isolate + ping-pong buffers | The C++ library owns the worker thread; leaf submit; `NativeCallable.listener` push | Fewer moving parts, no copy into an intermediate buffer, a skip costs about 1 µs, and the same engine is testable on the PC. |
| "If the worker dies, restart it" | A native crash can't be caught; prevention via arg checks and robustness tests; the fallback covers soft failures only | Correctness. |
| A new Canny/contour detector replaces the Dart one | **Port** the tuned Dart detector (the existing tests are the parity bar) + contour as an extra candidate | Keeps tuned behaviour and the original-app parity. |
| No capture-path work until phase 4 | WP7 targets the real post-shutter freeze: the pure-Dart JPEG decode, plus the double session rebuild (WP6 experiment) | That's where the user-visible freeze is. |
| "Better photos" not addressed | `veryHigh` gives about 2 MP; the `max` A/B gives more pixels at the same live cost | Verified capture-size logic. |
| OpenCV version undecided | 4.14.0, KleidiCV on, exact flags | Reproducible and size-controlled. |
| No 16 KB page-size handling | NDK r28, `-z max-page-size=16384`, a check script | Play requirement since 2025-11-01. |
| arm64 `abiFilters` | Stub library for the other ABIs, fat APK unchanged | Avoids fighting Flutter's ABI handling; safe fallback. |
| Phone-only testing | `scanner.dll` + `flutter test` parity, robustness and thread tests on the PC | Lets Claude Code iterate without the device. |
| Hot restart not considered | `scanner_shutdown_all()` | Avoids calling a closed `NativeCallable`. |
| Measurements only after the change | WP0 baseline with the same counters, plus a channel-cost probe | The before/after comparison and the WP8 gate need it. |

## 12. Implementation notes (branch `feature/opencv-ffi-detector`)

Done: phases 0-3 and the photo part of phase 4. Differences from the plan above:

- **One native buffer, not two.** A frame is never submitted while the worker is busy, so ping-pong buffers add nothing; ownership is still strict (UI writes only when idle; the buffer is freed only after the worker says `bye`).
- **Linked by hand** in `CMakeLists.txt` (`libopencv_imgproc.a`, `libopencv_core.a`, `cpufeatures`, `tegra_hal`): the generated `OpenCVConfig.cmake` lists codec libraries we don't build.
- **Overlay:** still `setState`, but only when the outline moved more than 0.006 (or appeared/disappeared); no `ValueNotifier` yet.
- **Detector guards** added after a false positive on a dark scene: reject flat pictures (1%-99% range under 25) and require real contrast across at least half of the quad's edge samples.
- **Photos:** `findCorners` (`lib/native/find_corners.dart`) uses OpenCV when confidence is at least 0.5, else the Dart detector. Used by the capture job and the crop screen.
- **Measured on the Redmi Note 9S (release):** `libscanner.so` 2.84 MB; APK 51.4 MB with arm64 only (was 82.4 MB with 3 ABIs, so not comparable); native detection 3 ms/frame on the first dark frames; about 7.5 detections/s with the 90 ms throttle. Not yet measured with a real page in view.
- Logs: `adb logcat -s flutter | findstr scan:`.

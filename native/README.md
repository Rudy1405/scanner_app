# Native OpenCV (libscanner.so)

One-time setup on a new machine (Windows, PowerShell):

1. Download https://github.com/opencv/opencv/archive/refs/tags/4.12.0.zip and extract it
   to `native/opencv-src/` (so `native/opencv-src/opencv-4.12.0/` exists).
2. `powershell -File native\build_opencv.ps1` (arm64-v8a, about 10-15 min).
3. `flutter build apk --release --target-platform android-arm64`

Gradle compiles `android/app/src/main/cpp` against `native/opencv-android/arm64-v8a`.
Everything under `native/` except the script and this file is git-ignored.
If the library is missing at run time the app falls back to the Dart detector.
See `design/plans/15-opencv-ffi-detector.md`.

# Builds a minimal static OpenCV (core + imgproc) for Android.
# One-time step; Gradle only compiles libscanner.so against the output.
#
#   powershell -File native\build_opencv.ps1            # arm64-v8a
#   powershell -File native\build_opencv.ps1 -Abi armeabi-v7a
#
# Needs: opencv-4.12.0.zip extracted to native\opencv-src (see native\README.md).
param(
  [string]$Abi = 'arm64-v8a',
  [string]$Ndk = '28.2.13676358',   # same as flutter.ndkVersion
  [string]$Cmake = '3.22.1'
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$ndkDir = Join-Path $sdk "ndk\$Ndk"
$cmakeBin = Join-Path $sdk "cmake\$Cmake\bin"
$src = Join-Path $here 'opencv-src\opencv-4.12.0'
$build = Join-Path $here "ocv-build-$Abi"
$out = Join-Path $here "opencv-android\$Abi"

foreach ($p in @($ndkDir, $cmakeBin, $src)) {
  if (-not (Test-Path $p)) { throw "Missing: $p" }
}
$env:PATH = "$cmakeBin;$env:PATH"

& "$cmakeBin\cmake.exe" -S $src -B $build -G Ninja `
  "-DCMAKE_TOOLCHAIN_FILE=$ndkDir\build\cmake\android.toolchain.cmake" `
  "-DCMAKE_MAKE_PROGRAM=$cmakeBin\ninja.exe" `
  "-DANDROID_ABI=$Abi" -DANDROID_PLATFORM=android-23 -DANDROID_STL=c++_static `
  -DCMAKE_BUILD_TYPE=Release "-DCMAKE_INSTALL_PREFIX=$out" `
  '-DBUILD_LIST=core,imgproc' -DBUILD_SHARED_LIBS=OFF `
  -DBUILD_ANDROID_PROJECTS=OFF -DBUILD_ANDROID_EXAMPLES=OFF -DBUILD_JAVA=OFF `
  -DBUILD_opencv_java=OFF -DBUILD_opencv_apps=OFF -DBUILD_TESTS=OFF `
  -DBUILD_PERF_TESTS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOCS=OFF `
  -DWITH_IPP=OFF -DWITH_ITT=OFF -DWITH_OPENCL=OFF -DWITH_PROTOBUF=OFF `
  -DWITH_TBB=OFF -DWITH_EIGEN=OFF -DWITH_LAPACK=OFF -DCV_TRACE=OFF `
  -DOPENCV_GENERATE_PKGCONFIG=OFF
if ($LASTEXITCODE) { throw 'cmake configure failed' }

& "$cmakeBin\cmake.exe" --build $build --target install -j 8
if ($LASTEXITCODE) { throw 'cmake build failed' }
Write-Host "OpenCV installed in $out"

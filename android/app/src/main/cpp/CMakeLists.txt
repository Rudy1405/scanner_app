cmake_minimum_required(VERSION 3.18)
project(scanner CXX)

# Static OpenCV built by native/build_opencv.ps1 (core + imgproc only).
# Linked by hand: the generated OpenCVConfig.cmake also lists 3rd-party codec
# libraries we don't build.
set(OPENCV_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../native/opencv-android/${ANDROID_ABI}")
set(OPENCV_NATIVE "${OPENCV_ROOT}/sdk/native")
if(NOT EXISTS "${OPENCV_NATIVE}/staticlibs/${ANDROID_ABI}/libopencv_core.a")
  message(FATAL_ERROR "OpenCV for ${ANDROID_ABI} not found. Run native/build_opencv.ps1 -Abi ${ANDROID_ABI}")
endif()

set(OCV_LIBS
  ${OPENCV_NATIVE}/staticlibs/${ANDROID_ABI}/libopencv_imgproc.a
  ${OPENCV_NATIVE}/staticlibs/${ANDROID_ABI}/libopencv_core.a)
foreach(extra tegra_hal cpufeatures)
  set(f "${OPENCV_NATIVE}/3rdparty/libs/${ANDROID_ABI}/lib${extra}.a")
  if(EXISTS "${f}")
    list(APPEND OCV_LIBS "${f}")
  endif()
endforeach()

add_library(scanner SHARED scanner.cpp)
target_include_directories(scanner PRIVATE
  ${OPENCV_NATIVE}/jni/include
  ${OPENCV_NATIVE}/jni/include/opencv4)
target_compile_features(scanner PRIVATE cxx_std_17)
target_compile_options(scanner PRIVATE -O2 -fvisibility=hidden)
target_link_options(scanner PRIVATE -Wl,--gc-sections -Wl,--exclude-libs,ALL
                    -Wl,-z,max-page-size=16384)
target_link_libraries(scanner ${OCV_LIBS} z dl log)

// C API of libscanner.so: finds the corners of a document page with OpenCV.
// Called from Dart through dart:ffi (no platform channel).
#ifndef SCANNER_H
#define SCANNER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SCANNER_EXPORT __attribute__((visibility("default")))

typedef struct Scanner Scanner;

// work_width: size of the long side the detector works at (e.g. 320).
SCANNER_EXPORT Scanner* scanner_create(int work_width);
SCANNER_EXPORT void scanner_destroy(Scanner* s);

// Luminance (Y) plane of a camera frame.
//   rotation: 0/90/180/270, clockwise turns that make the picture upright.
//   out8: x0,y0 .. x3,y3 in 0..1 of the UPRIGHT picture, order TL,TR,BR,BL.
// Returns the confidence 0..1 (0 = no page). Never throws.
SCANNER_EXPORT float scanner_detect_y(Scanner* s, const uint8_t* y, int w, int h,
                                      int stride, int rotation, float* out8);

// Whole picture with 3 (RGB) or 4 (RGBA) channels, already upright.
SCANNER_EXPORT float scanner_detect_image(Scanner* s, const uint8_t* px, int w,
                                          int h, int stride, int channels,
                                          float* out8);

SCANNER_EXPORT const char* scanner_version(void);

#ifdef __cplusplus
}
#endif
#endif

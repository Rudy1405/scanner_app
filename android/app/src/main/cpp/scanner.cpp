#include "scanner.h"

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

#include <algorithm>
#include <cmath>
#include <vector>

struct Scanner {
  int workWidth;
};

namespace {

constexpr float kMinConfidence = 0.40f;

struct Candidate {
  std::vector<cv::Point> quad;  // 4 points, TL,TR,BR,BL
  float score = 0;
};

// Orders 4 points as TL, TR, BR, BL.
std::vector<cv::Point> orderCorners(const std::vector<cv::Point>& p) {
  std::vector<cv::Point> o(4);
  int tl = 0, br = 0, tr = 0, bl = 0;
  for (int i = 1; i < 4; i++) {
    if (p[i].x + p[i].y < p[tl].x + p[tl].y) tl = i;
    if (p[i].x + p[i].y > p[br].x + p[br].y) br = i;
    if (p[i].y - p[i].x < p[tr].y - p[tr].x) tr = i;
    if (p[i].y - p[i].x > p[bl].y - p[bl].x) bl = i;
  }
  o[0] = p[tl];
  o[1] = p[tr];
  o[2] = p[br];
  o[3] = p[bl];
  return o;
}

double angleAt(const cv::Point& a, const cv::Point& b, const cv::Point& c) {
  cv::Point2d u(a.x - b.x, a.y - b.y), v(c.x - b.x, c.y - b.y);
  double nu = std::hypot(u.x, u.y), nv = std::hypot(v.x, v.y);
  if (nu < 1e-6 || nv < 1e-6) return 0;
  double cs = (u.x * v.x + u.y * v.y) / (nu * nv);
  return std::acos(std::max(-1.0, std::min(1.0, cs))) * 180.0 / CV_PI;
}

// Share of points along the quad's sides where the picture really changes
// across the edge (page vs. background). Noise in a dark or flat scene has none.
float edgeSupport(const std::vector<cv::Point>& q, const cv::Mat& img) {
  cv::Point2f c(0, 0);
  for (const auto& p : q) c += cv::Point2f(p);
  c *= 0.25f;
  int valid = 0, good = 0;
  for (int i = 0; i < 4; i++) {
    cv::Point2f a(q[i]), b(q[(i + 1) % 4]);
    cv::Point2f d = b - a;
    float len = std::hypot(d.x, d.y);
    if (len < 1) continue;
    cv::Point2f n(d.y / len, -d.x / len);  // a normal of the side
    if (n.dot((a + b) * 0.5f - c) < 0) n = -n;  // make it point outwards
    for (int k = 1; k < 24; k++) {
      cv::Point2f p = a + d * (k / 24.0f);
      cv::Point2f in = p - n * 3.f, out = p + n * 3.f;
      if (in.x < 0 || in.y < 0 || out.x < 0 || out.y < 0 || in.x >= img.cols - 1 ||
          out.x >= img.cols - 1 || in.y >= img.rows - 1 || out.y >= img.rows - 1)
        continue;
      valid++;
      int vi = img.at<uchar>(cvRound(in.y), cvRound(in.x));
      int vo = img.at<uchar>(cvRound(out.y), cvRound(out.x));
      if (std::abs(vi - vo) >= 14) good++;
    }
  }
  return valid < 20 ? 0.f : float(good) / valid;
}

// Scores a contour as a page: big, convex, rectangle-like, not the whole frame.
bool scoreContour(const std::vector<cv::Point>& contour, const cv::Mat& img,
                  Candidate& out) {
  const cv::Size size = img.size();
  const double frameArea = double(size.width) * size.height;
  double area = cv::contourArea(contour);
  if (area < frameArea * 0.12) return false;

  std::vector<cv::Point> hull;
  cv::convexHull(contour, hull);
  double hullArea = cv::contourArea(hull);
  if (hullArea < frameArea * 0.12) return false;
  double peri = cv::arcLength(hull, true);

  std::vector<cv::Point> poly;
  for (double eps = 0.015; eps <= 0.08; eps += 0.005) {
    cv::approxPolyDP(hull, poly, eps * peri, true);
    if (poly.size() <= 4) break;
  }
  if (poly.size() != 4 || !cv::isContourConvex(poly)) return false;

  std::vector<cv::Point> q = orderCorners(poly);
  double quadArea = cv::contourArea(q);
  if (quadArea < frameArea * 0.12) return false;

  // Corners must be real corners (about 90 degrees, allowing perspective).
  double worst = 0;
  for (int i = 0; i < 4; i++) {
    double a = angleAt(q[(i + 3) % 4], q[i], q[(i + 1) % 4]);
    worst = std::max(worst, std::fabs(a - 90.0));
  }
  if (worst > 38) return false;

  // A quad that is the whole frame means "no page found".
  if (quadArea > frameArea * 0.97) return false;

  // Opposite sides should have similar length (perspective keeps them close).
  auto len = [&](int a, int b) { return std::hypot(double(q[a].x - q[b].x), double(q[a].y - q[b].y)); };
  double s1 = len(0, 1), s2 = len(3, 2), s3 = len(0, 3), s4 = len(1, 2);
  double minSide = std::min(std::min(s1, s2), std::min(s3, s4));
  if (minSide < 0.12 * std::max(size.width, size.height)) return false;
  double pair1 = std::min(s1, s2) / std::max(s1, s2);
  double pair2 = std::min(s3, s4) / std::max(s3, s4);

  double fill = std::min(1.0, area / quadArea);          // contour follows the quad
  double sizeScore = std::min(1.0, quadArea / (frameArea * 0.45));
  double angleScore = 1.0 - worst / 38.0;
  double sideScore = (pair1 + pair2) / 2.0;
  float support = edgeSupport(q, img);
  if (support < 0.5f) return false;
  out.quad = q;
  out.score = float(0.25 * sizeScore + 0.20 * fill + 0.20 * angleScore + 0.15 * sideScore +
                    0.20 * support);
  return true;
}

// mask: where to look for contours; img: the picture, to check the edges.
void bestFromMask(const cv::Mat& mask, const cv::Mat& img, int mode, Candidate& best) {
  std::vector<std::vector<cv::Point>> contours;
  cv::findContours(mask, contours, mode, cv::CHAIN_APPROX_SIMPLE);
  for (const auto& c : contours) {
    Candidate cand;
    if (scoreContour(c, img, cand) && cand.score > best.score) best = cand;
  }
}

// gray: upright 8-bit picture at working size.
float detectPage(const cv::Mat& gray, float* out8) {
  // Percentile contrast stretch so dim pictures get full range.
  int hist[256] = {0};
  for (int r = 0; r < gray.rows; r++) {
    const uchar* row = gray.ptr<uchar>(r);
    for (int c = 0; c < gray.cols; c++) hist[row[c]]++;
  }
  const int total = gray.rows * gray.cols;
  int lo = 0, hi = 255, acc = 0;
  for (int i = 0; i < 256; i++) {
    acc += hist[i];
    if (acc >= total * 0.01) { lo = i; break; }
  }
  acc = 0;
  for (int i = 255; i >= 0; i--) {
    acc += hist[i];
    if (acc >= total * 0.01) { hi = i; break; }
  }
  // A flat or very dark picture has no page: stretching it only amplifies noise.
  if (hi - lo < 25) return 0.f;
  cv::Mat leveled;
  {
    double a = 255.0 / (hi - lo);
    gray.convertTo(leveled, CV_8U, a, -lo * a);
  }

  cv::Mat blur;
  cv::GaussianBlur(leveled, blur, cv::Size(5, 5), 0);

  Candidate best;
  cv::Mat kernel = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(3, 3));

  // Pass A: edges. Thresholds follow the median brightness.
  {
    std::vector<uchar> px(blur.begin<uchar>(), blur.end<uchar>());
    std::nth_element(px.begin(), px.begin() + px.size() / 2, px.end());
    double med = px[px.size() / 2];
    double t1 = std::max(10.0, 0.66 * med), t2 = std::max(30.0, 1.33 * med);
    cv::Mat edges;
    cv::Canny(blur, edges, t1, t2);
    cv::dilate(edges, edges, kernel, cv::Point(-1, -1), 2);
    bestFromMask(edges, blur, cv::RETR_LIST, best);
  }

  // Pass B: bright page on a darker table (Otsu), then dark page on a light one.
  if (best.score < 0.75f) {
    cv::Mat bin;
    cv::threshold(blur, bin, 0, 255, cv::THRESH_BINARY | cv::THRESH_OTSU);
    cv::morphologyEx(bin, bin, cv::MORPH_CLOSE, kernel, cv::Point(-1, -1), 2);
    cv::morphologyEx(bin, bin, cv::MORPH_OPEN, kernel, cv::Point(-1, -1), 2);
    bestFromMask(bin, blur, cv::RETR_EXTERNAL, best);
    if (best.score < 0.75f) {
      cv::Mat inv;
      cv::bitwise_not(bin, inv);
      bestFromMask(inv, blur, cv::RETR_EXTERNAL, best);
    }
  }

  if (best.quad.size() != 4 || best.score < kMinConfidence) return 0.f;
  for (int i = 0; i < 4; i++) {
    out8[i * 2] = std::max(0.f, std::min(1.f, float(best.quad[i].x) / gray.cols));
    out8[i * 2 + 1] = std::max(0.f, std::min(1.f, float(best.quad[i].y) / gray.rows));
  }
  return std::min(1.f, best.score);
}

cv::Size workSize(int w, int h, int workWidth) {
  double scale = double(workWidth) / std::max(w, h);
  if (scale > 1.0) scale = 1.0;
  return cv::Size(std::max(16, int(std::lround(w * scale))), std::max(16, int(std::lround(h * scale))));
}

}  // namespace

extern "C" {

Scanner* scanner_create(int work_width) {
  Scanner* s = new (std::nothrow) Scanner();
  if (s) s->workWidth = std::max(96, std::min(work_width, 1024));
  return s;
}

void scanner_destroy(Scanner* s) { delete s; }

float scanner_detect_y(Scanner* s, const uint8_t* y, int w, int h, int stride,
                       int rotation, float* out8) {
  if (!s || !y || !out8 || w < 16 || h < 16 || stride < w) return 0.f;
  try {
    cv::Mat src(h, w, CV_8UC1, const_cast<uint8_t*>(y), size_t(stride));
    cv::Mat small;
    cv::resize(src, small, workSize(w, h, s->workWidth), 0, 0, cv::INTER_AREA);
    cv::Mat upright;
    switch (rotation) {
      case 90: cv::rotate(small, upright, cv::ROTATE_90_CLOCKWISE); break;
      case 180: cv::rotate(small, upright, cv::ROTATE_180); break;
      case 270: cv::rotate(small, upright, cv::ROTATE_90_COUNTERCLOCKWISE); break;
      default: upright = small; break;
    }
    return detectPage(upright, out8);
  } catch (...) {
    return 0.f;
  }
}

float scanner_detect_image(Scanner* s, const uint8_t* px, int w, int h,
                           int stride, int channels, float* out8) {
  if (!s || !px || !out8 || w < 16 || h < 16 || (channels != 3 && channels != 4) ||
      stride < w * channels)
    return 0.f;
  try {
    cv::Mat src(h, w, channels == 3 ? CV_8UC3 : CV_8UC4, const_cast<uint8_t*>(px), size_t(stride));
    cv::Mat small;
    cv::resize(src, small, workSize(w, h, s->workWidth * 2), 0, 0, cv::INTER_AREA);
    cv::Mat gray;
    cv::cvtColor(small, gray, channels == 3 ? cv::COLOR_RGB2GRAY : cv::COLOR_RGBA2GRAY);
    return detectPage(gray, out8);
  } catch (...) {
    return 0.f;
  }
}

const char* scanner_version(void) { return "scanner 1.0 / opencv " CV_VERSION; }

}  // extern "C"

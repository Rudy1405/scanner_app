# Mechanics sheet

Source of truth for the scanner behaviour, read from the original program's native
scanner library (`libscannercs.so`, arm64, built-in addresses; Ghidra shows them +0x100000).
The app's Java code is packed (only 4 loader classes are readable), so screen flows and
labels are rebuilt from what is visible and marked *estimated*.

## Scanning pipeline (observed)

| Step | Original entry point | Notes |
|---|---|---|
| Decode image | `ScannerEngine.decodeImageS` 0x44b04 | |
| Detect page border | `ScannerEngine.detectBorder` 0x41cd0 -> `DetectBoundLinesColorByModes` 0x80eb4 | Returns 8 ints = 4 corner points (x,y). |
| Fix corners by hand | `ScannerEngine.adjustBound` 0x44730 / `AdjustBound` 0x82acc | User drags the 4 corners. |
| Flatten (perspective) | `ScannerEngine.trimImageS` 0x45e20 | Crop the quad to a rectangle. |
| Enhance (filter) | `ScannerEngine.enhanceImageS` 0x464bc -> `EnhanceColorImageByModes` 0x5eff4 | Mode switch: 0,1,2,3,10,11,14,15,16,17,18,19,20 and 51 (0x33, separate path). |
| Rotate / scale | `rotateAndScaleImageS` 0x4676c | 90° steps. |

## Enhance curves (observed)

**Colour enhance** (`enhance_Color_Image` 0x92cf8 -> 0x93044), applied to every channel:

- v <= 32 -> 0
- 33..235 -> int(253 * ((v - 32) / 203) ^ 0.8333333 + 1.5)
- v >= 236 -> 255

Constants: 253.0 at 0x2aa38, 0.8333333 at 0x2aa48, 203 and 32 inline.

**Black & white** (`enhance_BW_Image` 0x91cc8): grayscale (`colorToGray`), bilinear
down-scale (0x93248), Gaussian weights (`expf`), background estimate, bilinear up-scale,
divide by background, then the tone curve built at 0x92a20-0x92a80:

- v < 159 -> 0
- v > 230 -> 255
- otherwise int(253 * ((v - 158) / 72) ^ 0.5555556 + 1.5)

Constants: 72.0 at 0x2aa58, 0.5555556 at 0x2a8f8, 253.0 at 0x2aa38, 158/159/230 inline.

**Histogram clip** (0x91aa8): histogram of every 2nd pixel in both directions; clip count
= width * height * 0.41 * (1/4096) (0.41 at 0x2a9a0, 1/4096 at 0x2a9a8); the low and high
levels are where the running count from each end passes it. Used here for the grayscale
and lighten auto-levels.

## Magic enhance — "looks really scanned" (observed, libmagicenhancer.so)

Right after a shot the original runs `scanet::enhance` (0x25e00): `deshadow`
(0x1e21c, an MNN network) or `scan` (0x22560), then `enhance_color` (0x21dec,
cvtColor + per-pixel colour boost) and `sharpEnhance` (0x253f4) with base 4.

- **Per-pixel gain/offset** (`enhance_pix` 0x1d0b4): the network outputs two
  low-resolution maps per channel, applied as
  `out = clamp(in · gain · 0.03125 + 2 · offset − 255)` (0.03125 at 0x51c24).
  The network itself is encrypted and isn't reused: our maps come from the photo
  (paper brightness per block = 90th percentile, ink blocks replaced by their
  neighbours' median, smoothed; global paper colour from paper pixels). Gain =
  255 / local paper, then the colour curve below sets the black/white points.
- **Sharpening** (`sharpEnhance` 0x253f4, called with 4 at 0x25eec): box blur of
  size `((4 << (min>400)) << (min>1600)) − 1` (3, 7 or 15); `d = px − blur`;
  `d < −20 → 2d`, `−20 ≤ d < −9 → d`, else `d >> 1`; `out = clamp(px + adj)`.
- Colour boost amount inside `enhance_color` isn't readable: ×1.25 saturation
  (estimated).

## Blurry photos (observed, libpagescanner.so)

`getBlurValue` (0xda910): grey → half size → Laplacian (3×3) → variance.
`extractclearKeyFrame` (0xdbd20) keeps the clearest frame by comparing with
recent ones (factors 0.2 at 0xa35860 and 1.8 at 0xa35868). We use the same
measure on the flattened page at ≤ 800 px and reject below **30** (estimated from
the design's sample photos: sharp 160, sharp in dim light 50, slight shake 18,
blurred sample 0.4). Camera shots below it aren't saved; imports are marked.

## Page edges in dim light (observed approach, our code)

The original combines a page mask (`ContourMaskBitmap`) with candidate straight
lines (`findCandidateLines` 0x871b8, `adjustRect`). Rebuilt as: area-averaged
300 px copy, levelled 1 %/99 % per channel, Gaussian σ 1.2; pass 1 against the
median table colour; pass 2 against a quadratic surface fitted to the table
(relative to its local brightness, so a dark corner doesn't shrink the
difference); opening + closing radius min(w,h)/70; largest region with holes
filled; a total-least-squares line per side (ends of each side ignored),
refined three times; corners = line intersections.

## Round 3 — matched to the original's video (Test_files/og_scanner_app)

Seen in the video: live page = translucent fill + thin border, no handles;
on capture the outline flashes, the flattened page fills the preview, a scan
line sweeps top→bottom (enhanced above, plain photo below, ~0.9 s), then the
page lands as a bottom-right thumbnail with a red counter and "Modificar";
the bar becomes undo (left) · shutter · "Hecho" (right); "Individual | Lote"
pill until the first page.

- **Detection** now follows findCandidateLines + adjustRect: thin edges
  (Sobel on the strongest colour channel, non-max suppression, top 12 %),
  Hough lines (each pixel votes ±6° around its own direction, 26 strongest,
  ±5°/±7 px suppression), every top/bottom/left/right pair (photo borders
  allowed when the page runs off) scored by edge support along each side
  (60 %) and a consistent brightness step across it (40 %); weakest side
  ≥ 0.22, best score ≥ 0.42, else "no page". The colour-region method stays as
  a second candidate. Least-squares refinement at the end. Tested on three
  frames of the original's video (lamp, cluttered desk): within 1.4 % of the
  checked outline, also on the 200 px grey live frame.
- **Live overlay bug fixed**: corners were drawn over the whole screen while
  the preview is cropped to fill it; now mapped with the same crop.
- **Mejorar** now balances white per area (per-channel paper colour per block,
  smoothed), like the original's per-channel gain maps, so a yellow lamp on
  one side and shade on the other both come out white; ink then darkened by a
  1.3 power below 235 (estimated from the video's near-black text).

## Estimated (looked for, not found readable)

- Border detection algorithm: the original uses its own line detector (0x80eb4, partly ML).
  Rebuilt as: page-vs-background colour distance, Otsu threshold, largest region, its 4
  extreme corners. Falls back to a 4 % inset when nothing clear is found.
- Background blur for B&W: down-scale to 64 px long side, Gaussian sigma 2 (estimated;
  the original sizes are computed at run time).
- Gray weights: 0.299 / 0.587 / 0.114 (estimated).
- "Lighten" filter: auto-levels then gamma 0.8 (estimated; the label exists in the
  resources, its mode number is not readable).
- Output size of the flattened page: longest opposite edges of the quad, capped at
  2400 px long side (estimated).
- PDF: A4 by default, also Letter and "fit to image"; JPEG quality 85 (estimated).

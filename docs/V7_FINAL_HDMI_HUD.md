# V7 - HDMI final-stage visible diagnostics

## Critical difference from V5/V6

The always-on HUD is now connected **directly before dvi_encoder** and is applied
**after** gamma correction, not before it. It does not require selecting page 6.
White characters appear on a compact dark strip at top left; a thin **cyan
3-pixel vertical line at the far left of the active image** is a permanent
firmware-identity marker. If the cyan line is not visible, the bitstream is
old or the new HDL path was not successfully built/programmed.

Lines (numerical digits are hexadecimal unless CAM/DDR/SCREEN BCD):

- `V7 RAW R/G/B`, `OUT R/G/B`: 16x16 central grid of image RGB samples,
  before and after the additional post-Debayer correction. They are not
  camera sensor internal AWB/AE registers.
- `N`: count of sampled pixels (expect 100 hex for 256); `V`: 1 when valid.
- `GAIN R/G/B`: UQ2.8 RGB gain (100 hex = 1x); `T`: Sobel threshold;
  `MODE`: video display mode; `KEY`: total button count.
- `CAM/DDR/SCREEN`: detected frame events per 60 display frames (not strictly
  true FPS unless the output is running at exactly 60Hz).
- `ERR:R/L/O`: latched rejected DDR frames / late requests / FIFO overflow;
  `FRZ`: freeze active.

## Programming warning

**The ZIP intentionally omits all stale outflow/*.bit and *.hex files**.
Generate a NEW FPGA image using Efinity; confirm that output timestamp is
later than the RTL edit. Do NOT flash images copied from V4/V5/V6 ZIPs.

## Rebuild and validation

1. Unzip to a fresh folder; open `ti60f225_oob.xml` in Efinity.
2. Run full synthesis, place/route, timing analysis, bitstream generation.
3. Inspect the Efinity messages for missing `edge_final_hud` source or warnings.
4. Program the newly generated bitstream, not a previous outflow file.
5. Confirm left-edge cyan line and `V7` appears without pressing buttons.
6. Point camera at a uniformly illuminated neutral white paper; obtain RAW,
   OUT, GAIN values, and adjust RGB in calibration mode if needed.

## Verified vs not verified

Only source wiring, fixed-value font mapping, Python raster model and package
integrity are checked here. RTL simulator and Efinity are not installed in this
environment. NO FPGA timing closure or board performance is claimed.

We explicitly avoid changing pin configuration, DDR/IP, sensor exposure, and
Sobel processing modules. This is a *visibility* fix, not a latency fix.

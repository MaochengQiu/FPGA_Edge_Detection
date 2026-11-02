# G1R pixel raster regression

Run from `D:/FPGAdemo/V11_G1R/ti60f225_oob` using the workspace Python:

```powershell
& C:/Users/lenovo/AppData/Local/Programs/Python/Python313/python.exe scripts/verify_g1r_cases.py --generate-only
& C:/Users/lenovo/AppData/Local/Programs/Python/Python313/python.exe scripts/verify_g1r_cases.py --suite baseline
& C:/Users/lenovo/AppData/Local/Programs/Python/Python313/python.exe scripts/verify_g1r_cases.py --suite small
& C:/Users/lenovo/AppData/Local/Programs/Python/Python313/python.exe scripts/verify_g1r_cases.py --suite hd
& C:/Users/lenovo/AppData/Local/Programs/Python/Python313/python.exe scripts/verify_g1r_cases.py --suite timeout
& C:/Users/lenovo/AppData/Local/Programs/Python/Python313/python.exe scripts/verify_g1r_cases.py --suite deadline
& C:/Users/lenovo/AppData/Local/Programs/Python/Python313/python.exe scripts/verify_g1r_cases.py --suite reset
& C:/Users/lenovo/AppData/Local/Programs/Python/Python313/python.exe scripts/verify_g1r_cases.py --suite startup
& C:/Users/lenovo/AppData/Local/Programs/Python/Python313/python.exe scripts/verify_g1r_cases.py --suite boundary
& C:/Users/lenovo/AppData/Local/Programs/Python/Python313/python.exe scripts/verify_g1r_cases.py --suite circles
```

`--suite all` runs all nine suites. `--case-start N --case-end N` selects a
zero-based inclusive range in the small or HD manifest. Baseline, timeout, deadline and reset
keep their fixed controls regardless of the range. The runner auto-configures
the existing `D:/FPGAdemo/tools/iverilog/app` direct-stage Icarus environment
unless environment variables already override it. It uses `run_tests.run`
without changing that file; only `img_coords`, the selected geometry and a
namespaced frozen reference are compiled. Five diagnostics are automatically
connected if their names are present in the new geometry source. Support masks
are deliberately unconnected.

`manifest.json` records expected public classifications (NONE=0, CIRCLE=1,
SQUARE=2, RECTANGLE=3), independent target bounds, explanatory notes and SHA256
of every input. Each `.hex` is a sorted unique list of **full-frame pixel
addresses** `y*WIDTH+x`; it is not a DUT cell map. `cases_*.txt` is the compact
SV-readable index. Stimulus is generated once; SV drives all active pixels and
blank clocks, using a single moving sparse-input pointer. No per-clock dumps
are generated. Blank cases intentionally have empty input files.

Small raster: 512x384, S=8, central ROI 256x192, CW=32/CH=24,
HTOTAL=640, then 400000 extra blank clocks per normal frame. HD raster:
1920x1080, S=8, central ROI 960x540, CW=120/CH=68 (partial final row),
HTOTAL=2200/VTOTAL=1125, **no** extra blank clocks. The HD tests therefore
exercise the real post-ROI timing budget. Default S=8 matches the specified
production setting; the bench also exposes S for direct invocation.

Every case checks classification and four target coordinates. Positive bounds
allow at most seven pixels of deviation from the independently calculated
pooled envelope: an entire eight-pixel cell error fails. Isolated noise is
excluded from the expected target envelope. NONE requires all four coordinates
to be zero for new RTL, preventing stale boxes. All 66 public result bits must
hold during active raster, line blank, extended blank and held-high VS. The
next VS rising edge must publish the immediately preceding frame. Diagnostic
values are logged and checked for X, without encoding internal FSM states or
reason numbers in the expected answers.

The first six small cases are stable baseline controls: square, rectangle,
circle, isolated noise, gap1, gap2. All four sides have aligned empty runs of
one/two full cells, retaining the corners. An additional positive has exactly
75% per-side occupancy with two separated two-cell gaps. Negatives include a
completely missing top, blank, triangle, dense fill, missing-quadrant arc,
rotated diamond and an excessive five-cell gap. Other positives check multiple
scales/positions, isolated circle noise, two separated candidates with a clear
largest square, and all eight pixel phases along each axis (16 axis samples;
phase zero is a repeated control). Final blank checks invalidation after motion.

Timeout suite reuses the clean square for three consecutive frames: normal
budget -> truncate immediately after the last ROI pixel -> normal recovery.
The early VS must return NONE and clear the box rather than republish the old
square. This intentionally malformed short frame is separate from normal
budget acceptance. No algorithm completion latency is guessed from internal
signals. A simulation-time watchdog bounds a stuck job.

Deadline suite overrides the DUT processing budget to 128 clocks while leaving
the normal full raster and 400k blank interval intact. It must publish NONE,
zero box and reason 7 at VS. Timeout suite also checks reason 7. Reset suite
publishes a normal square, starts another capture and processing pass, asserts
reset during processing, checks zero result/warm empty diagnostics, then requires
the first full post-reset square to succeed. Published diagnostics join the
frame-only stability monitor. HD includes a 64x40-cell dense component exceeding
the default 2048-cell capacity and an immediately following valid square.

Reference evidence: `reference/G1_failed_revision/img_geometry.sv` pools all ROI
edges into global xmin/xmax/ymin/ymax; state 7 requires every left/right/top/
bottom support position; state 8 rejects `rect_bad`. The runner changes only
the module name in a work-directory copy. The exact SAME sparse pixel inputs
and bbox expectations drive the reference. A successful baseline reproduction
requires the clean square to pass and at least one actual noise/gap mismatch;
it does not count the old algorithm's failure as a successful new-RTL test.

`work/results_<suite>.json`, `work/<suite>_compile.log` and
`work/<suite>_run.log` are actual simulation evidence, including source hashes.
`work/results.json` summarizes the latest invocation. A source mutation during
a run invalidates its status. Baseline can run while the new RTL is absent.
FAIL returns exit 1, including compile errors and missing completion markers.
These are RTL simulations only; they make no board or synthesis claim.
Per-suite compiler intermediates are isolated under `work/<suite>/`.
`--report-only` reconciles all nine saved suite results with current detector,
bench and reference hashes, writing `work/verification_summary.json`. Missing,
failed or stale suites make that final-source report FAIL. `--suite all` also
performs this reconciliation when it completes. A separate baseline source hash
is expected; all eight detector suites must match the final detector hash.

The focused `boundary` suite uses `boundary/` data independently: 64-pixel and
96-pixel diamonds must both return NONE with a zero box; two equal separated
80x80-pixel square contours must also return NONE. Diagnostics show actual
candidate sizes and decisions without weakening the expectations. `diamond`
is a two-case subset for rapid rechecks. Focused invocation summaries are kept
separate from the full regression summary. A boundary failure must remain a
failure; no expected-failure allowance is applied to the new detector.

The `circles` suite uses an independent directory and 80 cases: radii 28, 32,
44, 48, 60 each sweep all eight X and Y pixel phases. Under the revised explicit
minimum-12x12-cell CIRCLE contract, radii 28/32 expect NONE and a zero box;
radii 44/48/60 expect CIRCLE and the analytic target envelope. Rectangles keep
the eight-cell minimum. Both the 64-pixel diamond and the 96-pixel diamond
retain their NONE expectation. The classifier's supported minimum is a product
contract, not an expected-failure exception for small circles.

The final `boundary` suite additionally rejects an aligned 8x8-cell dense patch,
an 8x8-cell dense patch with a central 2x2-cell hole (48/60 band fraction,
12/16 interior occupancy),
and twelve 30-degree missing-circle arcs, rotating the omitted interval in
30-degree increments around a radius-60 circle. The 30..60-degree oblique gap
is explicitly present. `startup` drives a truncated raster and 400k idle cycles
before the first-ever VS after reset, requires no published result and warmup
at that first VS, then requires a normal complete frame to recover.

HD logs `work_cycles`, `ready` and `pending` immediately before each VS via
bench hierarchy wires, without adding any RTL port. All HD cases must have
`ready=1` (including capacity rejection); cycles must be at most 400000.
`verification_summary.json` records each observation and the measured maximum.

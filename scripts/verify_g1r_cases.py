#!/usr/bin/env python3
"""Adversarial pixel-raster RTL tests. No board validation is implied.

  python scripts/verify_g1r_cases.py --generate-only
  python scripts/verify_g1r_cases.py --suite baseline
  python scripts/verify_g1r_cases.py --suite small
  python scripts/verify_g1r_cases.py --suite hd
  python scripts/verify_g1r_cases.py --suite timeout
  python scripts/verify_g1r_cases.py --suite deadline
  python scripts/verify_g1r_cases.py --suite reset
  python scripts/verify_g1r_cases.py --suite all

Uses existing run_tests.run and its official Icarus direct-stage helper. All
generated stimuli, reference copies, executables and evidence stay in
sim/g1r_data. Existing environment overrides are honored. No external packages.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "sim/g1r_data"
WORK = DATA / "work"
TOOLS = Path(r"D:\FPGAdemo\tools\iverilog\app")


def outline(l, t, r, b):
    return ({(x, t) for x in range(l, r+1)} |
            {(x, b) for x in range(l, r+1)} |
            {(l, y) for y in range(t, b+1)} |
            {(r, y) for y in range(t, b+1)})


def line(a, b):
    # Bresenham: continuous one-pixel digital edges, independent of cell rules.
    x, y = a
    bx, by = b
    dx, dy = abs(bx-x), -abs(by-y)
    sx, sy = (1 if x < bx else -1), (1 if y < by else -1)
    err = dx+dy
    points = set()
    while True:
        points.add((x,y))
        if (x,y) == (bx,by):
            return points
        e = 2*err
        if e >= dy:
            err += dy
            x += sx
        if e <= dx:
            err += dx
            y += sy


def polygon(vertices):
    return set().union(*(line(a,b) for a,b in zip(vertices, vertices[1:]+vertices[:1])))


def circle(cx,cy,r):
    # Round a densely sampled analytic circumference, NOT the RTL radial test.
    return {(round(cx+r*math.cos(i*math.tau/(16*r))),
             round(cy+r*math.sin(i*math.tau/(16*r)))) for i in range(16*r)}


def generate(destination=DATA, diamonds_only=False, ambiguous=False, circles_only=False):
    destination.mkdir(parents=True, exist_ok=True)
    manifests = {}
    for w,h in [(512,384),(1920,1080)]:
        if (diamonds_only or circles_only) and w!=512:
            continue
        cases = []
        rx,ry = w//4,h//4

        def add(name, points, shape, target=None, note=""):
            points = set(points)
            assert all(0<=x<w and 0<=y<h for x,y in points)
            if shape:
                target = points if target is None else set(target)
                xs,ys = zip(*target)
                # Public output contract: pooled-cell bounds, within one cell.
                bbox = [rx+(min(xs)-rx)//4*4, ry+(min(ys)-ry)//4*4,
                        rx+((max(xs)-rx)//4+1)*4-1, ry+((max(ys)-ry)//4+1)*4-1]
            else:
                bbox = [0,0,0,0]
            filename = f"{w}_{name}.hex"
            content = "".join(f"{y*w+x:08x}\n" for x,y in sorted(points,key=lambda p:(p[1],p[0])))
            (destination/filename).write_text(content, encoding="ascii")
            cases.append(dict(name=name,file=filename,pixels=len(points),shape=shape,
                              bbox=bbox,tolerance=3 if shape else 0,note=note,
                              sha256=hashlib.sha256((destination/filename).read_bytes()).hexdigest()))

        if circles_only:
            for radius in (28,32,44,48,60):
                for axis in ("x","y"):
                    for phase in range(8):
                        dx,dy=(phase,0) if axis=="x" else (0,phase)
                        add(f"circle_r{radius}_{axis}{phase}",circle(256+dx,192+dy,radius),0 if radius<44 else 1,
                            note="Five sizes, all eight phases per axis; conservative CIRCLE minimum 12x12 cells excludes radii 28/32")
        elif diamonds_only:
            for size in (64,96):
                radius=size//2
                add(f"diamond_{size}",polygon([(256,192-radius),(256+radius-1,192),
                                               (256,192+radius-1),(256-radius,192)]),0,
                    note="Small rotated square must not be mistaken for axis-aligned square or circle")
            if ambiguous:
                add("ambiguous_equal",outline(144,144,223,223)|outline(272,144,351,223),0,
                    note="Two equal 36-cell contours, separated by six empty cell columns; no unique largest target")
                add("dense_8x8_cells",{(x,y) for y in range(160,224) for x in range(224,288)},0,
                    note="Aligned 64x64-pixel solid patch; exactly 8x8 pooled cells, not a square contour")
                add("dense_8x8_small_hole",{(x,y) for y in range(160,224) for x in range(224,288)
                                         if not(248<=x<264 and 184<=y<200)},0,
                    note="8x8 dense cells minus central 2x2 cells: 48/60 in outer bands, but 12/16 interior cells occupied")
                complete = circle(256,192,60)
                for start in range(0,360,30):
                    arc={p for p in complete if ((math.degrees(math.atan2(p[1]-192,p[0]-256))-start)%360)>=30}
                    add(f"arc30_{start:03d}",arc,0,
                        note=f"Analytic 30-degree interval [{start},{start+30}) removed; includes oblique 30..60 gap")
        elif w == 512:
            sq = outline(176,128,303,255)
            rect = outline(160,136,343,247)
            circ = circle(256,192,60)
            # Keep first six stable: baseline requires clean square plus a
            # demonstrated noise/gap failure under identical pixel stimulus.
            add("square",sq,2)
            add("rectangle",rect,3)
            add("circle",circ,1)
            noise = {(140,108),(368,108),(140,276),(368,276)}
            add("isolated_noise",sq|noise,2,target=sq,
                note="Four isolated ROI cells outside target; bbox must stay on square")
            for gap in (1,2):
                g = {p for p in sq if not
                     ((p[1] in (128,255) and 232<=p[0]<232+gap*8) or
                      (p[0] in (176,303) and 184<=p[1]<184+gap*8))}
                add(f"gap{gap}",g,2,target=sq,
                    note=f"One {gap}-cell empty run at each side; corners retained")
            # Later additions go AFTER the six baseline control cases.
            add("missing_top",{p for p in sq if p[1]!=128},0)
            add("blank",set(),0)
            add("triangle",polygon([(256,120),(176,255),(336,255)]),0)
            add("dense",{(x,y) for y in range(128,256) for x in range(176,304)},0)
            add("arc",{p for p in circ if not(p[0]>256 and p[1]<192)},0)
            add("diamond",polygon([(256,120),(328,192),(256,264),(184,192)]),0)
            add("circle_noise",circ|noise,1,target=circ)
            add("small_square",outline(152,112,231,191),2)
            add("shifted_rectangle",outline(184,168,359,263),3)
            add("small_circle",circle(208,168,44),1)
            large = outline(240,128,351,239)
            add("largest_separated",large|outline(144,160,207,223),2,target=large,
                note="Two complete separated contours; largest has 52 vs 28 pooled cells")
            add("long_gap",{p for p in sq if not(p[1]==128 and 216<=p[0]<256)},0,
                note="Five empty cells on top: support below 75 percent and excessive gap")
            quarter = {p for p in sq if not
                       ((p[1] in (128,255) and (208<=p[0]<224 or 256<=p[0]<272)) or
                        (p[0] in (176,303) and (160<=p[1]<176 or 208<=p[1]<224)))}
            add("distributed_25pct_gaps",quarter,2,target=sq,
                note="Exactly 12/16 occupied positions per side, two separated two-cell gaps")
            for axis in ("x","y"):
                for phase in range(8):
                    dx,dy = (phase,0) if axis=="x" else (0,phase)
                    shifted = {(x+dx,y+dy) for x,y in sq}
                    add(f"phase_{axis}{phase}",shifted,2,
                        note="Axis phase sweep; x0/y0 duplicate is intentional control")
            # Finish with NONE after many positives, to expose stale output.
            add("blank_after_motion",set(),0)
        else:
            sq = outline(720,400,1039,719)
            add("square",sq,2)
            noise = {(504,288),(1400,288),(504,784),(1400,784)}
            add("isolated_noise",sq|noise,2,target=sq)
            add("rectangle",outline(672,432,1199,655),3)
            add("circle",circle(960,540,160),1)
            gap = {p for p in sq if not
                   ((p[1] in (400,719) and 872<=p[0]<888) or
                    (p[0] in (720,1039) and 552<=p[1]<568))}
            add("gap2",gap,2,target=sq)
            add("missing_top",{p for p in sq if p[1]!=400},0)
            add("arc",{p for p in circle(960,540,160) if not(p[0]>960 and p[1]<540)},0)
            add("blank",set(),0)
            # 64x40 occupied cells exceeds QUEUE_CAP=2048. It is a negative,
            # followed by a normal square to check fail-closed recovery.
            add("capacity_dense",{(x,y) for y in range(398,718) for x in range(672,1184)},0)
            add("after_capacity_square",sq,2)
        rows = [f"{c['name']} {c['file']} {c['pixels']} {c['shape']} "
                + " ".join(map(str,c['bbox']))+f" {c['tolerance']}\n" for c in cases]
        (destination/f"cases_{w}.txt").write_text("".join(rows),encoding="ascii")
        manifests[str(w)] = dict(width=w,height=h,S=8,CW=math.ceil((w//2)/8),
                                  CH=math.ceil((h//2)/8),cases=cases)
    (destination/"manifest.json").write_text(json.dumps(manifests,indent=2)+"\n",encoding="utf-8")
    return manifests


def configure():
    if TOOLS.exists():
        os.environ.setdefault("RTL_SIM","icarus_direct")
        os.environ.setdefault("IVERILOG",str(TOOLS/"bin/iverilog.exe"))
        os.environ.setdefault("VVP",str(TOOLS/"bin/vvp.exe"))
        os.environ.setdefault("IVL_BASE",str(TOOLS/"lib/ivl"))
    import run_tests as sim
    WORK.mkdir(parents=True,exist_ok=True)
    sim.BUILD = WORK
    # Avoid compiling unrelated RTL being changed by other workers.
    sim.RTL = [ROOT/"rtl/edge/video/img_coords.sv"]
    reference = ROOT/"reference/G1_failed_revision/img_geometry.sv"
    text = reference.read_text(encoding="utf-8")
    renamed,n = re.subn(r"\bmodule\s+img_geometry\b","module g1r_reference_geometry",text)
    if n != 1:
        raise RuntimeError("Expected exactly one frozen reference geometry module")
    copy = WORK/"g1r_reference_geometry.sv"
    copy.write_text(renamed,encoding="utf-8")
    sim.TB_RTL["tb_g1r_raster"] = [str(copy)]
    return sim,reference


def final_report():
    """Reconcile saved evidence against the CURRENT source, never promote old PASS."""
    expected = {"baseline","small","hd","timeout","deadline","reset","startup","boundary","circles"}
    rows = json.loads((WORK/"results.json").read_text(encoding="utf-8"))
    source_hash = hashlib.sha256((ROOT/"rtl/edge/geometry/img_geometry.sv").read_bytes()).hexdigest()
    bench_hash = hashlib.sha256((ROOT/"sim/tb_g1r_raster.sv").read_bytes()).hexdigest()
    reference_hash = hashlib.sha256((ROOT/"reference/G1_failed_revision/img_geometry.sv").read_bytes()).hexdigest()
    stale = [r["suite"] for r in rows if r["source_sha256"] !=
             (reference_hash if r["suite"]=="baseline" else source_hash) or r.get("bench_sha256")!=bench_hash]
    missing = sorted(expected-{r["suite"] for r in rows})
    failed = [r["suite"] for r in rows if r["status"]!="PASS"]
    summary = dict(status="FAIL" if stale or missing or failed else "PASS",
                   final_source_sha256=source_hash,bench_sha256=bench_hash,
                   stale_suites=stale,missing_suites=missing,failed_suites=failed,
                   board_tested=False,tests=rows)
    hd_log=WORK/"hd_run.log"
    if hd_log.exists():
        budgets=[int(x) for x in re.findall(r"G1R BUDGET case=\S+ cycles=(\d+) ready=1",hd_log.read_text())]
        summary["hd_precommit_cycles"]=budgets
        summary["hd_max_processing_cycles"]=max(budgets,default=None)
    output = WORK/"verification_summary.json"
    output.write_text(json.dumps(summary,indent=2)+"\n",encoding="utf-8")
    print(f"Final-source report {summary['status']}: {output}; hash={source_hash}")
    return 0 if summary["status"]=="PASS" else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--generate-only",action="store_true")
    ap.add_argument("--report-only",action="store_true",help="Reconcile last all-suite results with current RTL/bench hashes")
    ap.add_argument("--suite",choices=["all","baseline","small","hd","timeout","deadline","reset","startup","diamond","boundary","circles"],default="all")
    ap.add_argument("--case-start",type=int,default=0)
    ap.add_argument("--case-end",type=int,default=10000)
    args = ap.parse_args()
    if args.report_only:
        return final_report()
    focused = args.suite in ("diamond","boundary","circles")
    stimulus_dir = DATA/args.suite if focused else DATA
    manifest = generate(stimulus_dir,focused,args.suite=="boundary",args.suite=="circles")
    print(f"Generated {sum(len(v['cases']) for v in manifest.values())} cases in {stimulus_dir}",flush=True)
    if args.generate_only:
        return 0
    sim,reference = configure()
    source = ROOT/"rtl/edge/geometry/img_geometry.sv"
    suites = ["baseline","small","hd","timeout","deadline","reset","startup","boundary","circles"] if args.suite=="all" else [args.suite]
    results = []
    for suite in suites:
        if suite in ("boundary","circles") and args.suite=="all":
            stimulus_dir = DATA/suite
            generate(stimulus_dir,True,suite=="boundary",suite=="circles")
        tested_source = reference if suite=="baseline" else source
        if not tested_source.is_file():
            print(f"RTL not ready: {tested_source}",file=sys.stderr)
            return 1
        source_text = tested_source.read_text(encoding="utf-8")
        diagnostics = suite!="baseline" and all(re.search(r"\b"+p+r"\b",source_text) for p in
                          ["debug_reason","debug_cells","debug_count","debug_sides","debug_radial"])
        sim.RTL = [ROOT/"rtl/edge/video/img_coords.sv"]
        if suite!="baseline":
            sim.RTL.append(source)
        params = dict(DATA_DIR='"'+stimulus_dir.as_posix()+'"', HAS_DIAGNOSTICS=int(diagnostics),
                      CASE_START=args.case_start,CASE_END=args.case_end)
        if suite=="baseline":
            params.update(REFERENCE=1,HAS_DIAGNOSTICS=0,CASE_START=0,CASE_END=5)
        if suite=="hd":
            params.update(WIDTH=1920,HEIGHT=1080)
        if suite=="timeout":
            params.update(TIMEOUT_TEST=1,CASE_START=0,CASE_END=0)
        if suite=="deadline":
            params.update(BUDGET_TEST=1,CASE_START=0,CASE_END=0)
        if suite=="reset":
            params.update(RESET_TEST=1,CASE_START=0,CASE_END=0)
        if suite=="startup":
            params.update(STARTUP_TEST=1,CASE_START=0,CASE_END=0)
        before = hashlib.sha256(tested_source.read_bytes()).hexdigest()
        row = dict(suite=suite,params=params,status="FAIL",source_sha256=before,
                   source=str(tested_source),
                   reference_sha256=hashlib.sha256(reference.read_bytes()).hexdigest(),
                   manifest_sha256=hashlib.sha256((stimulus_dir/"manifest.json").read_bytes()).hexdigest(),
                   bench_sha256=hashlib.sha256((ROOT/"sim/tb_g1r_raster.sv").read_bytes()).hexdigest(),
                   backend=sim.BACKEND, board_tested=False)
        suite_work = WORK/suite
        suite_work.mkdir(parents=True,exist_ok=True)
        sim.BUILD = suite_work
        for stage in ["compile","run"]:
            path = suite_work/f"tb_g1r_raster_{stage}.log"
            if path.exists():
                path.unlink()
        print(f"Running {suite} (diagnostics={params['HAS_DIAGNOSTICS']})",flush=True)
        try:
            sim.run("tb_g1r_raster",params)
            log = (suite_work/"tb_g1r_raster_run.log").read_text()
            if suite=="baseline":
                if not re.search(r"G1R CASE PASS case=square\s",log):
                    raise RuntimeError("Reference clean-square control did not pass")
                failures = re.findall(r"G1R MISMATCH case=(isolated_noise|gap1|gap2)\s",log)
                if not failures or "G1R REFERENCE DONE" not in log:
                    raise RuntimeError("No actual reference noise/gap regression reproduced")
                row["reproduced_failures"] = failures
            elif "G1R RASTER PASS" not in log:
                raise RuntimeError("Simulation did not reach successful completion marker")
            if hashlib.sha256(tested_source.read_bytes()).hexdigest()!=before:
                raise RuntimeError("RTL changed during run; rerun against a stable source")
            row["status"] = "PASS"
        except Exception as exc:
            row["error"] = str(exc)
            print(str(exc),file=sys.stderr,flush=True)
        for stage in ["compile","run"]:
            path = suite_work/f"tb_g1r_raster_{stage}.log"
            if path.exists():
                (WORK/f"{suite}_{stage}.log").write_bytes(path.read_bytes())
        results.append(row)
        (WORK/f"results_{suite}.json").write_text(json.dumps(row,indent=2)+"\n",encoding="utf-8")
        summary_name = f"results_{args.suite}_invocation.json" if focused else "results.json"
        (WORK/summary_name).write_text(json.dumps(results,indent=2)+"\n",encoding="utf-8")
    ok = all(r["status"]=="PASS" for r in results)
    evidence = WORK/(f"results_{args.suite}_invocation.json" if focused else "results.json")
    print(f"G1R {'PASS' if ok else 'FAIL'}; evidence: {evidence}")
    if args.suite=="all":
        return final_report()
    return 0 if ok else 1


if __name__=="__main__":
    raise SystemExit(main())

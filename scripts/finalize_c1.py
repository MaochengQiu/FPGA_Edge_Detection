#!/usr/bin/env python3
"""Validate actual C1 regression/STA and collect programming artifacts.
Leaves the original V10 programming files and release manifest untouched.
"""
from pathlib import Path
from datetime import datetime,timezone,timedelta
import hashlib,json,re,shutil,xml.etree.ElementTree as ET
from check_c1_scope import check

ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'outflow'
scope=check()
tests=json.loads((ROOT/'reports/verification.json').read_text())
assert len(tests)==29 and all(t['status']=='PASS' for t in tests),'C1 full regression incomplete'
assert 'ALL REGRESSIONS PASSED' in (ROOT/'reports/rtl_regression_v10_c1.log').read_text(encoding='utf-8-sig')
for top,label in [('tb_debayer_color','DEBAYER COLOR PASS'),('tb_color_precision','COLOR PRECISION PASS'),
                  ('tb_color_pipeline','COLOR PIPELINE PASS'),('tb_final_hud','V10-C1 HUD PASS')]:
    assert label in (ROOT/f'sim/build/{top}_run.log').read_text()
assert '267 fields' in (ROOT/'reports/c1_debayer_spatial.log').read_text(encoding='utf-8-sig')
timing=(OUT/'ti60f225_oob.timing.rpt').read_text()
def rows(s):return [dict(launch=m[0],capture=m[1],constraint_ns=float(m[2]),slack_ns=float(m[3]))
                    for m in re.findall(r'^\s*(\S+)\s+(\S+)\s+([\d.-]+)\s+([\d.-]+)\s+\(R-R\)',s,re.M)]
setup=rows(timing.split('Setup (Max) Clock Relationship',1)[1].split('Hold (Min)',1)[0])
hold=rows(timing.split('Hold (Min) Clock Relationship',1)[1].split('NOTE:',1)[0])
assert setup and hold and min(p['slack_ns'] for p in setup+hold)>=0,'Negative final timing'
assert any(p['launch']=='vid_clk_dvi2' and p['capture']=='hdmi_tx_slow_clk' for p in setup),'Related video path cut'
assert 'No Synchronizer warnings to report.' in (OUT/'ti60f225_oob.cdc.rpt').read_text()
place_log=(OUT/'ti60f225_oob.place.out').read_text(errors='replace')
assert not re.search(r'No pins matched[^\n]*(video_health|edge_read_error_sync)',place_log),'CDC match failure'
files=[ROOT/e.attrib['name'] for e in ET.parse(ROOT/'ti60f225_oob.xml').getroot().iter()
       if e.tag.rsplit('}',1)[-1]=='design_file']
files += [ROOT/p for p in ('ti60f225_oob.xml','ti60f225_oob.peri.xml','ti60f225_oob.sdc','rtl/gamma_conrrection/2P2.mem')]
sources=tuple(files)
for ext in ('bit','hex'):
    src=OUT/f'ti60f225_oob.{ext}';assert src.stat().st_size>100000
    assert all(f.stat().st_mtime<=src.stat().st_mtime+(2 if f.name=='ti60f225_oob.xml' else 0) for f in sources),'Stale build'
    dest=ROOT/f'programming/ti60f225_oob_V10_C1.{ext}';shutil.copy2(src,dest);files.append(dest)
for suffix,name in [('timing.rpt','timing.rpt'),('cdc.rpt','cdc.rpt'),('place.rpt','resources.rpt'),
                    ('map.out','synthesis.log'),('place.out','place_route.log'),('pgm.out','bitstream.log')]:
    shutil.copy2(OUT/f'ti60f225_oob.{suffix}',ROOT/f'reports/c1_{name}')
shutil.copy2(ROOT/'reports/verification.json',ROOT/'reports/verification_c1.json')
report=dict(revision='V10-C1',collected_at=datetime.now(timezone(timedelta(hours=8))).isoformat(),
            tool='Efinity 2026.1.132 / Ti60F225 / I3 / seed 1',scope=scope,
            regression_results=tests,setup=setup,hold=hold,
            additional_debayer_spatial_check='PASS: 267 fields / 16020 interior 2-pixel words',
            min_setup_slack_ns=min(p['slack_ns'] for p in setup),min_hold_slack_ns=min(p['slack_ns'] for p in hold),
            rgb_correction_latency_cycles=1,raw_gain='Q8 0x0100 unity, VIO disabled at color input',
            wb_preset='Retained V10 preset; must recalibrate after Debayer fix',wb_step_q8=8,
            board_validation='NOT RUN; await user before edge-algorithm phase',
            sha256={f.relative_to(ROOT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in files})
(ROOT/'reports/v10_c1_release_manifest.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
print(f"V10-C1 FINAL PASS: {len(tests)} groups; min setup {report['min_setup_slack_ns']:.3f} ns; min hold {report['min_hold_slack_ns']:.3f} ns")
for ext in ('bit','hex'):
    f=ROOT/f'programming/ti60f225_oob_V10_C1.{ext}';print(f.name,hashlib.sha256(f.read_bytes()).hexdigest())

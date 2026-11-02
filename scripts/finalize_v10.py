#!/usr/bin/env python3
"""Check actual regression/STA outputs, then collect traceable V10 artifacts.
This does not run tests, compile, program hardware, or claim board acceptance.
"""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import hashlib, json, re, shutil, xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'outflow'
tests=json.loads((ROOT/'reports/verification.json').read_text())
assert tests and all(t['status']=='PASS' for t in tests), 'Regression failed'
assert 'ALL REGRESSIONS PASSED' in (ROOT/'reports/rtl_regression_v10.log').read_text(encoding='utf-8-sig')
assert 'V10 HUD PASS' in (ROOT/'sim/build/tb_final_hud_run.log').read_text()
assert 'THRESHOLD LIMITS PASS' in (ROOT/'sim/build/tb_threshold_limits_run.log').read_text()
assert 'WEAK EDGES PASS' in (ROOT/'sim/build/tb_weak_edges_run.log').read_text()
timing=(OUT/'ti60f225_oob.timing.rpt').read_text()
setup_text=timing.split('Setup (Max) Clock Relationship',1)[1].split('Hold (Min) Clock Relationship',1)[0]
hold_text=timing.split('Hold (Min) Clock Relationship',1)[1].split('NOTE:',1)[0]
def relationships(text):
    return [dict(launch=m[0],capture=m[1],constraint_ns=float(m[2]),slack_ns=float(m[3]))
            for m in re.findall(r'^\s*(\S+)\s+(\S+)\s+([\d.-]+)\s+([\d.-]+)\s+\(R-R\)',text,re.M)]
setup,hold=relationships(setup_text),relationships(hold_text)
assert setup and hold and min(p['slack_ns'] for p in setup+hold)>=0, 'Negative timing slack'
assert any(p['launch']=='vid_clk_dvi2' and p['capture']=='hdmi_tx_slow_clk' for p in setup), 'Related video path cut'
place_log=(OUT/'ti60f225_oob.place.out').read_text(errors='replace')
assert not re.search(r'No pins matched[^\n]*(video_health|edge_read_error_sync)',place_log), 'CDC exception failed to match'
assert 'No Synchronizer warnings to report.' in (OUT/'ti60f225_oob.cdc.rpt').read_text()
files=[]
manifest=ET.parse(ROOT/'ti60f225_oob.xml').getroot()
for e in manifest.iter():
    if e.tag.rsplit('}',1)[-1]=='design_file':files.append(ROOT/e.attrib['name'])
files += [ROOT/n for n in ('ti60f225_oob.xml','ti60f225_oob.peri.xml','ti60f225_oob.sdc','rtl/gamma_conrrection/2P2.mem')]
programming=ROOT/'programming';programming.mkdir(exist_ok=True)
source_files=tuple(files)
for ext in ('bit','hex'):
    src=OUT/f'ti60f225_oob.{ext}'
    assert src.stat().st_size>100000, f'Missing {ext}'
    # efx_run reserializes project XML on successful exit, just after PGM.
    # RTL, memory images, peripheral XML and SDC still get a strict check.
    assert all(f.stat().st_mtime<=src.stat().st_mtime+(2 if f.name=='ti60f225_oob.xml' else 0)
               for f in source_files), 'Sources newer than bitstream'
    dest=programming/f'ti60f225_oob_V10.{ext}'
    shutil.copy2(src,dest);files.append(dest)
for source,name in (('timing','timing'),('cdc','cdc'),('place','resources')):
    shutil.copy2(OUT/f'ti60f225_oob.{source}.rpt',ROOT/f'reports/v10_{name}.rpt')
for source,name in (('map','synthesis'),('place','place_route'),('pgm','bitstream')):
    shutil.copy2(OUT/f'ti60f225_oob.{source}.out',ROOT/f'reports/v10_{name}.log')
report=dict(revision='V10',collected_at=datetime.now(timezone(timedelta(hours=8))).isoformat(),
            tool='Efinity 2026.1.132 / Ti60F225 / I3 / seed 1',
            regression_results=tests,threshold_limits=dict(minimum=4,maximum=128,default=24,step=1),
            decimal_hud_and_limit_label='PASS',weak_dark_step_reference='T40:0 edges; T24:12 edges; flat:0',setup=setup,hold=hold,
            min_setup_slack_ns=min(p['slack_ns'] for p in setup),
            min_hold_slack_ns=min(p['slack_ns'] for p in hold),
            cdc_report='No Synchronizer warnings to report.',
            place_warning_count=place_log.count('WARNING'),board_validation='NOT RUN',
            camera_60fps_validation='NOT RUN; sensor timing settings retained',
            sha256={f.relative_to(ROOT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in files})
(ROOT/'reports/v10_release_manifest.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
print(f"V10 FINAL CHECK PASS: {len(tests)} regression groups; setup min {report['min_setup_slack_ns']:.3f} ns; hold min {report['min_hold_slack_ns']:.3f} ns")
for f in programming.iterdir():print(f.name,hashlib.sha256(f.read_bytes()).hexdigest())

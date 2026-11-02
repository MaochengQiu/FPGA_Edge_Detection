#!/usr/bin/env python3
"""Check V3 exposure arithmetic, source registration and a synthetic motion reference.
No proprietary sensor/FPGA timing claims; not a substitute for HDL simulation/STA.
Pure standard library, reproducible.
"""
from pathlib import Path
import re,json,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
rom=(ROOT/'rtl/cam_i2c_ctrl/i2c/i2c_master_reg_rom.v').read_text()
ctl=(ROOT/'rtl/edge/control/img_control.sv').read_text()
health=(ROOT/'rtl/edge/compose/edge_video_health.sv').read_text()
project=ET.parse(ROOT/'ti60f225_oob.xml').getroot()
source_files=[n.attrib['name'] for n in project.iter() if n.tag.endswith('design_file')]
assert len(source_files)==73
assert 'rtl/edge/compose/edge_video_health.sv' in source_files
assert len(set(source_files))==len(source_files)
for name in source_files: assert (ROOT/name).is_file(),name
assert "pending_t<=11'd40;active_t<=11'd40;" in ctl
assert 'MEASURE_FRAMES=60' in health
# Only decode the unguarded V3 branch after `else, not the compatibility macro branch.
v3=rom.split('`ifdef EDGE_ORIGINAL_LONG_EXPOSURE',1)[1].split('`else',1)[1].split('`endif',1)[0]
old=rom.split('`ifdef EDGE_ORIGINAL_LONG_EXPOSURE',1)[1].split('`else',1)[0]
def shutter(block):
    vals=[]
    for addr in ('3e00','3e01','3e02'):
        pattern=rf"16'h{addr},8'h([0-9a-f]{{2}}),1'b0"
        match=re.search(pattern,block,re.I)
        assert match,addr
        vals.append(int(match.group(1),16))
    return ((vals[0]&15)<<12)|(vals[1]<<4)|(vals[2]>>4)
old_shutter=shutter(old)
new_shutter=shutter(v3)
def_vts=0x05dc
assert old_shutter==0x1bbf and new_shutter==0x0500
assert new_shutter>=4 and new_shutter<=2*def_vts-11
# In this ROM the original preset is above the sensor datasheet's default VTS limit.
assert old_shutter>2*def_vts-11
# No claim that the physical sensor used the default VTS: read back VTS when possible.
# Synthetic 1D moving stripe integrated across N locations: old (long) smears wider.
def blur_pulse(k):
    length=96;base=[255 if 48<=x<=50 else 0 for x in range(length)]
    out=[]
    for x in range(length):
        samp=[base[j] for j in range(x-(k//2),x+(k//2)+1) if 0<=j<length]
        out.append(sum(samp)//len(samp))
    return out
def sobel_1d(line):return [abs(line[x-1]-line[x+1])*4 for x in range(1,len(line)-1)]
old_arr=blur_pulse(13)
new_arr=blur_pulse(3)
old_edge=[i+1 for i,g in enumerate(sobel_1d(old_arr)) if g>=40]
new_edge=[i+1 for i,g in enumerate(sobel_1d(new_arr)) if g>=40]
assert old_edge and new_edge
old_extent=max(old_edge)-min(old_edge)
new_extent=max(new_edge)-min(new_edge)
assert new_extent<old_extent,(old_extent,new_extent)
report={
 'preset':'V3 short exposure + default bypass Sobel',
 'exposure_half_lines_old':old_shutter,
 'exposure_half_lines_new':new_shutter,
 'exposure_ratio_old_over_new':round(old_shutter/new_shutter,3),
 'nominal_vts_from_datasheet':def_vts,
 'new_exposure_within_nominal_vts_limit':True,
 'old_exposure_outside_nominal_vts_limit':True,
 'synthetic_motion_edge_extent_px':{'13tap_blur':old_extent,'3tap_blur':new_extent},
 'source_registration':'PASS',
 'electrical_clocks_and_ddr_hardware':'NOT MEASURED',
 'effective_sensor_fps':'UNKNOWN UNTIL ON-BOARD',
 'rtl_simulation':'NOT RUN UNLESS scripts/run_tests.py EXECUTED',
 'efinity_synthesis_sta':'NOT RUN',
}
(ROOT/'reports/motion_v3_reference.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
print(json.dumps(report,indent=2,ensure_ascii=False))

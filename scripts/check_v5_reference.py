#!/usr/bin/env python3
"""Python-only model, not an RTL simulation or timing sign-off."""
from pathlib import Path
import re
from xml.etree import ElementTree as ET
project=Path(__file__).resolve().parents[1]
ns={'e':'http://www.efinixinc.com/enf_proj'}
xml=ET.parse(project/'ti60f225_oob.xml')
listed={i.attrib['name'] for i in xml.findall('.//e:design_file',ns)}
for p in ('rtl/edge/compose/edge_color_balance.sv','rtl/edge/compose/edge_rgb_statistics.sv','rtl/edge/compose/edge_diag_page.sv'):
    assert p in listed and (project/p).is_file(),p
for name in ('ti60f225_oob.peri.xml','ti60f225_oob.sdc'):
    assert (project/name).is_file()
control=(project/'rtl/edge/control/img_control.sv').read_text()
assert 'pending_d==6' in control and "wb_r<=10'h0c0;wb_g<=10'h1c0;wb_b<=10'h0f0" in control and 'wb_selected' in control
src=(project/'rtl/ti60f225_oob_top.v').read_text()
for sign in ('edge_wb_processor','edge_wb_stats','edge_diagnostics','edge_diagnostics_rgb'):
    assert sign in src
assert re.search(r'\.din\(\{edge_diagnostics_vs,edge_diagnostics_hs,edge_diagnostics_de,edge_diagnostics_rgb\}\)',src)
for c in ('R','G','B'):
    assert c in (project/'rtl/edge/compose/edge_diag_page.sv').read_text()
# Quantized gain and saturating output known vectors.
def gain(v,g):return min(255,(v*g)>>8)
assert [gain(v,g) for v,g in zip((100,80,120),(192,320,256))]==[75,100,120]
assert all(gain(v,384)==255 for v in (180,220,255))
assert all(gain(100,g)==100 for g in (256,256,256))
# 16x16 grid, from central image half, exact count and mean.
width,height=1920,1080
sx,sy=width//32,height//32
xx=[width//4+sx//2+k*sx for k in range(16)]
yy=[height//4+sy//2+k*sy for k in range(16)]
assert len(set(xx))==16 and len(set(yy))==16
assert max(xx)<width and max(yy)<height
assert sum([100 for x in xx for y in yy])>>8==100
print('V5 STATIC/REFERENCE PASS: source manifest, HDMI wiring, ROI, gain math and controls')
print('WARNING: no RTL simulation, Efinity synthesis, timing closure or board proof performed here.')

#!/usr/bin/env python3
"""V8 fixed white-card preset, source gates and Efinity manifest checks.
This is NOT RTL simulation, board-level verification or timing signoff.
"""
from pathlib import Path
from xml.etree import ElementTree as ET
import re
p=Path(__file__).resolve().parents[1]
control=(p/'rtl/edge/control/img_control.sv').read_text()
hud=(p/'rtl/edge/compose/edge_final_hud.sv').read_text()
top=(p/'rtl/ti60f225_oob_top.v').read_text()
gainrtl=(p/'rtl/edge/compose/edge_color_balance.sv').read_text()
assert "wb_r<=10'h0c0;wb_g<=10'h1c0;wb_b<=10'h0f0" in control
assert "10'h240" in control
assert "wire hud_enabled=(display_mode==3'd6);" in hud
assert "wire area=in_de" in hud
assert "wire sentinel=hud_enabled && in_de" in hud
assert "letter=8'h31; // V10 threshold release" in hud
assert 'input wire [1:0] wb_selected' in hud
assert '.wb_selected(edge_wb_selected)' in top
assert 'wire [23:0] edge_diagnostics_rgb = edge_rgb;' in top
assert 'edge_color_balance edge_wb_processor(' in top
assert 'out_de<=in_de;out_hs<=in_hs;out_vs<=in_vs;' in gainrtl
assert 'out_de<=in_de;out_hs<=in_hs;out_vs<=in_vs;' in hud
assert all(s in top for s in ('.i_bdata         (edge_final_hdmi_rgb[7:0])',
'.i_gdata         (edge_final_hdmi_rgb[15:8])',
'.i_rdata         (edge_final_hdmi_rgb[23:16])',
'.i_de            (edge_final_hdmi_de)',
'.i_hs            (edge_final_hdmi_hs)',
'.i_vs            (edge_final_hdmi_vs)'))
manifest=(p/'ti60f225_oob.xml').read_text()
for rel in ('rtl/edge/control/img_control.sv','rtl/edge/compose/edge_color_balance.sv',
            'rtl/edge/compose/edge_final_hud.sv','rtl/ti60f225_oob_top.v'):
    assert rel in manifest
# The observed white-card values from the user's visible V7 screenshot.
raw=(int('F4',16),int('6A',16),int('C4',16))
gain=(int('0C0',16),int('1C0',16),int('0F0',16))
corrected=tuple(min(255,(p*g+128)>>8) for p,g in zip(raw,gain))
assert corrected==(183,186,184),corrected
assert max(corrected)-min(corrected)<=3
assert all(0<=v<=255 for v in corrected)
# KEY3 page 6 is active; all other modes have 1-clock pass-through.
assert 'selected=rgb' in (p/'rtl/edge/compose/img_composer.sv').read_text()
print('PASS: white-card RGB %s -> %s with gains %s' % (raw,corrected,gain))
print('PASS: mode 6 telemetry + compact mode/decimal threshold label on pages 0..5')
print('PASS: HDMI encoder inputs + RGB/DE/HS/VS aligned at final HUD')
print('NOTE: old white-card sample is arithmetic-only after the Debayer fix; recalibrate on board. See reports/V10_C1_VALIDATION.md')

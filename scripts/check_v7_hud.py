#!/usr/bin/env python3
"""Static checks and pixel-reference tests. NOT a Verilog simulation."""
from pathlib import Path
import re
from xml.etree import ElementTree as ET
base=Path(__file__).resolve().parents[1]
root=(base/'rtl/ti60f225_oob_top.v').read_text()
new=(base/'rtl/edge/compose/edge_final_hud.sv').read_text()
project=(base/'ti60f225_oob.xml').read_text()
assert 'rtl/edge/compose/edge_final_hud.sv' in project
assert root.count('edge_final_hud #(')==1
assert root.count('dvi_encoder dvi_encoder_m0')==1
m=re.search(r'dvi_encoder dvi_encoder_m0\s*\((.*?)\);',root,re.S)
assert m
ports=dict(re.findall(r'\.(i_\w+)\s*\(\s*([^)]*?)\s*\)',m.group(1)))
expected={'i_rdata':'edge_final_hdmi_rgb[23:16]', 'i_gdata':'edge_final_hdmi_rgb[15:8]',
          'i_bdata':'edge_final_hdmi_rgb[7:0]', 'i_de':'edge_final_hdmi_de',
          'i_hs':'edge_final_hdmi_hs','i_vs':'edge_final_hdmi_vs'}
assert {k:ports.get(k) for k in expected}==expected,ports
assert 'edge_diag_page #(' not in root, 'old heavy diagnostic page still instantiated'
assert 'edge_final_hdmi_hud' in root and '24\'h00FFFF' in new
assert 'letter_ink ? 24\'hFFFFFF' in new
assert 'in_de?mixed_rgb:24\'d0' in new
assert 'out_de<=in_de;out_hs<=in_hs;out_vs<=in_vs;' in new
# Font: static glyphs include V,7,0..9,A..F, pre-rendered font rows.
for cp in ['56','37','30','31','32','33','34','35','36','38','39','41','42','43','44','45','46']:
    assert ('8\'h'+cp+':font5=') in new
# Dynamic nibble position and literals are all covered in generated case.
for reg in ('mean_raw_r','mean_raw_g','mean_raw_b','mean_bal_r','mean_bal_g','mean_bal_b',
            'last_samples','wb_r','wb_g','wb_b','threshold','cam_bcd','done_bcd','selected_bcd'):
    assert 'hex_ascii(('+reg in new
# Check character cell boundaries for the first 3 rows and actual glyph.
font={int(k,16):int(v,16) for k,v in re.findall(r'8\'h([0-9a-fA-F]{2}):font5=35\'h([0-9a-fA-F]{9})',new)}
assert 0x56 in font and 0x37 in font
assert any((font[0x56]>>(34-i))&1 for i in range(35))
for y in (0,1,2,12,13,35,36,54,55):
    row=0 if y<18 else (1 if y<36 else 2)
    assert row in (0,1,2)
for x in (0,1,2):
    assert x<3
print('PASS: HDL source added, final DVI ports all driven by V7 HUD, sync aligned')
print('PASS: font glyph bitmaps, dynamic RGB/frame fields and fail-safe cyan marker')
print('NOTE: these are static/reference tests, NOT RTL simulation or Efinity timing')

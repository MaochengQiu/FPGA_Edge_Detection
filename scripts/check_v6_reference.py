#!/usr/bin/env python3
"""Standard-library offline reference and integration checks, NOT RTL simulation."""
from pathlib import Path
import re,json,sys
root=Path(__file__).resolve().parents[1]
hud=(root/'rtl/edge/compose/edge_diag_page.sv').read_text()
health=(root/'rtl/edge/compose/edge_video_health.sv').read_text()
top=(root/'rtl/ti60f225_oob_top.v').read_text()
ctrl=(root/'rtl/edge/control/img_control.sv').read_text()
assert 'input wire clk,rst_n,de,hs,vs' in hud
assert 'output reg out_de,out_hs,out_vs' in hud
for needle in ('out_de<=de;out_hs<=hs;out_vs<=vs;', 'out_rgb<=de?current_rgb:24\'d0;',
               "(display_mode==3'd0 || display_mode==3'd3 || display_mode==3'd6)",
               "24'hFFFFFF", "24'h111820", 'LEFT=24, TOP=14', 'ROWS=3'):
    assert needle in hud,needle
assert "out_rgb=24'h0d1825" not in hud
for s in ('mean_raw_r','mean_bal_r','wb_r','threshold','sample_valid','last_samples',
          'cam_bcd','done_bcd','selected_bcd','key_press_count','last_key','overflow_flag'):
    assert hud.count(s)>1, s
assert top.count('.display_mode(edge_display)')>=2
assert '.out_de(edge_final_hdmi_de)' in top and '.out_hs(edge_final_hdmi_hs)' in top and '.out_vs(edge_final_hdmi_vs)' in top
assert "wire legacy_hud_visible=(display_mode!=3'd0 && display_mode!=3'd3 && display_mode!=3'd6);" in health
assert 'pending_d==6' in ctrl and 'if(tuning_page)' in ctrl
assert (root/'sim/tb_diag_overlay.sv').is_file()
# Validate all three text rows at their source label-level and exactly one
# dynamic assignment per field/digit address. No other glyphs are drawn.
pat=re.compile(r"\{2'd(\d+),7'd(\d+)\}: letter=(.*?);")
look={}
for r,c,v in pat.findall(hud):
    r,c=int(r),int(c)
    assert (r,c) not in look,(r,c)
    look[(r,c)]=v
assert set(r for r,c in look)=={0,1,2}
assert max(c for r,c in look)<62
assert sum('hex_ascii' in v for v in look.values())==43
for key in ('cam_bcd','done_bcd','selected_bcd','mean_raw_r','mean_bal_r','wb_r','wb_g','wb_b'):
    assert any(key in v for v in look.values()),key
# Simulate glyph placement over synthetic RGB pixels based on actual compiled
# font masks/case values. This is a raster mathematical check, not Verilog RTL.
font=dict((int(c,16),int(v,16)) for c,v in re.findall(r"8'h([0-9a-f]+):font5=35'h([0-9a-f]+);",hud))
assert len(font)>=45
texts=[]
for row in range(3):
    line=''
    for col in range(62):
        v=look.get((row,col),"8'h20")
        if v.startswith("8'h"):
            line+=chr(int(v[3:],16))
        else:line+='0'
    texts.append(line.rstrip())
assert 'RAW R:' in texts[0] and 'OUT R:' in texts[0] and 'V:' in texts[0]
assert 'GAIN R:' in texts[1] and 'KEY:' in texts[1]
assert 'CAM:' in texts[2] and 'SCREEN:' in texts[2] and 'HOLD:' in texts[2]
# White sample with dark 2-pixel shadow and clear gutter in a synthetic video.
img=[['base']*64 for _ in range(64)]
for row in range(3):
    for col in range(3):
        ch=texts[row][col]
        glyph=font[ord(ch)]
        for fy in range(7):
            for fx in range(5):
                if (glyph>>(34-(fy*5+fx))) & 1:
                    x0=2+16*col+2*(fx+1);y0=3+16*row+2*fy
                    for dy in range(2):
                        for dx in range(2):
                            if x0+dx+2<64 and y0+dy+2<64:img[y0+dy+2][x0+dx+2]='shadow'
                            if x0+dx<64 and y0+dy<64:img[y0+dy][x0+dx]='white'
assert sum(a=='white' for row in img for a in row)>50
assert sum(a=='shadow' for row in img for a in row)>5
assert sum(a=='base' for row in img for a in row)>500
result={'version':'V6 transparent HDMI HUD','status':'PASS: source/port/coordinates/labels/pixel reference',
        'modes':[0,3,6],'rows':texts,'font_glyphs':len(font),
        'registered_video_signals':['RGB','DE','HS','VS'],
        'relative_screen_coverage':'48 of 1080 lines (~4.44% text ROI), untouched outside glyphs and shadows',
        'rtl_simulation':'NOT EXECUTED: iverilog unavailable',
        'efinity_synthesis':'NOT EXECUTED: Efinity unavailable','on_board':'NOT EXECUTED'}
(root/'reports/V6_REFERENCE.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n')
print('V6 STATIC/PIXEL REFERENCE PASS')
for i,x in enumerate(texts):print(i,x)

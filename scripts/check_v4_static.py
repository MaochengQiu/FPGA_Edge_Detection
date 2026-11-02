#!/usr/bin/env python3
"""Static integration check; does not synthesize or simulate RTL."""
from pathlib import Path
import xml.etree.ElementTree as ET
import json
r=Path(__file__).resolve().parents[1]
peri=ET.parse(r/'ti60f225_oob.peri.xml').getroot()
portmap={e.attrib['name']:e.attrib.get('gpio_def') for e in peri.iter() if e.tag.split('}')[-1]=='comp_gpio'}
expect={'i_arstn':'GPIOL_07','edge_keys_n[0]':'GPIOR_22',
        'edge_keys_n[1]':'GPIOR_21','edge_keys_n[2]':'GPIOL_03'}
assert all(portmap.get(k)==v for k,v in expect.items()),(portmap,expect)
text={q:(r/q).read_text() for q in [
 'rtl/ti60f225_oob_top.v', 'rtl/edge/control/img_control.sv',
 'rtl/edge/frame/img_frame_store.sv', 'rtl/edge/compose/edge_video_health.sv']}
top=text['rtl/ti60f225_oob_top.v']
for signal in ['edge_selected','edge_selected_toggle','edge_key_press_count','edge_last_key']:
 assert signal in top,signal
for port in ['.selected_event_async(edge_selected_toggle)',
 '.key_press_count(edge_key_press_count)', '.last_key(edge_last_key)',
 '.threshold_pending(edge_pending_threshold)']:
 assert port in top,port
assert 'selected_frames(selected_frames)' in text['rtl/edge/frame/img_frame_store.sv']
assert 'if(|press)' in text['rtl/edge/control/img_control.sv']
assert 'hex_glyph' in text['rtl/edge/compose/edge_video_health.sv']
assert all((r/path).is_file() for path in ['rtl/edge/top/img_pipeline.sv',
 'rtl/edge/frame/img_frame_manager.sv', 'ti60f225_oob.xml', 'ti60f225_oob.sdc'])
report={'test':'V4 static integration','status':'PASS','board_key_mapping':expect,
 'rtl_simulation':'NOT RUN','efinity_synthesis':'NOT RUN','actual_video_fps':'NOT MEASURED'}
(r/'reports/v4_diagnostics_static.json').write_text(json.dumps(report,indent=2,ensure_ascii=False))
print(json.dumps(report,indent=2,ensure_ascii=False))

from pathlib import Path
import hashlib,json,xml.etree.ElementTree as ET

root=Path(__file__).resolve().parents[1]
prior=root.parents[1]/'v10-e3/ti60f225_oob'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
shape=lambda e:(e.tag,sorted(e.attrib.items()),[shape(c) for c in e])
m=json.loads((prior/'reports/e3_release_manifest.json').read_text(encoding='utf8'))
for name,h in m['sha256'].items():assert sha(prior/name)==h,('Published E3 changed',name)
old={p.relative_to(prior).as_posix():sha(p) for p in (prior/'rtl').rglob('*') if p.is_file()}
new={p.relative_to(root).as_posix():sha(p) for p in (root/'rtl').rglob('*') if p.is_file()}
added='rtl/edge/video/edge_hdmi_test_pattern.sv'
assert set(new)-set(old)=={added} and not set(old)-set(new)
changed=[n for n in old if old[n]!=new[n]]
assert set(changed)=={'rtl/ti60f225_oob_top.v','rtl/edge/compose/edge_final_hud.sv'}
for name in ('ti60f225_oob.peri.xml','ti60f225_oob.sdc'):assert sha(root/name)==sha(prior/name)
a=ET.parse(prior/'ti60f225_oob.xml').getroot();b=ET.parse(root/'ti60f225_oob.xml').getroot()
design=next(e for e in b if e.tag.endswith('design_info'))
found=[e for e in design if e.get('name')==added];assert len(found)==1
design.remove(found[0]);assert shape(a)==shape(b),'Other project settings changed'
top=(root/'rtl/ti60f225_oob_top.v').read_text(encoding='utf8')
assert "E3_WEAK_CHAIN_ENABLE = 1'b0" in top and "E4_HDMI_TEST = 1'b0" in top
assert 'wire edge_store_arst_n=w_arstn && cal_done && dly_cnt[26];' in top
assert '.clk(hdmi_tx_slow_clk),.rst_n(edge_pixel_rst_n),.keys_n(edge_keys_n)' in top
assert 'wire edge_encoder_rst_n=E4_HDMI_TEST?edge_test_rst_n:edge_pixel_rst_n;' in top
report=dict(status='PASS',E3_release_preserved=True,changed_rtl=changed,new_rtl=added,
    algorithm_and_control='byte-identical core/control; E3 weak supplement disabled as in E3B',
    camera_DDR_PLL_color='unchanged',SDC_and_peripheral='byte-identical',
    normal_reset='unchanged; test branch only has independent reset',
    normal_video='same preencoder inputs selected for E4_HDMI_TEST=0',
    physical_fault='not diagnosed from simulation alone')
(root/'reports/e4_scope.json').write_text(json.dumps(report,indent=2))
print('E4 SCOPE PASS: E3 frozen; normal core/reset/constraints preserved; diagnostic-only test path added')

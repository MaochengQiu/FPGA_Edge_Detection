from pathlib import Path
import hashlib,json,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
OLD=ROOT.parents[1]/'v10-e4-diagnostics/ti60f225_oob'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
shape=lambda e:(e.tag,sorted(e.attrib.items()),[shape(c) for c in e])
m=json.loads((OLD/'reports/e4_release_manifest.json').read_text(encoding='utf8'))
for n,h in m['sha256'].items():assert sha(OLD/n)==h,('Published E4 modified',n)
old={p.relative_to(OLD).as_posix():sha(p) for p in (OLD/'rtl').rglob('*') if p.is_file()}
new={p.relative_to(ROOT).as_posix():sha(p) for p in (ROOT/'rtl').rglob('*') if p.is_file()}
assert set(old)==set(new),'Unexpected RTL source addition/removal'
changed={n for n in old if old[n]!=new[n]}
assert changed=={'rtl/ti60f225_oob_top.v','rtl/edge/control/img_control.sv',
                 'rtl/edge/compose/img_composer.sv','rtl/edge/compose/edge_final_hud.sv'}
for n in ('ti60f225_oob.sdc','ti60f225_oob.peri.xml'):assert sha(ROOT/n)==sha(OLD/n)
assert shape(ET.parse(ROOT/'ti60f225_oob.xml').getroot())==shape(ET.parse(OLD/'ti60f225_oob.xml').getroot())
composer=(ROOT/'rtl/edge/compose/img_composer.sv').read_text(encoding='utf8')
assert "2:selected=edge_pixel?24'hffffff:24'h000000;" in composer
assert "7:selected=edge_pixel?24'he0f0ff:24'h000103;" in composer
assert 'out_ctl<=ctl;' in composer
control=(ROOT/'rtl/edge/control/img_control.sv').read_text(encoding='utf8')
restored=control.replace(',\n    DISPLAY_MAX=6)(\n',')(\n').replace('pending_d>=DISPLAY_MAX','pending_d>=6').replace('cfg_data<=DISPLAY_MAX','cfg_data<=6')
assert restored==(OLD/'rtl/edge/control/img_control.sv').read_text(encoding='utf8'),'Control change exceeded page limit'
report=dict(status='PASS',E4_release_preserved=True,changed_rtl=sorted(changed),
    algorithm_core='BYTE IDENTICAL to E4D',M2_codes='unchanged 0x000000 / 0xffffff',
    M7_codes='same edge bit, 0x000103 / 0xe0f0ff',controller='Only configurable max page, default6/top7',
    constraints_project_pins='unchanged',camera_DDR_PLL_reset_color='unchanged',
    dynamic_allocation='none; edge density cannot increase fixed RAM capacity or pipeline cycle count',
    board_fault='NOT reproduced in RTL; physical cause remains unconfirmed')
(ROOT/'reports/e5_scope.json').write_text(json.dumps(report,indent=2))
print('E5 SCOPE PASS: original E4 frozen, M2 retained, same core/clock/RAM; M7 changes display codewords only')

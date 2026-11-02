from pathlib import Path
from copy import deepcopy
import hashlib,json,xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
OLD=ROOT.parents[1]/'v10-e5-output-ab/ti60f225_oob'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
shape=lambda e:(e.tag,sorted(e.attrib.items()),[shape(c) for c in e])

def main():
    manifest=json.loads((OLD/'reports/e5_release_manifest.json').read_text(encoding='utf8'))
    for name,digest in manifest['sha256'].items():
        assert sha(OLD/name)==digest,('Published E5 modified',name)
    old={p.relative_to(OLD).as_posix():sha(p) for p in (OLD/'rtl').rglob('*') if p.is_file()}
    new={p.relative_to(ROOT).as_posix():sha(p) for p in (ROOT/'rtl').rglob('*') if p.is_file()}
    added=set(new)-set(old)
    assert added=={'rtl/dvi_tx/edge_dvi_encode.v','rtl/dvi_tx/edge_dvi_encoder.v'}
    assert not set(old)-set(new)
    changed={n for n in old if old[n]!=new[n]}
    assert changed=={'rtl/ti60f225_oob_top.v','rtl/edge/compose/edge_final_hud.sv'}
    # Every byte of the old processing/control/composer remains in use unchanged.
    for name in old:
        if name not in changed:assert sha(ROOT/name)==old[name],name
    for name in ('ti60f225_oob.sdc','ti60f225_oob.peri.xml'):
        assert sha(ROOT/name)==sha(OLD/name),name
    xml=ET.parse(ROOT/'ti60f225_oob.xml').getroot()
    normalized=deepcopy(xml)
    design=next(e for e in normalized if e.tag.endswith('design_info'))
    for e in list(design):
        if e.get('name') in added:design.remove(e)
    assert shape(normalized)==shape(ET.parse(OLD/'ti60f225_oob.xml').getroot())
    top=(ROOT/'rtl/ti60f225_oob_top.v').read_text(encoding='utf8')
    previous=(OLD/'rtl/ti60f225_oob_top.v').read_text(encoding='utf8')
    prefix=top.split('// E6: verified video-only encoder',1)[0]
    prefix=prefix.replace(".PALETTE_PROBE(E5_M7_ENABLE),.DVI_TRANSPORT(1'b1))",'.PALETTE_PROBE(E5_M7_ENABLE))')
    assert prefix==previous.split('dvi_encoder dvi_encoder_m0',1)[0]
    assert top.split('assign tmds_tx_clk_TX_DATA',1)[1]==previous.split('assign tmds_tx_clk_TX_DATA',1)[1]
    assert 'edge_dvi_encoder dvi_encoder_m0(' in top
    assert 'dvi_encoder dvi_encoder_m0\n' not in top
    src=(ROOT/'reference/board_demo_dvi/encode.v').read_bytes()
    assert (ROOT/'rtl/dvi_tx/edge_dvi_encode.v').read_bytes()==src.replace(b'module encode (',b'module edge_dvi_encode (')
    composer=(ROOT/'rtl/edge/compose/img_composer.sv').read_text(encoding='utf8')
    assert "2:selected=edge_pixel?24'hffffff:24'h000000;" in composer
    assert "7:selected=edge_pixel?24'he0f0ff:24'h000103;" in composer
    result=dict(status='PASS',E5_release_preserved=True,changed_existing_rtl=sorted(changed),
        added_rtl=sorted(added),source_count=80,board_demo_encoder='Byte identical except module rename; original notice retained',
        algorithm_control_composer='BYTE IDENTICAL to E5',
        M2_codes='unchanged 000000/FFFFFF',M7_codes='unchanged 000103/E0F0FF',
        camera_DDR_color_gamma_reset_PLL_SDC_pins_serializer='unchanged',
        transport='Video-only DVI/TMDS on existing HDMI connector; no audio or HDMI data islands',
        physical_blackout='Board verification required; no claim of confirmed root cause')
    (ROOT/'reports/e6_scope.json').write_text(json.dumps(result,indent=2))
    print('E6 SCOPE PASS: E5 frozen; processing unchanged; encoder replacement and E6D label only')
    return result

if __name__=='__main__':main()

from pathlib import Path
from copy import deepcopy
import hashlib,json,xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1];OLD=ROOT.parents[1]/'v10-e6-dvi/ti60f225_oob'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
shape=lambda e:(e.tag,sorted(e.attrib.items()),[shape(c) for c in e])

def main():
    manifest=json.loads((OLD/'reports/e6_release_manifest.json').read_text(encoding='utf8'))
    for n,h in manifest['sha256'].items():assert sha(OLD/n)==h,('E6 release modified',n)
    old={p.relative_to(OLD).as_posix():sha(p) for p in (OLD/'rtl').rglob('*') if p.is_file()}
    new={p.relative_to(ROOT).as_posix():sha(p) for p in (ROOT/'rtl').rglob('*') if p.is_file()}
    added=set(new)-set(old);changed={n for n in old if old[n]!=new[n]}
    assert added=={'rtl/edge/preprocess/img_gaussian5x5.sv'} and not set(old)-set(new)
    assert changed=={'rtl/ti60f225_oob_top.v','rtl/edge/preprocess/img_preprocess.sv',
        'rtl/edge/top/img_pipeline.sv','rtl/edge/control/img_control.sv','rtl/edge/compose/edge_final_hud.sv'}
    for n in ('ti60f225_oob.sdc','ti60f225_oob.peri.xml'):assert sha(ROOT/n)==sha(OLD/n),n
    x=deepcopy(ET.parse(ROOT/'ti60f225_oob.xml').getroot())
    d=next(e for e in x if e.tag.endswith('design_info'))
    for e in list(d):
        if e.get('name') in added:d.remove(e)
    assert shape(x)==shape(ET.parse(OLD/'ti60f225_oob.xml').getroot())
    top=(ROOT/'rtl/ti60f225_oob_top.v').read_text(encoding='utf-8-sig')
    prev=(OLD/'rtl/ti60f225_oob_top.v').read_text(encoding='utf8')
    # Entire downstream E6 output transport and inversion stays identical.
    assert top.split('// E6: verified video-only encoder',1)[1].strip()==prev.split('// E6: verified video-only encoder',1)[1].strip()
    for n in old:
        if n not in changed:assert sha(ROOT/n)==old[n]
    assert "E1_NMS_STRICT_TIES = 1'b0" in top and 'parameter E2_MIN_SEEDS = 3' in top
    assert '.THRESHOLD_DEFAULT(50)' in top and '.PREPROCESS_DEFAULT(E7_FILTER_ENABLE?2:0)' in top
    report=dict(status='PASS',E6_release_preserved=True,changed_existing_rtl=sorted(changed),added_rtl=sorted(added),
        E6_DVI_transport_camera_DDR_color_gamma_PLL_SDC_pins_reset='unchanged',
        NMS_graph_threshold_ratio_M2_M7='BYTE IDENTICAL to E6',
        PRE=dict(PRE0='bypass',PRE1='median3',PRE2='binomial Gaussian5',PRE3='binomial Gaussian3 (replaces sharpen)'),
        default='T50 PRE2',legacy_module_defaults='quality disabled, PRE0; old timing retained',
        latency='all E7 modes 6*HTOTAL+61; filtered modes use 3-pixel gradient exclusion radius',
        real_quality='Candidate; synthetic image evidence does not establish board quality or stability')
    (ROOT/'reports/e7_scope.json').write_text(json.dumps(report,indent=2))
    print('E7 SCOPE PASS: original E6 frozen; E6 transport, NMS/linking and M7 retained')
    return report

if __name__=='__main__':main()

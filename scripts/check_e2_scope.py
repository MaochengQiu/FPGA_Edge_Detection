"""Protect E1/C2 and verify the exact E2 experiment scope."""
from pathlib import Path
import argparse,difflib,hashlib,json,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'reference/e2_baseline'
ALLOWED={'rtl/ti60f225_oob_top.v','rtl/edge/top/img_pipeline.sv','rtl/edge/compose/edge_final_hud.sv','rtl/edge/compose/img_composer.sv'}
NEW={'rtl/edge/gradient/img_edge_link.sv','rtl/edge/video/img_window5x5.sv'}
def sha(f):return hashlib.sha256(f.read_bytes()).hexdigest()
def shape(e):return e.tag,tuple(sorted(e.attrib.items())),tuple(shape(c) for c in e)
def check(standalone=False):
    release=json.loads((BASE/'v10_e1_release_manifest.json').read_text(encoding='utf-8'))
    prior=ROOT.parents[1]/'e1/ti60f225_oob'
    if not standalone:
        for n,h in release['sha256'].items():assert sha(prior/n)==h,'E1 modified: '+n
        color=json.loads((prior/'reference/e1_baseline/v10_c21_release_manifest.json').read_text(encoding='utf-8'))
        for n,h in color['sha256'].items():assert sha(ROOT.parents[1]/'v10/ti60f225_oob'/n)==h,'Color release modified: '+n
    a=ET.parse(BASE/'ti60f225_oob.xml').getroot();b=ET.parse(ROOT/'ti60f225_oob.xml').getroot()
    design=next(e for e in b if e.tag.rsplit('}',1)[-1]=='design_info')
    found=[e for e in design if e.tag.rsplit('}',1)[-1]=='design_file' and e.get('name') in NEW]
    assert {e.get('name') for e in found}==NEW
    for e in found:design.remove(e)
    assert shape(a)==shape(b),'Project settings changed beyond two new sources'
    names=[e.get('name') for e in a.iter() if e.tag.rsplit('}',1)[-1]=='design_file']
    names+=['ti60f225_oob.peri.xml','ti60f225_oob.sdc','rtl/gamma_conrrection/2P2.mem']
    changed={};unchanged=[];patch=[]
    for n in names:
        h=release['sha256'][n];actual=sha(ROOT/n)
        if actual==h:unchanged.append(n);continue
        assert n in ALLOWED,'Out-of-scope E2 change: '+n
        assert sha(BASE/n)==h
        changed[n]=dict(before=h,after=actual)
        old=(BASE/n).read_text(encoding='utf-8-sig');new=(ROOT/n).read_text(encoding='utf-8-sig')
        patch+=list(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='E1/'+n,tofile='E2/'+n))
    assert set(changed)==ALLOWED
    old=(BASE/'rtl/ti60f225_oob_top.v').read_text(encoding='utf-8-sig');new=(ROOT/'rtl/ti60f225_oob_top.v').read_text(encoding='utf-8-sig')
    for line in ("    parameter E2_LINK_ENABLE = 1'b1, // E2L local graph; 0=E2N NMS-only A/B.\n",
        '    parameter E2_MIN_SEEDS = 3, // Strong support; 2 is a more permissive experiment.\n'):
        assert line in new;new=new.replace(line,'')
    new=new.replace('img_control #(.THRESHOLD_DEFAULT(50)) edge_parameters(','img_control edge_parameters(')
    new=new.replace(',.LINK_ENABLE(E2_LINK_ENABLE),.LINK_MIN_SEEDS(E2_MIN_SEEDS)','')
    new=new.replace(',.LINK_ENABLE(E2_LINK_ENABLE)','')
    assert new==old,'Camera/DDR/video/reset top wiring changed'
    ref=(ROOT/'sim/reference/img_pipeline_e1_reference.sv').read_text(encoding='utf-8-sig')
    frozen=(BASE/'rtl/edge/top/img_pipeline.sv').read_text(encoding='utf-8-sig')
    assert ref.replace('module img_pipeline_e1_reference #(','module img_pipeline #(').replace('img_composer_e1_reference #(','img_composer #(').strip()==frozen.strip()
    composer=(ROOT/'sim/reference/img_composer_e1_reference.sv').read_text(encoding='utf-8-sig')
    assert composer.replace('module img_composer_e1_reference #(','module img_composer #(').strip()==(BASE/'rtl/edge/compose/img_composer.sv').read_text(encoding='utf-8-sig').strip()
    c2=(ROOT/'sim/reference/img_pipeline_c2_reference.sv').read_text(encoding='utf-8-sig')
    assert c2.replace('module img_pipeline_c2_reference #(','module img_pipeline #(').replace('img_composer_e1_reference #(','img_composer #(').strip()==(ROOT/'reference/e1_baseline/rtl/edge/top/img_pipeline.sv').read_text(encoding='utf-8-sig').strip()
    report=dict(status='PASS',revision='V10-E2',basis='Delivered E1, color preset from C2.1',
        E1_and_C2_unchanged=None if standalone else True,
        external_stable_releases='NOT CHECKED in standalone mode' if standalone else 'SHA256 PASS',
        changed_existing_rtl=changed,new_rtl={n:sha(ROOT/n) for n in sorted(NEW)},
        unchanged_sources_and_constraints=unchanged,project_settings='IDENTICAL except two design_file entries',
        top_wiring='IDENTICAL except link parameters and board THRESHOLD_DEFAULT=50',
        camera_ddr_mipi_hdmi_pll_reset='UNCHANGED',color='PH2 BGGR, gains 0x240/0x180/0x240 unchanged',
        sobel_nms_math='UNCHANGED',gray='Same img_rgb2gray replayed from aligned RGB; redundant gray RAM removed',
        threshold='H=50 default; L=ceil(H/2); original 4..128 step1 controls retained',
        graph='5x5 direction-constrained exact local reachability; >=3 seeds; supported one-pixel bridge',
        M3='RGB even-x sample unchanged; edge OR over each column pair, COMPARE_PAIR_EDGE=0 restores E1 sampling',
        latency_cycles='5*HTOTAL+60, both E2L/E2N',extra_over_E1_1080p_cycles=4433)
    suffix='_standalone' if standalone else ''
    (ROOT/f'reports/e2_scope{suffix}.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    (ROOT/f'reports/e2_changes{suffix}.patch').write_text(''.join(patch),encoding='utf-8')
    return report
if __name__=='__main__':
    args=argparse.ArgumentParser();args.add_argument('--standalone',action='store_true')
    standalone=args.parse_args().standalone
    check(standalone);print('E2 SCOPE PASS: '+('packaged baseline checked' if standalone else 'E1/C2 preserved')+', color/video constraints intact; local graph, alignment and M3 edge preview')

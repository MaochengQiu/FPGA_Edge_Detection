"""Verify isolated E1 changes and prove the stable color project is intact."""
from pathlib import Path
import difflib,hashlib,json,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'reference/e1_baseline'
ALLOWED={'rtl/ti60f225_oob_top.v','rtl/edge/top/img_pipeline.sv','rtl/edge/compose/edge_final_hud.sv'}
NEW='rtl/edge/gradient/img_nms.sv'
def sha(f):return hashlib.sha256(f.read_bytes()).hexdigest()
def shape(e):return e.tag,tuple(sorted(e.attrib.items())),tuple(shape(c) for c in e)
def check():
    release=json.loads((BASE/'v10_c21_release_manifest.json').read_text(encoding='utf-8'))
    stable=ROOT.parents[1]/'v10/ti60f225_oob'
    for name,digest in release['sha256'].items():assert sha(stable/name)==digest,'Stable C2/C2.1 modified: '+name
    old_xml=ET.parse(BASE/'ti60f225_oob.xml').getroot();new_xml=ET.parse(ROOT/'ti60f225_oob.xml').getroot()
    additions=[e for e in new_xml.iter() if e.tag.rsplit('}',1)[-1]=='design_file' and e.get('name')==NEW]
    assert len(additions)==1
    design=next(e for e in new_xml if e.tag.rsplit('}',1)[-1]=='design_info');design.remove(additions[0])
    assert shape(old_xml)==shape(new_xml),'Project changed beyond adding NMS source'
    names=[e.get('name') for e in old_xml.iter() if e.tag.rsplit('}',1)[-1]=='design_file']
    names+=['ti60f225_oob.peri.xml','ti60f225_oob.sdc','rtl/gamma_conrrection/2P2.mem']
    changed={};unchanged=[];patch=[]
    for name in names:
        digest=release['sha256'][name];actual=sha(ROOT/name)
        if actual==digest:unchanged.append(name);continue
        assert name in ALLOWED,'Out-of-scope E1 change: '+name
        assert sha(BASE/name)==digest,'Changed baseline: '+name
        changed[name]=dict(before=digest,after=actual)
        old=(BASE/name).read_text(encoding='utf-8-sig');new=(ROOT/name).read_text(encoding='utf-8-sig')
        patch+=list(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='C2.1/'+name,tofile='E1/'+name))
    assert set(changed)==ALLOWED
    old=(BASE/'rtl/ti60f225_oob_top.v').read_text(encoding='utf-8-sig')
    new=(ROOT/'rtl/ti60f225_oob_top.v').read_text(encoding='utf-8-sig')
    new=new.replace("    parameter E1_NMS_ENABLE = 1'b1, // E1 A/B: 1=NMS, 0=original Sobel decision.\n",'')
    new=new.replace("    parameter E1_NMS_STRICT_TIES = 1'b0, // Keep equal maxima for curve continuity.\n",'')
    new=new.replace(',.NMS_ENABLE(E1_NMS_ENABLE),.NMS_STRICT_TIES(E1_NMS_STRICT_TIES)','')
    new=new.replace(',.NMS_ENABLE(E1_NMS_ENABLE)','')
    assert old==new,'Top video/camera/reset wiring changed'
    frozen=(BASE/'rtl/edge/top/img_pipeline.sv').read_text(encoding='utf-8-sig')
    reference=(ROOT/'sim/reference/img_pipeline_c2_reference.sv').read_text(encoding='utf-8-sig')
    assert reference.replace('module img_pipeline_c2_reference #(','module img_pipeline #(').strip()==frozen.strip(),'C2 numerical reference changed'
    for name in ('rtl/edge/control/img_control.sv','rtl/debayer/raw_to_rgb.v','rtl/debayer/debayer_top_2to1.v',
        'rtl/edge/gradient/img_sobel_gradient.sv','rtl/edge/compose/edge_color_balance.sv'):
        assert sha(ROOT/name)==release['sha256'][name],name
    report=dict(status='PASS',revision='V10-E1',basis='Color-complete C2 series, delivered C2.1 preset manifest',
        stable_project_unchanged=True,changed_existing_rtl=changed,new_rtl={NEW:sha(ROOT/NEW)},
        unchanged_sources_and_constraints=unchanged,project_settings='IDENTICAL except one design_file',
        top_wiring='IDENTICAL except NMS parameters on kernel and HUD',
        color_preset='UNCHANGED PH2 BGGR, RGB gains 0x240/0x180/0x240',
        camera_ddr_mipi_hdmi_pll_reset='UNCHANGED',sobel_arithmetic='UNCHANGED',
        new_kernel_latency_cycles='3*HTOTAL+27, both E1N/E1S',added_latency_cycles=2205)
    (ROOT/'reports/e1_scope.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    (ROOT/'reports/e1_changes.patch').write_text(''.join(patch),encoding='utf-8')
    return report
if __name__=='__main__':
    check();print('E1 SCOPE PASS: stable C2/C2.1 untouched; three RTL edits + one NMS source; color/video interfaces preserved')

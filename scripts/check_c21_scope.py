"""Preserve delivered C2 and verify the in-place C2.1 preset-only change."""
from pathlib import Path
import difflib, hashlib, json, shutil, sys, xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'reference/c21_baseline'
ALLOWED={'rtl/edge/control/img_control.sv','rtl/edge/compose/edge_final_hud.sv'}

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def shape(e):return e.tag,tuple(sorted(e.attrib.items())),tuple(shape(c) for c in e)

def prepare():
    assert not BASE.exists(),'Existing C2 rollback must be preserved'
    release=json.loads((ROOT/'reports/v10_c2_release_manifest.json').read_text(encoding='utf-8'))
    for name,digest in release['sha256'].items():assert sha(ROOT/name)==digest,name
    package=ROOT.parents[1]/'packages/ti60f225_oob_V10_C2_color.zip'
    assert sha(package)=='839e70cbc06104e55a37ed75e94ac4933dbe5078b95edc42797cc3be14b5d606'
    names=sorted(ALLOWED)+['ti60f225_oob.xml','README.md','sim/tb_control_white_balance.sv','sim/tb_final_hud.sv']
    for name in names:
        dest=BASE/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/name,dest)
    shutil.copy2(ROOT/'reports/v10_c2_release_manifest.json',BASE/'v10_c2_release_manifest.json')
    photo=Path(r'C:\Users\张轩宇\Documents\xwechat_files\wxid_yma1yzr3ss3422_c133\temp\RWTemp\2026-10\37352a1025002e697bda1ccb8978a21e\aadf9c22f253214ff472ab9a71884787.jpg')
    dest=ROOT/'reference/c21_board_feedback';dest.mkdir(exist_ok=True)
    shutil.copy2(photo,dest/photo.name)
    feedback=dict(basis='User confirms PH=2; attached C2 hardware photo',
        bayer_phase=2,bayer_name='BGGR',wb_q8_hex=['240','180','240'],wb_gain=[2.25,1.5,2.25],
        raw_mean_hex=['32','3F','2D'],out_mean_hex=['5E','57','54'],
        clipped_hex=['00F','00F','00F'],clipped_each=15,samples=256,
        cam=30,ddr=30,screen_new_frames=30,errors='R0 L0 O0 U0 D0',
        scene='Camera points at a bright ceiling luminaire; not a uniform white/gray card',
        conclusion='PH2 accepted for this existing sensor configuration; user gains stored as a starting preset, not universal white balance',
        photo=photo.name,photo_sha256=sha(dest/photo.name))
    (dest/'feedback.json').write_text(json.dumps(feedback,indent=2,ensure_ascii=False),encoding='utf-8')
    print(f'C2 BASELINE PASS: {len(release["sha256"])} hashes verified; rollback and user feedback preserved')

def check():
    release=json.loads((BASE/'v10_c2_release_manifest.json').read_text(encoding='utf-8'))
    assert (ROOT/'reports/v10_c2_release_manifest.json').read_bytes()==(BASE/'v10_c2_release_manifest.json').read_bytes(),'C2 manifest changed'
    assert sha(BASE/'ti60f225_oob.xml')==release['sha256']['ti60f225_oob.xml']
    assert shape(ET.parse(ROOT/'ti60f225_oob.xml').getroot())==shape(ET.parse(BASE/'ti60f225_oob.xml').getroot()),'Project settings changed'
    compiled=[e.attrib['name'] for e in ET.parse(BASE/'ti60f225_oob.xml').getroot().iter() if e.tag.rsplit('}',1)[-1]=='design_file']
    names=compiled+['ti60f225_oob.peri.xml','ti60f225_oob.sdc','rtl/gamma_conrrection/2P2.mem',
        'programming/ti60f225_oob_V10_C2.bit','programming/ti60f225_oob_V10_C2.hex']
    changed={};unchanged=[];patch=[]
    for name in names:
        digest=release['sha256'][name];actual=sha(ROOT/name)
        if actual==digest:unchanged.append(name);continue
        assert name in ALLOWED,'Out-of-scope change: '+name
        assert sha(BASE/name)==digest,'C2 rollback changed'
        changed[name]=dict(before=digest,after=actual)
        old=(BASE/name).read_text(encoding='utf-8-sig');new=(ROOT/name).read_text(encoding='utf-8-sig')
        patch.extend(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='V10-C2/'+name,tofile='V10-C2.1/'+name))
    assert set(changed)==ALLOWED,'Unexpected C2.1 RTL change set'
    old=(BASE/'rtl/edge/control/img_control.sv').read_text(encoding='utf-8-sig')
    new=(ROOT/'rtl/edge/control/img_control.sv').read_text(encoding='utf-8-sig')
    # Remove comments: exactly four reset constants may change, no control logic.
    import re
    strip=lambda s:re.sub(r'//[^\n]*','',s)
    restored=new.replace("wb_r<=10'h240;wb_g<=10'h180;wb_b<=10'h240;wb_selected<=0;",
        "wb_r<=10'h100;wb_g<=10'h100;wb_b<=10'h100;wb_selected<=0;")
    restored=restored.replace("bayer_phase<=2'd2;","bayer_phase<=2'd1;")
    assert strip(restored)==strip(old),'Controller behavior changed beyond reset defaults'
    old=(BASE/'rtl/edge/compose/edge_final_hud.sv').read_text(encoding='utf-8-sig')
    new=(ROOT/'rtl/edge/compose/edge_final_hud.sv').read_text(encoding='utf-8-sig')
    assert old.split('    reg [7:0] letter;',1)[0]==new.split('    reg [7:0] letter;',1)[0],'HUD counters/font timing changed'
    assert old.split('    wire letter_ink=',1)[1]==new.split('    wire letter_ink=',1)[1],'HUD/reference RGB or output timing changed'
    result=dict(status='PASS',revision='V10-C2.1',basis='Delivered C2 SHA256 manifest',in_place_project=True,
        changed_color_sources=changed,unchanged_release_files=unchanged,
        control_logic='IDENTICAL after replacing four reset constants',project_settings='IDENTICAL',
        debayer_rgb_precision_gray_sobel_preprocess_composer='UNCHANGED',
        ddr_mipi_hdmi_pll_reset_exposure='UNCHANGED',
        default_phase=2,default_pattern='BGGR',wb_default_q8_hex=['240','180','240'],
        calibration='User-confirmed phase, user-provided gains; neutral-card validation pending')
    (ROOT/'reports/c21_scope.json').write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding='utf-8')
    (ROOT/'reports/c21_changes.patch').write_text(''.join(patch),encoding='utf-8')
    return result

if __name__=='__main__':
    if sys.argv[1:]==['--prepare']:prepare()
    else:
        check();print('C2.1 SCOPE PASS: reset preset + HUD identification only; all video/algorithm logic unchanged')
